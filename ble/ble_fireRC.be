# Simple Berry driver for the Amazon remote control (a cheap BLE HID controller)

import BLE

var hid

class HID
    static hid_service = "1812"
    var hid_chars
    static battery_service = "180f"
    static device_info_service = "180a"
    var dev_chars
    var init_step, init_finished

    def init()
        self.init_step = 0
        self.init_finished = false
        self.hid_chars = ["2a4a","2a4b","2a4e","2a4d"]
        self.dev_chars = ["2A23","2A24","2A25","2A26","2A27","2A28","2A29","2A2a","2A50"]
        self.nextStep()
    end

    def nextStep()
        if self.init_step == 0
            self.getDeviceInfo()
        elif self.init_step == 1
            self.readBattery()
        elif self.init_step == 2
            self.initHID()
        else
            log("HID: initialized")
        end
    end

    def getDeviceInfo()
        BLE.set_svc(self.device_info_service,true)
        BLE.set_chr(self.dev_chars[0])
        if size(self.dev_chars) > 1
            self.dev_chars = self.dev_chars[1..]
        else
            self.init_step += 1
            self.dev_chars = nil
        end
        BLE.run(1)
    end


    def readBattery()
        BLE.set_svc(self.battery_service)
        BLE.set_chr("2a19")
        BLE.run(1)
        if self.init_finished == false
            self.init_step += 1
        end
    end

    def initHID()
        BLE.set_svc(self.hid_service)
        BLE.set_chr(self.hid_chars[0])
        if size(self.hid_chars) > 1
            self.hid_chars = self.hid_chars[1..]
            BLE.run(1)
        else
            self.hid_chars = nil
            BLE.run(3)
            self.init_step += 1
            self.init_finished = true
        end
    end

    def readCB(error,uuid,handle,buffer)
        if error != 0
            log(f"HID: characteristic {uuid:x} not supported")
        else
            if uuid == 0x2a23
                log(f"HID: System ID: {buffer.tohex()}")
            elif uuid == 0x2a2a
                log(f"HID: Certification: {buffer.tohex()}")
            elif uuid == 0x2a50
                log(f"HID: PNP ID: {buffer.tohex()}")
            elif self.init_step == 0
                log(f"HID: device info {uuid:x} : {buffer.asstring()}")
            elif uuid == 0x2a19
                log(f"HID: battery: {buffer.tohex()}")
            elif uuid == 0x2a4a
                log(f"HID: info: {buffer.tohex()}")
            elif uuid == 0x2a4b
                log(f"HID: report map: {buffer.tohex()}")
            elif uuid == 0x2a4e
                log(f"HID: protocol mode: {buffer.tohex()}")
            end 
        end
        self.nextStep()
    end
end

