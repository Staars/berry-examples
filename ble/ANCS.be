#------------------------------------------------------------------------------#
# ANCS Demo for Tasmota BLE driver (Berry)
# ESP32 = Notification Consumer (NC)
#
# Simplified stable version:
# - Advertise with ANCS service solicitation
# - Add HID-style advertising cue (UUID 0x1812)
# - Add GAP Appearance characteristic (Generic HID = 0x03C0)
# - On accepted-link connect, subscribe DS immediately to provoke pairing
# - On first authentication callback, save bond once if not persisted yet
# - On init, restore saved bond with BLE.store() if present
# - Subscribe DS first, then NS
# - Parse notifications defensively
# - Serialize Control Point writes
# - Queue notifications by UID and emit one JSON line per notification
#------------------------------------------------------------------------------#

import BLE
import string
import persist
import json

var cbuf = bytes(-255)

var NAME     = "nimble"
var ANCS_SVC = "7905F431-B5CE-4E99-A40F-4B1E122D00D0"
var NS_CHR   = "9FBF120D-6301-42D9-8C58-25E699A21DBD"  # Notification Source
var CP_CHR   = "69D1D8F3-45E1-49A8-9821-9BBDFDAAD9D9"  # Control Point
var DS_CHR   = "22EAC6E9-24D6-4BB5-BE44-B36ACE7C7BFB"  # Data Source

# HID / GAP cues modeled after ESP-IDF ANCS example
var GAP_SVC            = "1800"
var GAP_CHR_NAME       = "2A00"
var GAP_CHR_APPEAR     = "2A01"
var HID_SVC16          = "1812"
var APPEAR_GENERIC_HID = 0x03C0

# 16-bit slices returned by current C++ layer
var NS_UID = 0x120D
var DS_UID = 0xC6E9

var CATEGORIES = [
  "Other", "Incoming Call", "Missed Call", "Voicemail",
  "Social", "Schedule", "Email", "News",
  "Health & Fitness", "Business & Finance", "Location", "Entertainment"
]

class Notification
    var uid
    var uid_b
    var event_id
    var event
    var flags
    var category_id
    var category
    var count
    var app_id
    var title
    var message
    var date
    var requested

    def init(uid_b, event_id, flags, category_id, count, category)
        self.uid         = uid_b.tohex()
        self.uid_b       = uid_b
        self.event_id    = event_id
        self.flags       = flags
        self.category_id = category_id
        self.category    = category
        self.count       = count
        self.app_id      = nil
        self.title       = nil
        self.message     = nil
        self.date        = nil
        self.requested   = false

        if event_id == 0
            self.event = "new"
        elif event_id == 1
            self.event = "modified"
        elif event_id == 2
            self.event = "removed"
        else
            self.event = str(event_id)
        end
    end

    def set_attr(attr_id, value)
        if    attr_id == 0x00  self.app_id  = value
        elif  attr_id == 0x01  self.title   = value
        elif  attr_id == 0x03  self.message = value
        elif  attr_id == 0x05  self.date    = value
        end
    end

    def complete()
        return self.app_id != nil && self.title != nil && self.message != nil && self.date != nil
    end

    def to_json()
        return json.dump({
            "uid":         self.uid,
            "event_id":    self.event_id,
            "event":       self.event,
            "flags":       self.flags,
            "category_id": self.category_id,
            "category":    self.category,
            "count":       self.count,
            "app_id":      self.app_id,
            "title":       self.title,
            "message":     self.message,
            "date":        self.date
        })
    end
end

