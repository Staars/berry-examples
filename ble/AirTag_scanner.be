#-
AirTag scanner (barebone app)
-#

cbuf = bytes(-64)
class AIRTAGSCANNER : Driver
    static header = bytes("1EFF4C00")
    def init()
        import BLE
        import cb
        var cbp = cb.gen_cb(/svc,manu->self.ble_cb(svc,manu))
        BLE.adv_cb(cbp,cbuf)
        tasmota.add_fast_loop(/-> BLE.loop())
        log("AIR: start Airtag scanner")
    end

    def ble_cb(svc,manu)
        if cbuf[9..12] != self.header || cbuf[14] != 0x19
            return
        end
        var mode = "unknown"
        if cbuf[13] == 0x12
            mode = "lost"
        elif cbuf[13] == 0x07
            mode = "unregistered"
        end
        var MAC = cbuf[0..5]
        # var addr_type = cbuf[6]
        var RSSI = (255 - (cbuf[7])) * -1
        var payload = cbuf[9..(cbuf[8]+8)]
        log(f'AIR: "MAC":"{MAC.tohex()}","RSSI":{RSSI},"Payload":"{payload.tohex()}","Mode":"{mode}"')
    end
end

a = AIRTAGSCANNER()
