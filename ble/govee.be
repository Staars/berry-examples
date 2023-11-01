    # control a BLE Govee desk lamp
    class GOVEE : Driver
        var buf
    
        def init(MAC)
            import BLE
            self.buf = bytes(-21) # create a byte buffer, first byte reserved for length info
            self.buf[0] = 20 # length of the data part of the buffer in bytes
            self.buf[1] = 0x33 # a magic number - control byte for the Govee lamp
            var cbp = tasmota.gen_cb(/e,o,u->self.cb(e,o,u)) # create a callback function pointer
            BLE.conn_cb(cbp,self.buf)
            BLE.set_MAC(bytes(MAC),1) # addrType: 1 (random)
        end
    
        def cb(error,op,uuid)
            if error == 0
                print("success!")
                return
            end
            print(error)
        end
    
        def chksum()
            var cs = 0
            for i:1..19
                cs ^= self.buf[i]
            end
            self.buf[20] = cs
        end
    
        def clr()
            for i:2..19
                self.buf[i] = 0
            end
        end
    
        def writeBuf()
            import BLE
            BLE.set_svc("00010203-0405-0607-0809-0a0b0c0d1910")
            BLE.set_chr("00010203-0405-0607-0809-0a0b0c0d2b11")
            self.chksum()
            print(self.buf)
            BLE.run(12) # op: 12 (write, then disconnect)
        end
    end
    
    gv = GOVEE("AABBCCDDEEFF") # MAC of the lamp
    tasmota.add_driver(gv)
    
    def gv_power(cmd, idx, payload, payload_json)
        if int(payload) > 1
            return 'error'
        end
        gv.clr()
        gv.buf[2] = 1 # power cmd
        gv.buf[3] = int(payload)
        gv.writeBuf()
    end
    
    def gv_bright(cmd, idx, payload, payload_json)
        if int(payload) > 255
            return 'error'
        end
        gv.clr()
        gv.buf[2] = 4 # brightness
        gv.buf[3] = int(payload)
        gv.writeBuf()
    end
    
    def gv_rgb(cmd, idx, payload, payload_json)
        var rgb = bytes(payload)
        print(rgb)
        gv.clr()
        gv.buf[2] = 5 # color
        gv.buf[3] = 5 # manual ??
        gv.buf[4] = rgb[3]
        gv.buf[5] = rgb[0]
        gv.buf[6] = rgb[1]
        gv.buf[7] = rgb[2]
        gv.writeBuf()
    end
    
    def gv_scn(cmd, idx, payload, payload_json)
        gv.clr()
        gv.buf[2] = 5 # color
        gv.buf[3] = 4 # scene
        gv.buf[4] = int(payload)
        gv.writeBuf()
    end
    
    def gv_mus(cmd, idx, payload, payload_json)
        var rgb = bytes(payload)
        print(rgb)
        gv.clr()
        gv.buf[2] = 5 # color
        gv.buf[3] = 1 # music
        gv.buf[4] = rgb[0]
        gv.buf[5] = 0
        gv.buf[6] = rgb[1]
        gv.buf[7] = rgb[2]
        gv.buf[8] = rgb[3]
        gv.writeBuf()
    end
    
    
    tasmota.add_cmd('gpower', gv_power) # only on/off
    tasmota.add_cmd('bright', gv_bright) # brightness 0 - 255
    tasmota.add_cmd('color', gv_rgb) #  color 00FF0000 - sometimes the last byte has to be set to something greater 00, usually it should be 00
    tasmota.add_cmd('scene', gv_scn) # scene 0 - ?,
    tasmota.add_cmd('music', gv_mus) # music 00 - 0f + color 000000   -- does not work at all!!!
    
    #   POWER      = 0x01
    #   BRIGHTNESS = 0x04
    
    #   COLOR      = 0x05
        #   MANUAL     = 0x02 - seems to be wrong for this lamp
        #   MICROPHONE = 0x01 - can not be confirmed yet
        #   SCENES     = 0x04
