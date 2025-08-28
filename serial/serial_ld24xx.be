#- LF24xx.be - HLK-LD24 family 24GHz smart wave motion sensor support
#   Refactor: introduce LD24xxBase and subclass LD2410/LD2412/LD2420
#   SPDX-FileCopyrightText: 2024 Christian Baars
#   SPDX-License-Identifier: GPL-3.0-only
-#

class LD24xxBase
    var model_name, fw_version
    var MAX_GATES
    var OFF_MOV_DIST, OFF_MOV_EN, OFF_STAT_DIST, OFF_STAT_EN
    var OFF_MOV_GATES, OFF_STAT_GATES, GATE_SIZE
    var OFF_LIGHT, HAS_LIGHT

    var moving_distance, moving_energy
    var static_distance, static_energy
    var max_mov_gate, max_stat_gate
    var mov_gate_energies, stat_gate_energies
    var light, mode

    def init()
        self.mov_gate_energies = []
        self.stat_gate_energies = []
    end

    def handleTRG(buf)
        self.mode = buf[6]
        # basic distances
        if (buf[8] & 1) != 0
            self.moving_distance = buf.get(self.OFF_MOV_DIST, 2)
            self.moving_energy = buf[self.OFF_MOV_EN]
        end
        if (buf[8] & 2) != 0
            self.static_distance = buf.get(self.OFF_STAT_DIST, 2)
            self.static_energy = buf[self.OFF_STAT_EN]
        end
        # engineering mode
        if self.mode == 1
            self.max_mov_gate = buf[self.OFF_MOV_GATES - 2]
            self.max_stat_gate = buf[self.OFF_STAT_GATES - 2]
            self.mov_gate_energies.clear()
            self.stat_gate_energies.clear()
            var i = 0
            while i < self.MAX_GATES
                self.mov_gate_energies.push(buf.get(self.OFF_MOV_GATES + i * self.GATE_SIZE, self.GATE_SIZE))
                self.stat_gate_energies.push(buf.get(self.OFF_STAT_GATES + i * self.GATE_SIZE, self.GATE_SIZE))
                i += 1
            end
            if self.HAS_LIGHT && size(buf) > self.OFF_LIGHT
                self.light = buf[self.OFF_LIGHT]
            end
        end
    end

    def show_web()
        if self.mode == nil
            return nil
        end
        var msg = ""
        if self.mode != 0
            msg += f"{{s}}{self.model_name} moving distance{{m}}{self.moving_distance} cm{{e}}"
                   "{{s}}{self.model_name} static distance{{m}}{self.static_distance} cm{{e}}"
        end
        if self.mode == 1
            msg += f"{{s}}{self.model_name} max moving gate{{m}}{self.max_mov_gate}{{e}}"
                   "{{s}}{self.model_name} max static gate{{m}}{self.max_stat_gate}{{e}}"
            if self.HAS_LIGHT && self.light != nil
                msg += f"{{s}}{self.model_name} light{{m}}{self.light}{{e}}"
            end
            msg += "{s}Moving gate energies{m}{e}{s}"
            var i = 0
            while i < self.MAX_GATES
                var energy = (self.mov_gate_energies[i] >> 4) + 1
                if energy > 8
                    energy = 8
                end
                msg += f"&#x258{energy} "
                i += 1
            end
            msg += "{m}{e}{s}Static gate energies{m}{e}{s}"
            i = 0
            while i < self.MAX_GATES
                var energy2 = (self.stat_gate_energies[i] >> 4) + 1
                if energy2 > 8
                    energy2 = 8
                end
                msg += f"&#x258{energy2} "
                i += 1
            end
            msg += "{m}{e}"
        end
        tasmota.web_send_decimal(msg)
    end

    def show_json()
        if self.mode == nil || self.mode == 0
            return nil
        end
        var engin_msg = ""
        if self.mode == 1
            engin_msg = f",\"moving_energies\":{self.mov_gate_energies},\"static_energies\":{self.stat_gate_energies}"
        end
        var msg = f",\"{self.model_name}\":{{\"distance\":[{self.moving_distance},{self.static_distance}],\"energy\":[{self.moving_energy},{self.static_energy}]}}{engin_msg}"
        tasmota.response_append(msg)
    end
end

