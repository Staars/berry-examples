# Simple Berry driver for the BPR2S Air mouse (a cheap BLE HID controller)

import BLE

class BLE_BPR2S : Driver
    var buf
    var connecting, connected, new_position
    var x,y

    def init(MAC,addr_type)
        var cbp = tasmota.gen_cb(/e,o,u,h->self.cb(e,o,u,h))
        self.buf = bytes(-256)
        BLE.conn_cb(cbp,self.buf)
        BLE.set_MAC(bytes(MAC),addr_type)
        print("BLE: will try to connect to BPR2S with MAC:",MAC)
        self.connect()
        tasmota.add_fast_loop(/-> BLE.loop()) # needed for mouse position
    end

    def connect()
        self.connecting = true
        self.connected = false
        self.new_position = false
        self.x = 128
        self.y = 128
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

    def every_50ms()
        import mqtt
        if self.new_position == true
            mqtt.publish("tele/BPR2S",format('{"mouse":{"x":%s,"y":%s}}',self.x,self.y))
            self.new_position = false
        end
    end

    def handle_read_CB(uuid) # uuid is the callback characteristic
        self.connected = true;
    # we just have to read these characteristics before we can finally subscribe
        if uuid == 0x2a4a # did receive HID info
            print("BLE: now connecting to BPR2S")
            BLE.set_chr("2a4b")
            BLE.run(1) # read next characteristic 
        elif uuid == 0x2a4b # did receive HID report map
            BLE.set_chr("2a4d")
            BLE.run(1) # read to trigger notifications of the HID device
        elif uuid == 0x2a4d # did receive HID report
            BLE.set_chr("2a4d")
            BLE.run(3) # subscribe
        end
    end

    def handle_mouse_pos()
        var x = self.buf.getbits(12,12)
        if x > 2048
            x -= 4096
        end
        var y = self.buf.getbits(24,12)
        if y > 2048
            y -= 4096
        end

        self.x += (x >> 7) # some conversion factor
        self.y += (y >> 7)
        
        # could be mapped to hue, saturation, brightness, ...
        if self.x > 255 self.x = 255
        elif self.x < 0 self.x = 0
        end
        if self.y > 255 self.y = 255
        elif self.y < 0 self.y = 0
        end
        self.new_position = true
    end

    def handle_HID_notification(h) 
        import mqtt
        var t = "key"
        var v = ""
        if h == 42
            var k = self.buf[3]
            if k == 0x65
                v = "square"
            elif k == 0x4f
                v = "right"
            elif k == 0x50
                v = "left"
            elif k == 0x51
                v = "down"
            elif k == 0x52
                v = "up"
            elif k == 0x2a
                v = "back"
            end
        elif h == 38
            var k = self.buf[1]
            if k == 0x30
                v = "on"
            elif k == 0xe2
                v = "mute"
            elif k == 0x23
                v = "triangle"
            elif k == 0x21
                v = "circle"
            elif k == 0x41
                v = "set"
            elif k == 0x24
                v = "return"
            elif k == 0xea
                v = "minus"
            elif k == 0xe9
                v = "plus"
            end
        elif h == 34
            self.handle_mouse_pos()
            return
        end
        if v != ''
            mqtt.publish("tele/BPR2S",format('{"%s":"%s"}',t,v))
        # else # will be triggered on button release too
        #     print(self.buf[1..self.buf[0]],h) # show the packet as byte buffer
        end
    end

    def cb(error,op,uuid,handle)
        if error == 0
            if op == 1 # read OP
                # print(op,uuid)
                self.handle_read_CB(uuid)
            elif op == 3
                self.connecting = false
                self.connected = true
                print("BLE: init completed for BPR2S")
            elif op == 5
                self.connected = false
                self.connecting = false
                print("BLE: did disconnect BPR2S ... will try to reconnect")
            elif op == 103 # notification OP
                if self.connected == false return end
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