class BLE_AR : Driver
    var buf, init_step
    var audio_buf
    var connecting, connected

    def init(MAC,addr_type)
        var cbp = tasmota.gen_cb(/e,o,u,h->self.cb(e,o,u,h))
        self.buf = bytes(-256)
        BLE.conn_cb(cbp,self.buf)
        BLE.set_MAC(bytes(MAC),addr_type)
        global.hid = HID()
        self.init_step = 0
        self.audio_buf = bytes()
        print("BLE: will try to connect to Fire remote with MAC:",MAC)
        tasmota.add_fast_loop(/-> BLE.loop()) # needed for mouse position
    end

    def every_second()
        if (self.connecting == false && self.connected == false)
            print("BLE: try to reconnect RC")
            hid.readBattery()
        end
    end

    # def every_50ms()
    # end

    def saveAudioFrames()
        self.audio_buf..self.buf[1..self.buf[0]]
    end

    def handle_HID_notification(h) 
        import mqtt
        var t = "key"
        var v = ""
        if h == 46
            var k = self.buf[3]
            if k == 0x4f
                v = "right"
            elif k == 0x50
                v = "left"
            elif k == 0x51
                v = "down"
            elif k == 0x52
                v = "up"
            elif k == 0xf1
                v = "back"
            elif k == 0x66
                v = "on"
            elif k == 0x58
                v = "select"
            end
        elif h == 54
            self.saveAudioFrames()
        elif h == 50
            var k = self.buf[1]
            if k == 0xe2
                v = "mute"
            elif k == 0x23
                v = "home"
            elif k == 0x21
                v = "micro"
                var payload = bytes("01")
                self.buf[0] = size(payload)
                self.buf.setbytes(1,payload)
                BLE.run(2,false,0x3e)
            elif k == 0xea
                v = "minus"
            elif k == 0xe9
                v = "plus"
            elif k == 0x40
                v = "menu"
            elif k == 0xb4
                v = "rewind"
            elif k == 0xb3
                v = "forward"
            elif k == 0xcd
                v = "play"
            elif k == 0x8d
                v = "TV"
                var payload = bytes("00")
                self.buf[0] = size(payload)
                self.buf.setbytes(1,payload)
                BLE.run(2,false,0x3e)
            end
        elif h == 71
            var k = self.buf[1]
            if k == 0xa1
                v = "prime"
            elif k == 0xa2
                v = "netflix"
                var f = open("audio.opus", "w") # opus??
                f.write(self.audio_buf)
                f.close()
            elif k == 0xa3
                v = "disney"
            elif k == 0xa4
                v = "hulu"
            end
        end
        if v != ''
            mqtt.publish("tele/FireRC",format('{"%s":"%s"}',t,v))
        else # will be triggered on button release too
            print(self.buf[1..self.buf[0]],h) # show the packet as byte buffer
        end
    end

    def cb(error,op,uuid,handle)
        if error == 0
            if op == 1 # read OP
                # print(op,uuid)
                hid.readCB(error,uuid,handle,self.buf[1..self.buf[0]])
            elif op == 3
                if uuid == 0x2A4D
                    print(0x59)
                    BLE.set_chr("2aff")
                    BLE.run(3,false,0x59)
                    return
                end
                if handle == 92
                    print(0x5c)
                    BLE.run(3,false,0x5c)
                    return
                else
                    print(handle)
                end
                self.connecting = false
                self.connected = true
                print("BLE: init completed for FireRC")
            elif op == 5
                self.connected = false
                self.connecting = false
                print("BLE: did disconnect FireRC ... will try to reconnect")
            elif op == 103 # notification OP
                if self.connected == false return end
                self.handle_HID_notification(handle)
            end
        else
            if op == 1 # read OP
                # print(op,uuid)
                hid.readCB(error,uuid,handle,self.buf[1..self.buf[0]])
                return
            else
                print("BLE: error:",error)
            end
            if self.connecting == true
                print("BLE: init sequence failed ... try to repeat")
                self.connecting = false
            end
        end
    end

end

ar_hid = BLE_AR("475441925FB3",0)  # Amazon remote HID controller MAC and address type
tasmota.add_driver(ar_hid)

