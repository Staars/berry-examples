    # just a proof of concept to connect a Xbox X/S controller
    # must be repaired on every connect
    class XBOX : Driver
        var buf

        def init(MAC)
            import BLE
            var cbp = tasmota.gen_cb(/e,o,u->self.cb(e,o,u))
            self.buf = bytes(-256)
            BLE.conn_cb(cbp,self.buf)
            BLE.set_MAC(bytes(bytes(MAC)),0)
            self.connect()
        end

        def connect() # separated to call it from the berry console if needed
            import BLE
            BLE.set_svc("1812")
            BLE.set_chr("2a4a") # the first characteristic we have to read
            BLE.run(1) # read
        end

        def handle_read_CB(uuid) # uuid is the notifying characteristic
            import BLE
        # we just have to read these characteristics before we can finally subscribe
            if uuid == 0x2a4a # ignore data
                BLE.set_chr("2a4b")
                BLE.run(1) # read next characteristic 
            end
            if uuid == 0x2a4b # ignore data
                BLE.set_chr("2a4d")
                BLE.run(1) # read next characteristic 
            end
            if uuid == 0x2a4d # ignore data
                BLE.set_chr("2a4d")
                BLE.run(3) # start notify
            end
        end

        def handle_HID_notifiaction() # a very incomplete parser
            if self.buf[14] == 1
                print("ButtonA") # a MQTT message could actually trigger something
            end
            if self.buf[14] == 2
                print("ButtonB")
            end
            if self.buf[14] == 8
                print("ButtonX")
            end
            if self.buf[14] == 16
                print("ButtonY")
            end
        end

        def cb(error,op,uuid)
            if error == 0
                if op == 1
                    print(op,uuid)
                    self.handle_read_CB(uuid)
                end
                if op == 3
                self.handle_HID_notification()
                end
                return
            else
                print(error)
            end
        end

    end

    xbox = XBOX("AABBCCDDEEFF")  # xbox controller MAC
    tasmota.add_driver(xbox)
