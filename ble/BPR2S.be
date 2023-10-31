# Simple Berry driver for the BPR2S Air mouse (a cheap BLE HID controller)
# TODO: handle mouse mode

import BLE

class BLE_BPR2S : Driver
    var buf
    var connecting, connected

    def init(MAC,addr_type)
        var cbp = tasmota.gen_cb(/e,o,u,h->self.cb(e,o,u,h))
        self.buf = bytes(-256)
        BLE.conn_cb(cbp,self.buf)
        BLE.set_MAC(bytes(MAC),addr_type)
        print("BLE: will try to connect to BPR2S with MAC:",MAC)
        self.connect()
    end

    def connect()
        self.connecting = true;
        self.connected = false;
        BLE.set_svc("1812")
        BLE.set_chr("2a4a") # the first characteristic we have to read
        BLE.run(1) # read
    end

    def every_second()
        if (self.connecting == false && self.connected == false)
            print("BLE: try to reconnect BPR2S")
            self.connect()
        end
    end

    def handle_read_CB(uuid) # uuid is the callback characteristic
        self.connected = true;
    # we just have to read these characteristics before we can finally subscribe
        if uuid == 0x2a4a # did receive HID info
            BLE.set_chr("2a4b")
            BLE.run(1) # read next characteristic 
        elif uuid == 0x2a4b # did receive HID report map
            BLE.set_chr("2a4d")
            BLE.run(1) # read to trigger notifications of the HID device
        elif uuid == 0x2a4d # did receive HID report
            print(self.buf[1..self.buf[0]])
            BLE.set_chr("2a4d")
            BLE.run(3) # subscribe
        end
    end

    def handle_HID_notification(h) 
        import mqtt
        var key = ""
        if h == 42
            var k = self.buf[3]
            if k == 0x65
                key = "square"
            elif k == 0x4f
                key = "right"
            elif k == 0x50
                key = "left"
            elif k == 0x51
                key = "down"
            elif k == 0x52
                key = "up"
            elif k == 0x2a
                key = "back"
            end
        elif h == 38
            var k = self.buf[1]
            if k == 0x30
                key = "on"
            elif k == 0xe2
                key = "mute"
            elif k == 0x23
                key = "triangle"
            elif k == 0x21
                key = "circle"
            elif k == 0x41
                key = "set"
            elif k == 0x24
                key = "return"
            elif k == 0xea
                key = "minus"
            elif k == 0xe9
                key = "plus"
            end
        end
        if key != ''
            mqtt.publish("tele/BPR2S",format("{'key':'%s'}",key))
        # else # will be triggered on button release too
        #     print(self.buf[1..self.buf[0]],h) # show the packet as byte buffer
        end
    end

    def cb(error,op,uuid,handle)
        if error == 0
            if op == 1 # read OP
                print(op,uuid)
                self.handle_read_CB(uuid)
            elif op == 3
                self.connecting = false;
                print("BLE: init completed for BPR2S")
            elif op == 5
                self.connected = false;
                self.connecting = false;
                print("BLE: did disconnect BPR2S ... will try to reconnect")
            elif op == 103 # notification OP
                self.handle_HID_notification(handle)
            end
        else
            print("BLE: error:",error)
            if self.connecting == true
                print("BLE: init sequence failed ... try to repeat")
                self.connecting = false
            end
        end
    end

end

ble_hid = BLE_BPR2S("E007020103C1",1) # HID controller MAC and address type
tasmota.add_driver(ble_hid)
