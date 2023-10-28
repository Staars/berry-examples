# base template driver to use a BLE HID controller

import BLE

class BLE_HID : Driver
    var buf

    def init(MAC,addr_type)
        var cbp = tasmota.gen_cb(/e,o,u,h->self.cb(e,o,u,h))
        self.buf = bytes(-256)
        BLE.conn_cb(cbp,self.buf)
        BLE.set_MAC(bytes(MAC),addr_type)
        self.connect()
    end

    def connect() # separated to call it from the berry console if needed
        BLE.set_svc("1812")
        BLE.set_chr("2a4a") # the first characteristic we have to read
        BLE.run(1) # read
    end

    def handle_read_CB(uuid) # uuid is the notifying characteristic
    # we just have to read these characteristics before we can finally subscribe
        if uuid == 0x2a4a # did receive HID info
            print("HID info:", self.buf[1],self.buf[2])
            BLE.set_chr("2a4b")
            BLE.run(1) # read next characteristic 
        end
        if uuid == 0x2a4b # did receive report map
            print("HID report map of size:", self.buf[0])
            for i:range(0,self.buf[0],20)
                var j = 20
                if self.buf[0] - i < 20 # last chunk
                    j = self.buf[0] - i
                end
                var b = self.buf[i+1..i+j]
                var l = ""
                for k:range(0,size(b)-1) l+=format("%02x ",b[k]) end
                print(l)
            end
            BLE.set_chr("2a4d")
            BLE.run(1) # read to trigger notifications of the HID device
        end
        if uuid == 0x2a4d # did receive report map
            print(self.buf[1..self.buf[0]])
            BLE.set_chr("2a4d")
            BLE.run(3) # subscribe
        end
    end

    def handle_HID_notification(h) 
        # just for debugging
        print(self.buf[1..self.buf[0]],h)
        # now this data would be parsed to trigger something
    end

    def cb(error,op,uuid,handle)
        if error == 0
            if op == 1
                print(op,uuid)
                self.handle_read_CB(uuid)
            end
            if op == 103
                self.handle_HID_notification(handle)
            end
            return
        else
            print(error)
            if uuid == 0x2a4a
                print("Try to conect to HID ...")
                BLE.set_chr("2a4a") # the first characteristic we have to read
                BLE.run(1) # read
            end
        end
    end

end

ble_hid = BLE_HID("112233445566",1)  # HID controller MAC and address type
tasmota.add_driver(ble_hid)