#-
12:43:21.924 Service: UUID: 1800
12:43:21.925     Characteristics:
12:43:22.115          UUID: 2A00 , handle: 0x0003 , ['Read']
12:43:22.117          UUID: 2A01 , handle: 0x0005 , ['Read']
12:43:22.120          UUID: 2A04 , handle: 0x0007 , ['Read']
12:43:22.122 __________________________
12:43:22.123 Service: UUID: 180A
12:43:22.123     Characteristics:
12:43:22.215          UUID: 2A29 , handle: 0x000a , ['Read']
12:43:22.217          UUID: 2A24 , handle: 0x000c , ['Read']
12:43:22.219          UUID: 2A25 , handle: 0x000e , ['Read']
12:43:22.222          UUID: 2A27 , handle: 0x0010 , ['Read']
12:43:22.223          UUID: 2A26 , handle: 0x0012 , ['Read']
12:43:22.225          UUID: 2A28 , handle: 0x0014 , ['Read']
12:43:22.227          UUID: 2A23 , handle: 0x0016 , ['Read']
12:43:22.230          UUID: 2A2A , handle: 0x0018 , ['Read']
12:43:22.232          UUID: 2A50 , handle: 0x001a , ['Read']
12:43:22.233 __________________________
12:43:22.234 Service: UUID: 180F
12:43:22.235     Characteristics:
12:43:22.416          UUID: 2A19 , handle: 0x001d , ['Read', 'Notify']
12:43:22.417 __________________________
12:43:22.418 Service: UUID: 1812
12:43:22.418     Characteristics:
12:43:22.515          UUID: 2A4A , handle: 0x0021 , ['Read']
12:43:22.517          UUID: 2A4C , handle: 0x0023 , ['WriteNoResp']
12:43:22.519          UUID: 2A4B , handle: 0x0025 , ['Read']
12:43:22.522          UUID: 2A4E , handle: 0x0027 , ['Read', 'WriteNoResp']
12:43:22.524          UUID: 2A22 , handle: 0x0029 , ['Read', 'Notify']
12:43:22.526          UUID: 2A32 , handle: 0x002c , ['Read', 'WriteNoResp', 'Write']
12:43:22.528          UUID: 2A4D , handle: 0x002e , ['Read', 'Notify']
12:43:22.530          UUID: 2A4D , handle: 0x0032 , ['Read', 'Notify']
12:43:22.533          UUID: 2A4D , handle: 0x0036 , ['Read', 'Notify']
12:43:22.535          UUID: 2A4D , handle: 0x003a , ['Read', 'Notify']
12:43:22.537          UUID: 2A4D , handle: 0x003e , ['Read', 'WriteNoResp', 'Write']
12:43:22.539          UUID: 2A4D , handle: 0x0041 , ['Read', 'WriteNoResp', 'Write']
12:43:22.541          UUID: 2A4D , handle: 0x0044 , ['Read', 'Write']
12:43:22.544          UUID: 2A4D , handle: 0x0047 , ['Read', 'Notify']
12:43:22.545 __________________________
12:43:22.546 Service: UUID: FE151500-5E8D-11E6-8B77-86F30CA893D3
12:43:22.547     Characteristics:
12:43:22.666          UUID: FE151501-5E8D-11E6-8B77-86F30CA893D3 , handle: 0x004c , ['Read', 'Write', 'Indicate']
12:43:22.679          UUID: FE151502-5E8D-11E6-8B77-86F30CA893D3 , handle: 0x004f , ['Read', 'Write']
12:43:22.683          UUID: FE151503-5E8D-11E6-8B77-86F30CA893D3 , handle: 0x0051 , ['Read', 'Write', 'Indicate']
12:43:22.687          UUID: FE151504-5E8D-11E6-8B77-86F30CA893D3 , handle: 0x0054 , ['Read']
12:43:22.688 __________________________
12:43:22.689 Service: UUID: 5DE20000-5E8D-11E6-8B77-86F30CA893D3
12:43:22.690     Characteristics:
12:43:22.817          UUID: 5DE24A17-5E8D-11E6-8B77-86F30CA893D3 , handle: 0x0057 , ['Write']
12:43:22.820          UUID: 5DD24A18-5E8D-11E6-8B77-86F30CA893D3 , handle: 0x0059 , ['Notify']
12:43:22.824          UUID: 5DE24A19-5E8D-11E6-8B77-86F30CA893D3 , handle: 0x005c , ['Read', 'Notify']
12:43:22.825 __________________________
12:43:22.826 Service: UUID: CFBFA000-762C-4912-A043-20E3ECDE0A2D
12:43:22.827     Characteristics:
12:43:22.918          UUID: CFBFA001-762C-4912-A043-20E3ECDE0A2D , handle: 0x0060 , ['Write', 'Notify']
12:43:22.922          UUID: CFBFA003-762C-4912-A043-20E3ECDE0A2D , handle: 0x0063 , ['Write']
12:43:22.925          UUID: CFBFA002-762C-4912-A043-20E3ECDE0A2D , handle: 0x0065 , ['WriteNoResp', 'Notify']
12:43:22.929          UUID: CFBFA004-762C-4912-A043-20E3ECDE0A2D , handle: 0x0068 , ['WriteNoResp', 'Notify']
12:43:22.930 __________________________
12:43:22.931 Service: UUID: 54534542-2045-4854-2053-492049415447
12:43:22.932     Characteristics:
12:43:23.066          UUID: 54534543-2045-4854-2053-492049415447 , handle: 0x006c , ['Read']
12:43:23.070          UUID: 54534544-2045-4854-2053-492049415447 , handle: 0x006e , ['Read', 'Write']
12:43:23.074          UUID: 54534545-2045-4854-2053-492049415447 , handle: 0x0070 , ['Read', 'Write']
12:43:23.077          UUID: 54534546-2045-4854-2053-492049415447 , handle: 0x0072 , ['Read', 'Write', 'Notify']
12:43:23.081          UUID: 54534547-2045-4854-2053-492049415447 , handle: 0x0075 , ['Read', 'Write']
12:43:23.085          UUID: 54534548-2045-4854-2053-492049415447 , handle: 0x0077 , ['Read', 'Write', 'Notify']
12:43:23.088          UUID: 54534549-2045-4854-2053-492049415447 , handle: 0x007a , ['Read', 'Write', 'Notify']
-#