class LD2410 : LD24xxBase
    def init(major, minor, patch)
        self.model_name = "LD2410"
        self.fw_version = [major, minor, patch]
        self.MAX_GATES = 8
        self.OFF_MOV_DIST = 9
        self.OFF_MOV_EN = 11
        self.OFF_STAT_DIST = 12
        self.OFF_STAT_EN = 14
        self.OFF_MOV_GATES = 0
        self.OFF_STAT_GATES = 0
        self.GATE_SIZE = 1
        self.HAS_LIGHT = false
        super(self).init()
    end
end

class LD2412 : LD24xxBase
    def init(major, minor, patch)
        super(self).init()
        self.model_name = "LD2412"
        self.fw_version = [major, minor, patch]
        self.MAX_GATES = 13
        self.OFF_MOV_DIST = 9
        self.OFF_MOV_EN = 11
        self.OFF_STAT_DIST = 12
        self.OFF_STAT_EN = 14
        self.OFF_MOV_GATES = 17
        self.OFF_STAT_GATES = 31
        self.GATE_SIZE = 1
        self.OFF_LIGHT = 45
        self.HAS_LIGHT = true
    end
end


class LD2420 : LD24xxBase
    var presence, range

    def init(sender, major, minor, patch)
        self.model_name = "LD2420"
        self.fw_version = [major, minor, patch]
        sender.cmnd_chain = [
            /->sender.sendCMD(sender.CMND_SET_SYSTEM_PARAM, bytes("000004000000")),
            /->sender.setCfgMode(false)
        ]
        self.MAX_GATES = 16
        self.OFF_MOV_GATES = 9
        self.GATE_SIZE = 2
        self.HAS_LIGHT = false
        super(self).init()
    end

    def handleTRG(buf)
        if buf[4] == 0x23
            self.mode = 2
            self.presence = buf[6]
            self.range = buf.get(7, 2)
            self.mov_gate_energies.clear()
            var i = 0
            while i < self.MAX_GATES
                self.mov_gate_energies.push(buf.get(self.OFF_MOV_GATES + i * self.GATE_SIZE, self.GATE_SIZE))
                i += 1
            end
        else
            # fall back to base parsing if not type 0x23
            super(self).handleTRG(buf)
        end
    end

    def show_web()
        if self.mode == nil
            return nil
        end
        var msg
        if self.mode == 0
            msg = f"{{s}}{self.model_name} range{{m}}{self.range} cm{{e}}"
        elif self.mode == 2
            msg = f"{{s}}{self.model_name} presence{{m}}{self.presence}{{e}}" ..
                  f"{{s}}{self.model_name} range{{m}}{self.range} cm{{e}}"
        else
            # let base handle other modes
            super(self).show_web()
            return
        end
        tasmota.web_send_decimal(msg)
    end

    def show_json()
        if self.mode == nil
            return nil
        end
        # always include the base JSON block first
        super(self).show_json()

        # then append LD2420‑specific extras
        if self.mode == 0
            tasmota.response_append(f",\"range\":{self.range}")
        elif self.mode == 2
            tasmota.response_append(f",\"presence\":{self.presence},\"range\":{self.range},\"gates\":{self.mov_gate_energies}")
        end
    end
end


