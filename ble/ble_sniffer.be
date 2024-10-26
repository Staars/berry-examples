#-
Very simple and fast console BLE sniffer
intended to me modified in the code for special needs
-#

cbuf = bytes(-64)
class BLE_SNIFF : Driver
    def init()
        import BLE
        import cb
        var cbp = cb.gen_cb(/svc,manu->self.ble_cb(svc,manu)) # position of service and manufacturer data in the buffer, 0 if absent
        BLE.adv_cb(cbp,cbuf)
        tasmota.add_fast_loop(/-> BLE.loop())
    end

    def ble_cb(svc,manu)
        # if manu == 0 return end # filter out packet without manufacturer data
        # if svc == 0 return end # filter out packet without service data 
        var MAC = cbuf[0..5]
        var addr_type = cbuf[6]
        # if addr_type == 0 return end # filter out address type : 0 - public, 1 - random
        var RSSI = (255 - (cbuf[7])) * -1
        var payload = cbuf[9..(cbuf[8]+8)]

        print(MAC,addr_type,RSSI,payload,svc,manu)
    end
end

sniffer = BLE_SNIFF()
