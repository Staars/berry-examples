#-
Example to find pattern in r5 payload
-#

cbuf = bytes(-64)

class BLE_EWE : Driver
    static b0 = bytes('0201021B05FFFFEE1BC878F64A4790365AD509227B7442C5245C7DE4828B98')
    static b1 = bytes('0201021B05FFFFEE1BC878F64A4790355AD50922727D4ACC2D5574EE8B3369')
    static b2 = bytes('0201021B05FFFFEE1BC878F64A4790345AD50922545B6FEA0B7352C9AD45BD')
    static b3 = bytes('0201021B05FFFFEE1BC878F64A47903B5AD50922D3DCE96D8CF4D5492AB1E6')
    static b4 = bytes('0201021B05FFFFEE1BC878F64A47903A5AD5092266695BD8394160FD9FDB40')
    static b5 = bytes('0201021B05FFFFEE1BC878F64A4790395AD50922CFC0F37190E8C957368904')
    var last_data

    def init()
        import BLE
        import cb
        var cbp = cb.gen_cb(/svc,manu->self.ble_cb(svc,manu)) # position of service and manufacturer data in the buffer, 0 if absent
        BLE.adv_cb(cbp,cbuf)
        self.last_data = self.b1[16..]
        tasmota.add_fast_loop(/-> BLE.loop())
    end

    def ble_cb(svc,manu)
        var MAC = cbuf[0..5]
        if MAC != bytes("665544332211") return end
        var addr_type = cbuf[6]
        var RSSI = (255 - (cbuf[7])) * -1
        var payload = cbuf[9..(cbuf[8]+8)]
        var data = cbuf[25..(cbuf[8]+8)]
        # print(data)
        if data != self.last_data
            #print(data)
            self.test(data)
        end
        # print(MAC,addr_type,RSSI,payload,svc,manu)
    end

    def test(d)
        if self.b0[22]^d[6] == self.b0[21]^d[5]
            print("Button 0")
        elif self.b1[22]^d[6] == self.b1[21]^d[5]
            print("Button 1")
        elif self.b2[22]^d[6] == self.b2[21]^d[5]
            print("Button 2")
        elif self.b3[22]^d[6] == self.b3[21]^d[5]
            print("Button 3")
        elif self.b4[22]^d[6] == self.b4[21]^d[5]
            print("Button 4")
        elif self.b5[22]^d[6] == self.b5[21]^d[5]
            print("Button 5")
        end
        self.last_data = d
    end
end

ewe = BLE_EWE()