class ANCS : Driver
    var current_func

    var latest_uid
    var peer_mac

    var subscribed_ds
    var subscribed_ns
    var ready

    var subscribe_pending
    var auth_retry_done

    var cp_busy
    var cp_t0
    var attr_phase

    var bond_blob
    var bond_key

    var pending
    var active_uid

    def init()
        import cb
        var sp = cb.gen_cb(/e,o,u,h -> self.ble_cb(e,o,u,h))
        BLE.conn_cb(sp, cbuf)

        self.latest_uid = bytes(-4)
        self.peer_mac   = bytes(-6)
        self.bond_blob  = nil
        self.bond_key   = "ancs_bond"
        self.pending    = {}
        self.active_uid = nil

        self.restore_bond()

        self.reset_session()
        tasmota.add_fast_loop(/-> BLE.loop())
        self.current_func = /-> self.startup()
        log("ANCS: Starting BLE ANCS consumer", 2)
    end

    def every_50ms()
        self.current_func()
    end

    def wait()
    end

    def reset_session()
        self.subscribed_ds     = false
        self.subscribed_ns     = false
        self.ready             = false
        self.subscribe_pending = false
        self.auth_retry_done   = false
        self.cp_busy           = false
        self.cp_t0             = 0
        self.attr_phase        = -1
        self.pending           = {}
        self.active_uid        = nil
    end

    def load_bond_blob()
        if !persist.has(self.bond_key)
            return nil
        end

        var s = persist.find(self.bond_key)
        if s == nil || s == ""
            return nil
        end

        return bytes().fromb64(s)
    end

    def save_bond_blob_once(blob)
        if blob == nil || blob.size() == 0
            return
        end

        if persist.has(self.bond_key)
            self.bond_blob = blob
            return
        end

        var s = blob.tob64()
        persist.setmember(self.bond_key, s)
        persist.save()
        self.bond_blob = blob

        log(f"ANCS: Bond record persisted len={blob.size()}", 2)
    end

    def clear_bond_blob()
        if persist.has(self.bond_key)
            persist.remove(self.bond_key)
            persist.save()
        end
        self.bond_blob = nil
    end

    def restore_bond()
        if !persist.has(self.bond_key)
            log("ANCS: No saved bond record", 3)
            return
        end

        var blob = self.load_bond_blob()
        if blob != nil && blob.size() > 0
            self.bond_blob = blob
            BLE.store(blob)
            log(f"ANCS: Restored bond record len={blob.size()}", 2)
        else
            log("ANCS: Saved bond key invalid/empty", 1)
        end
    end

    def emit_notification(uid)
        var notif = self.pending.find(uid)
        if notif == nil
            return
        end

        log(notif.to_json(), 2)
        self.pending.remove(uid)

        if self.active_uid == uid
            self.active_uid = nil
            self.attr_phase = -1
        end

        self.start_next_notification()
    end

    def start_next_notification()
        if !self.ready || self.cp_busy || self.active_uid != nil
            return
        end

        for uid : self.pending.keys()
            var notif = self.pending[uid]
            if notif != nil && notif.event_id == 0 && !notif.requested
                notif.requested = true
                self.active_uid = uid
                self.attr_phase = 0
                self.request_next_attribute()
                return
            end
        end
    end

    #--------------------#
    # Main BLE callback
    #--------------------#

    def ble_cb(error, op, uuid, handle)
        # log(f"ANCS: cb error={error} op={op} uuid={uuid} handle={handle}", 4)

        if error != 0
            if op == 3
                self.subscribe_pending = false
            elif op == 2
                self.cp_busy = false
            end
            log(f"ANCS: BLE error error={error} op={op} uuid={uuid} handle={handle}", 1)
            return
        end

        if op == 211
            self.add_gap_appearance()

        elif op == 201
            log("ANCS: Advertising started", 3)

        elif op == 227
            self.reset_session()
            self.peer_mac = cbuf[1..6]
            log(f"ANCS: iPad/iPhone connected: {self.peer_mac.tohex()}", 2)
            log("ANCS: Discovering ANCS on accepted link", 2)
            self.subscribe_ds()

        elif op == 228
            self.reset_session()
            log("ANCS: Central disconnected", 2)

        elif op == 230
            var n = int(cbuf[0])
            if n > 0
                var blob = cbuf[1..n]
                self.save_bond_blob_once(blob)
                log(f"ANCS: Bonded/authenticated len={n}", 2)
            else
                log("ANCS: Bonded/authenticated, empty bond payload", 2)
            end

            if !self.subscribed_ds && !self.auth_retry_done
                self.auth_retry_done = true
                self.subscribe_pending = false
                self.subscribe_ds()
            end

        elif op == 3
            self.subscribe_pending = false
            log(f"ANCS: Subscribe complete uuid={uuid} handle={handle}", 3)

            if uuid == DS_UID
                if !self.subscribed_ds
                    self.subscribed_ds = true
                    log("ANCS: DS subscribed", 2)
                end
                if !self.subscribed_ns
                    self.subscribe_ns()
                end

            elif uuid == NS_UID
                if !self.subscribed_ns
                    self.subscribed_ns = true
                    self.ready = true
                    log("ANCS: NS subscribed", 2)
                    log("ANCS: Ready for notifications", 2)
                    self.start_next_notification()
                end

            else
                log(f"ANCS: Subscribe completed for unknown uuid={uuid}", 3)
            end

        elif op == 2
            var dt = tasmota.millis() - self.cp_t0
            self.cp_busy = false
            log(f"ANCS: CP write OK uuid={uuid} handle={handle} dt_ms={dt} phase={self.attr_phase}", 4)
            self.request_next_attribute()

        elif op == 103
            var n = int(cbuf[0])
            var raw = n > 0 ? cbuf[1 .. n].tohex() : "<empty>"
            log(f"ANCS: NOTIFY uuid={uuid} handle={handle} len={n} raw={raw}", 4)
            self.on_notify(uuid)

        elif op == 224 || op == 225 || op == 226
            log(f"ANCS: Local server subscribe event op={op} uuid={uuid} handle={handle}", 4)
        end
    end

    #--------------------#
    # Setup / advertising
    #--------------------#

    def startup()
        self.current_func = /-> self.wait()
        self.set_gap_name()
        self.set_adv_params()
        self.add_gap_name_chr()
    end

    def set_gap_name()
        var name = bytes().fromstring(NAME)
        cbuf[0] = name.size()
        cbuf.setbytes(1, name)
        BLE.run(233)
    end

    def set_adv_params()
        cbuf.setbytes(0, bytes("05025000A000")) # connectable mode = 2, itvl_min = 50 ms, itvl_max = 100 ms
        BLE.run(232)
    end

    def add_gap_name_chr()
        BLE.set_svc(GAP_SVC)
        BLE.set_chr(GAP_CHR_NAME)

        var name = bytes().fromstring(NAME)
        cbuf[0] = name.size()
        cbuf.setbytes(1, name)

        BLE.run(211, true, 0x02)
        log("ANCS: Creating GAP Device Name characteristic", 3)
    end

    def add_gap_appearance()
        BLE.set_svc(GAP_SVC)
        BLE.set_chr(GAP_CHR_APPEAR)

        cbuf[0] = 2
        cbuf.set(1, APPEAR_GENERIC_HID, 2)

        BLE.run(211, true, 0x02)
        log("ANCS: Creating GAP Appearance characteristic = 0x03C0 (Generic HID)", 3)

        self.add_adv()
    end

    def add_adv()
        var name_b  = bytes().fromstring(NAME)
        var uuid_le = bytes(string.replace(ANCS_SVC, "-", "")).reverse()

        var name_ad = bytes("0009") + name_b
        name_ad[0] = name_b.size() + 1

        # Complete List of 16-bit Service UUIDs: HID (0x1812), little-endian
        var hid_ad = bytes("00031218")
        hid_ad[0] = 3

        # Solicited Service UUIDs, 128-bit: ANCS
        var sol_ad = bytes("0015") .. uuid_le
        sol_ad[0] = 17

        var payload = bytes("020106") .. name_ad .. hid_ad .. sol_ad

        cbuf[0] = payload.size()
        cbuf.setbytes(1, payload)

        BLE.run(201)

        log(f"ANCS: Advertising as {NAME}", 2)
        log("ANCS: Advertising HID service UUID 0x1812 + ANCS solicitation", 2)
        log("ANCS: Waiting for iPad/iPhone to connect", 2)
    end

    #--------------------#
    # Bridge client ops
    #--------------------#

    def subscribe_ds()
        if self.subscribed_ds || self.subscribe_pending
            return
        end

        self.subscribe_pending = true

        BLE.set_MAC(self.peer_mac, 1)
        BLE.set_svc(ANCS_SVC, true)
        BLE.set_chr(DS_CHR)
        BLE.run(3, true)
        log("ANCS: Subscribing DS", 3)
    end

    def subscribe_ns()
        if self.subscribed_ns || self.subscribe_pending
            return
        end

        self.subscribe_pending = true

        BLE.set_MAC(self.peer_mac, 1)
        BLE.set_svc(ANCS_SVC, true)
        BLE.set_chr(NS_CHR)
        BLE.run(3, true)
        log("ANCS: Subscribing NS", 3)
    end

    def write_cp(pkt)
        if self.cp_busy
            log("ANCS: CP busy, skipping immediate write", 3)
            return
        end

        self.cp_busy = true
        self.cp_t0   = tasmota.millis()
        cbuf[0] = pkt.size()
        cbuf.setbytes(1, pkt)

        log(f"ANCS: CP write START phase={self.attr_phase} len={pkt.size()} pkt={pkt.tohex()}", 4)

        BLE.set_MAC(self.peer_mac, 1)
        BLE.set_svc(ANCS_SVC, true)
        BLE.set_chr(CP_CHR)
        BLE.run(2, true)
    end

    #--------------------#
    # Notify handling
    #--------------------#

    def on_notify(uuid)
        var n = int(cbuf[0])
        if n <= 0
            log(f"ANCS: Empty notify for uuid={uuid}", 3)
            return
        end

        var data = cbuf[1 .. n]

        if uuid == NS_UID
            self.on_notification_source(data)
        elif uuid == DS_UID
            self.on_data_source(data)
        else
            log(f"ANCS: Unknown notify uuid={uuid} len={data.size()} data={data.tohex()}", 3)
        end
    end

    # [EventID, EventFlags, CategoryID, CategoryCount, UID0..3]
    def on_notification_source(data)
        var n = data.size()
        if n < 8
            log(f"ANCS: Short NS packet len={n} data={data.tohex()}", 3)
            return
        end

        var event_id = int(data[0])
        var flags    = int(data[1])
        var cat_id   = int(data[2])
        var cat_cnt  = int(data[3])

        self.latest_uid[0] = int(data[4])
        self.latest_uid[1] = int(data[5])
        self.latest_uid[2] = int(data[6])
        self.latest_uid[3] = int(data[7])

        var uid_b    = data[4..7]
        var uid      = uid_b.tohex()
        var cat_str  = cat_id < size(CATEGORIES) ? CATEGORIES[cat_id] : ("Cat " + str(cat_id))
        var flag_hex = string.format("%02X", flags)

        log(f"ANCS: NS event={event_id} flags=0x{flag_hex} cat={cat_str} count={cat_cnt} uid={uid}", 3)

        if event_id == 0
            self.pending[uid] = Notification(uid_b, event_id, flags, cat_id, cat_cnt, cat_str)
            if cat_id == 1
                log("ANCS: Incoming call - use ancs.accept_call() / ancs.reject_call()", 2)
            end
            self.start_next_notification()

        elif event_id == 1 || event_id == 2
            log(Notification(uid_b, event_id, flags, cat_id, cat_cnt, cat_str).to_json(), 2)

        else
            log(f"ANCS: Ignoring unsupported event_id={event_id}", 3)
        end
    end

    # [CommandID, UID0..3, AttributeID, LenLo, LenHi, <value>, ...]
    def on_data_source(data)
        var n = data.size()
        log(f"ANCS: DS RAW len={n} hex={data.tohex()}", 4)
        if n < 8
            log(f"ANCS: Short DS packet len={n} data={data.tohex()}", 3)
            return
        end

        var uid = data[1..4].tohex()
        var notif = self.pending.find(uid)

        if notif == nil
            log(f"ANCS: DS without pending notification uid={uid}", 3)
            return
        end

        var attr_id  = int(data[5])
        var attr_len = data.get(6, 2)
        var limit    = 8 + attr_len
        if limit > n
            limit = n
        end

        var value = ""
        if limit > 8
            value = data[8 .. limit - 1].asstring()
        end

        notif.set_attr(attr_id, value)

        if attr_id == 0x05 || notif.complete()
            self.emit_notification(uid)
        end
    end

    #--------------------#
    # Control Point
    #--------------------#

    def request_next_attribute()
        if !self.ready || self.cp_busy || self.active_uid == nil
            return
        end

        var notif = self.pending.find(self.active_uid)
        if notif == nil
            self.active_uid = nil
            self.attr_phase = -1
            self.start_next_notification()
            return
        end

        var u = notif.uid_b
        var pkt = bytes(8) .. 0 .. u

        if self.attr_phase == 0
            pkt .. 0
            self.attr_phase = 1
        elif self.attr_phase == 1
            pkt .. 0x01 .. 0x10 .. 0
            self.attr_phase = 2
        elif self.attr_phase == 2
            pkt .. 0x03 .. 0x10 .. 0
            self.attr_phase = 3
        elif self.attr_phase == 3
            pkt .. 0x05
            self.attr_phase = -1
        else
            self.attr_phase = -1
            return
        end

        self.write_cp(pkt)
    end

    def perform_action(action_id)
        if !self.ready
            log("ANCS: Not ready yet", 2)
            return
        end

        if self.cp_busy
            log("ANCS: CP busy, action deferred by user retry", 2)
            return
        end

        self.attr_phase = -1
        self.write_cp(bytes(6) .. 0x02 .. self.latest_uid .. action_id)
    end

    def accept_call()
        self.perform_action(0x00)
    end

    def reject_call()
        self.perform_action(0x01)
    end
end

var ancs = ANCS()
tasmota.add_driver(ancs)

log("ANCS: Advertising with local name + HID UUID 0x1812 + ANCS solicitation", 2)