class LD2 : Driver
    var buf
    var ser, sensor, MAC
    var cmnd_chain, timeout

    static CMND_START_CONFIGURATION = 0xFF
    static CMND_END_CONFIGURATION = 0xFE
    static CMND_READ_VERSION = 0x00
    static CMND_READ_SERIAL_NUM = 0x11
    static CMND_SET_SYSTEM_PARAM = 0x12
    static CMND_SET_DISTANCE = 0x60
    static CMND_READ_PARAMETERS = 0x61
    static CMND_START_ENGINEERING = 0x62
    static CMND_END_ENGINEERING = 0x63
    static CMND_SET_SENSITIVITY = 0x64
    static CMND_GET_FIRMWARE = 0xA0
    static CMND_SET_BAUDRATE = 0xA1
    static CMND_FACTORY_RESET = 0xA2
    static CMND_REBOOT = 0xA3
    static CMND_GET_MAC = 0xA5
    static CMND_SET_DIST_RES = 0xAA
    static CMND_GET_DIST_RES = 0xAB

    static config_header = bytes("FDFCFBFA")
    static config_footer = bytes("04030201")
    static target_header = bytes("F4F3F2F1")
    static target_footer = bytes("F8F7F6F5")
    static simple_on_header  = bytes("4F4E0D0A")   # "ON"
    static simple_off_header = bytes("4F46460D0A") # "OFF"

    def init(rx, tx, baud)
        log("LD2: start LD24xx driver")
        self.ser = serial(rx, tx, baud)
        self.buf = bytes(64)
        self.ser.read()  # read to /dev/null
        self.cmnd_chain = [
            /->self.getFW(),
            /->self.getVersion(),
            /->self.getMAC(),
            /->self.setCfgMode(false)
        ]
        self.setCfgMode(true)
    end

    def init_sensor(sensor_type, major, minor, patch)
        if sensor_type == 2410
            self.sensor = LD2410(major, minor, patch)
        elif sensor_type == 2412
            self.sensor = LD2412(major, minor, patch)
        elif sensor_type == 2420
            self.sensor = LD2420(self, major, minor, patch)
        else
            log("LD2: ERROR - unknown sensor!!")
            return
        end
        log(f"LD2: found {self.sensor.model_name}")
    end

    # common commands for the LD24xx family
    def sendCMD(cmd, val)
        var val_len = 0
        if val != nil
            val_len = size(val)
        end
        var total = 4 + 2 + 2 + val_len + 4  # header+len+cmd+val+footer
        var cmd_buf = bytes(-total)
        cmd_buf.setbytes(0, self.config_header)
        cmd_buf[4] = 2 + val_len
        cmd_buf[6] = cmd
        if val != nil
            cmd_buf.setbytes(8, val)
        end
        cmd_buf.setbytes(8 + val_len, self.config_footer)
        self.ser.write(cmd_buf)
        print(cmd_buf)
    end

    def getVersion()
        self.timeout = 2  # seconds
        self.sendCMD(self.CMND_READ_VERSION)
        log("LD2: Request Version, try to identify sensor type")
    end

    def getFW()
        self.timeout = 2  # seconds
        self.sendCMD(self.CMND_GET_FIRMWARE)
        log("LD2: Request FW, try to identify sensor type")
    end

    def getMAC()
        self.timeout = 2  # seconds
        self.sendCMD(self.CMND_GET_MAC, bytes("0100"))
        log("LD2: Request MAC")
    end

    def factoryReset()
        self.sendCMD(self.CMND_FACTORY_RESET)
        log("LD2: Factory reset")
    end

    def setCfgMode(on)
        if on == true
            self.sendCMD(self.CMND_START_CONFIGURATION, bytes("0100"))
            log("LD2: Start config mode", 3)
        else
            self.sendCMD(self.CMND_END_CONFIGURATION)
            log("LD2: Stop config mode", 3)
        end
    end

    def setEngMode(on)
        if on == true
            self.sendCMD(self.CMND_START_ENGINEERING, bytes("0100"))
            log("LD2: Start engineering mode")
        else
            self.sendCMD(self.CMND_END_ENGINEERING)
            log("LD2: Stop engineering mode")
        end
        self.timeout = 2  # seconds
    end

    def setDistRes(res)
        var payload = bytes("0000")
        payload[0] = res
        self.sendCMD(self.CMND_SET_DIST_RES, payload)
        self.timeout = 2  # seconds
    end

    def setMaxDistAndNoOneDur(max_mov_dist_range, max_stat_dist_range, no_one_duration)
        var val = bytes(-18)
        val[2] = max_mov_dist_range
        val[6] = 1
        val[8] = max_stat_dist_range
        val[12] = 2
        val.set(14, no_one_duration, -2)  # big-endian
        self.sendCMD(self.CMND_SET_DISTANCE, val)
        self.timeout = 2  # seconds
    end

    def settGateSensitivity(gate, moving_sensitivity, static_sensitivity)
        var val = bytes(-18)
        val[2] = gate
        val[6] = 1
        val[8] = moving_sensitivity
        val[12] = 2
        val[14] = static_sensitivity
        self.sendCMD(self.CMND_SET_SENSITIVITY, val)
        self.timeout = 2  # seconds
    end

    def settAllSensitivity(sensitivity)
        var val = bytes(-18)
        val[2] = 0xff
        val[3] = 0xff
        val[6] = 1
        val[8] = sensitivity
        val[12] = 2
        val[14] = sensitivity
        self.sendCMD(self.CMND_SET_SENSITIVITY, val)
        self.timeout = 2  # seconds
    end

    # driver loop and helper functions
    def clean_buffer()
        var cap = size(self.buf)
        if cap < 4
            return  # nothing to do
        end

        var idx = 0
        while idx <= cap - 4
            var window = self.buf[idx .. idx + 3]
            if window == self.config_footer || window == self.target_footer
                # drop everything including this footer
                self.buf = self.buf[idx + 4 ..]
                cap = size(self.buf)
                idx = 0
                continue  # check again in case there are more packets queued
            end
            idx += 1
        end

        # if we scanned the whole buffer without finding a footer, 
        # and it's just garbage, clear it
        if idx > cap - 4
            self.buf.clear()
        end
    end


    def next_cmnd()
        if size(self.cmnd_chain) > 0
            var function = self.cmnd_chain[0]
            function()
            if size(self.cmnd_chain) > 1
                self.cmnd_chain = self.cmnd_chain[1 ..]
            else
                self.cmnd_chain = []
                self.timeout = nil
            end
        end
    end

    def every_50ms()
        if self.ser != nil
            self.buf .. self.ser.read()
            if size(self.buf) > 11  # shortest possible packet is 12
                self.handle_read()
            end
        end
        self.clean_buffer()
    end

    def every_second()
        if self.timeout != nil
            if self.timeout > 0
                self.timeout -= 1
            else
                log("LD2: timeout ... proceed with next command")
                self.timeout = nil
                self.next_cmnd()
            end
        end
    end

    def parseVersion()
        # Example: FD FC FB FA 0D 00 00 01 00 00 07 00 76 31 2E 34 2E 31 34 04 03 02 01
        # header |len |ty|hd|ack | length |   string   | trailer

        var str_len = self.buf[10]
        # ensure payload length fits in buffer
        if size(self.buf) < 13 + str_len
            log(f"LD2: parseVersion — buffer too short ({size(self.buf)} bytes for {str_len}‑byte string)")
            return
        end

        var s = self.buf[13 .. 12 + str_len].asstring()
        import string
        var fw = string.split(s, ".")
        if size(fw) < 3
            log(f"LD2: parseVersion — unexpected version string '{s}'")
            return
        end

        var major = int(fw[0])
        var minor = int(fw[1])
        var patch = int(fw[2])

        log(f"LD2: Version string '{s}' parsed as {major}.{minor}.{patch}")

        # Only initialise LD2420 here if nothing else has yet
        if self.sensor == nil
            self.init_sensor(2420, major, minor, patch)  # intended as LD2420 fallback
        end
    end

    def parseFW()
        if size(self.buf) < 20
            log("LD2: parseFW — buffer too short")
            return
        end
        var ftype  = self.buf.get(10, 2)   # firmware type
        var major  = self.buf[13]
        var minor  = self.buf[12]
        var patch = self.buf.get(14,4)
        log(f"LD2: Firmware version {major:x}.{minor:x}.{patch:02x}")

        if ftype == 256
            self.init_sensor(2410, major, minor, patch)
        elif ftype == 0x2412
            self.init_sensor(2412, major, minor, patch)
        elif ftype == 0x2420
            self.init_sensor(2420, major, minor, patch)
        else
            log(f"LD2: Unknown FW type: {ftype}")
            log(self.buf)
        end
    end

    def handleCFG()
        var cmd = self.buf[6]
        var ack = self.buf[7] == 1

        if !ack
            log(f"LD2: Sensor NACK for cmd {cmd}", 2)
            return   # stop here, nothing further to parse
        end

        if cmd == self.CMND_READ_PARAMETERS
            print(
                "LD2: moving_distance_gate", self.buf[12],
                "static_distance_gate", self.buf[13],
                "no one duration", self.buf.get(32, -2)
            )
            for i:0..self.sensor.MAX_GATES
                print("LD2: moving sens", i, self.buf[14 + i], "static sens", i, self.buf[23 + i])
            end

        elif cmd == self.CMND_START_CONFIGURATION || cmd == self.CMND_END_CONFIGURATION
            # nothing to do

        elif cmd == self.CMND_READ_VERSION
            self.parseVersion()

        elif cmd == self.CMND_GET_FIRMWARE
            self.parseFW()

        elif cmd == self.CMND_GET_MAC
            self.MAC = self.buf[10 .. 15].tohex()
            log(f"LD2: has MAC {self.MAC}")

        else
            log(f"LD2: Unknown config payload {self.buf}",2)
        end

        log("LD2: Sensor ACK", 3)
        self.next_cmnd()
    end

    def handle_read()
        if self.buf[0] == 0xfd
            self.handleCFG()
        elif self.buf[0] == 0xf4
            if self.sensor != nil
                self.sensor.handleTRG(self.buf)
            end
        elif self.buf[0] == 0x4f
            if self.sensor != nil
                self.sensor.handleSimple(self.buf)
            end
        else
            print(self.buf)
            self.buf = self.buf[1 ..]
        end
    end

    def serviceSensitivities()
        if self.sensitivity_counter < 0
            self.setCfgMode(false)
            log("LD2: Did set sensitivities", 2)
        else
            self.settGateSensitivity(
                self.sensitivity_counter,
                self.moving_sensitivity[self.sensitivity_counter],
                self.static_sensitivity[self.sensitivity_counter]
            )
            self.sensitivity_counter -= 1
            print("LD2:", self.sensitivity_counter + 1, "steps left")
        end
    end

    def cmndDuration(cmd, idx, payload, payload_json)
        var pl = int(payload)
        self.setCfgMode(true)
        if pl == 0
            self.factoryReset()
        else
            self.setMaxDistAndNoOneDur(8, 8, pl)
        end
        tasmota.resp_cmnd({"Duration": pl})
    end

    def cmndMovingSens(cmd, idx, payload, payload_json)
        import string
        var pl = string.split(payload, ",")
        var i = 0
        while i < size(pl)
            self.moving_sensitivity[i] = int(pl[i])
            i += 1
        end
        self.sensitivity_counter = self.sensor.MAX_GATES
        self.setCfgMode(true)
        self.serviceSensitivities()
        tasmota.resp_cmnd({"MovingSensitivity": pl})
    end

    def cmndStaticSens(cmd, idx, payload, payload_json)
        import string
        var pl = string.split(payload, ",")
        var i = 0
        while i < size(pl)
            self.static_sensitivity[i] = int(pl[i])  # TODO error check
            i += 1
        end
        self.sensitivity_counter = self.sensor.MAX_GATES
        self.setCfgMode(true)
        self.serviceSensitivities()
        tasmota.resp_cmnd({"StaticSensitivity": pl})
    end

    def cmndEngMode(cmd, idx, payload, payload_json)
        var pl = int(payload) > 0
        self.setCfgMode(true)
        self.cmnd_chain.push(/->self.setEngMode(pl))
        tasmota.resp_cmnd({"EngineeringMode": pl})
        self.cmnd_chain.push(/->self.setCfgMode(false))
    end

    def cmndDistRes(cmd, idx, payload, payload_json)
        var pl = int(payload)
        self.setCfgMode(true)
        self.cmnd_chain.push(/->self.setDistRes(pl))
        tasmota.resp_cmnd({"DistanceResolution": pl})
        self.cmnd_chain.push(/->self.setCfgMode(false))
    end

    def web_sensor()  # display sensor value in the web UI
        if self.sensor != nil
            self.sensor.show_web()
        end
    end

    def json_append() # add sensor value to teleperiod
        if self.sensor != nil
            self.sensor.show_json()
        end
    end
end

var ld2 = LD2(15, 16, 115200) # or 256000 baud
tasmota.add_driver(ld2)
tasmota.add_cmd('LD2Duration',   /c,i,p,j->ld2.cmndDuration(c, i, p, j))
tasmota.add_cmd('LD2MovingSens', /c,i,p,j->ld2.cmndMovingSens(c, i, p, j))
tasmota.add_cmd('LD2StaticSens', /c,i,p,j->ld2.cmndStaticSens(c, i, p, j))
tasmota.add_cmd('LD2EngMode',    /c,i,p,j->ld2.cmndEngMode(c, i, p, j))
tasmota.add_cmd('LD2DistRes',    /c,i,p,j->ld2.cmndDistRes(c, i, p, j))
