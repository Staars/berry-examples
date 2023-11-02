# BLE light controller
# compatible to "Happy Lighting, "Triones","ICS", although there might be differences
import BLE

class BLE_TRIONES : Driver
    var buf
    var connected, requestStatus

    def init(MAC,addr_type)
        var cbp = tasmota.gen_cb(/e,o,u,h->self.cb(e,o,u,h))
        self.buf = bytes(-256)
        BLE.conn_cb(cbp,self.buf)
        self.connected = false
        self.requestStatus = false
        BLE.set_MAC(bytes(MAC),addr_type)
        BLE.set_svc("ffd0")
        BLE.set_chr("ffd4")
        BLE.run(3)
        tasmota.add_driver(self)
    end

    def getStatus()
        self.requestStatus = true
        self.buf[0] = 3
        self.buf[1] = 0xef
        self.buf[2] = 0x01
        self.buf[3] = 0x77
        BLE.run(2)
    end

    def getName()
        print("BLE: did connect to Triones light controller -",self.buf[1..self.buf[0]].asstring())
        BLE.set_svc("ffd5")
        BLE.set_chr("ffd9") # write to
    end

    def showStatus()
        import mqtt
        print(self.buf[1..self.buf[0]])
        if self.buf[1] != 0x66 && self.buf[12] != 0x99
            print("BLE: unknown info format, wrong magic numbers")
            return
        end
        var power = "off"
        if self.buf[3] == 0x23
            power = "on"
        end
        var color
        if self.buf[10] != 0
            color = format('",White":%u',self.buf[10])
        else
            color = format('",Color":"%02x%02x%02x"',self.buf[7],self.buf[8],self.buf[9])
        end
        var speed = ""
        var mode = "static"
        if self.buf[4] != 0x41 # static = 0x41, built-in = 0x25-0x38
            mode = format("scene%u",(self.buf[4]-0x25))
            speed = format(',"Speed":%u', self.buf[6])
            color = ""
        end

        var p = format('{"Power":"%s","Mode":"%s"%s%s}',power,mode,speed,color)
        mqtt.publish("tele/triones",p)
        self.requestStatus = false
    end

    def setColor(r,g,b)
        self.buf[0] = 7
        self.buf[1] = 0x56
        self.buf[2] = r
        self.buf[3] = g
        self.buf[4] = b
        self.buf[5] = 0
        self.buf[6] = 0xf0
        self.buf[7] = 0xaa
        BLE.run(2)
    end

    def setWhite(intensity)
        self.buf[0] = 7
        self.buf[1] = 0x56
        self.buf[2] = 0
        self.buf[3] = 0
        self.buf[4] = 0
        self.buf[5] = intensity
        self.buf[6] = 0x0f
        self.buf[7] = 0xaa
        BLE.run(2)
    end

    def setPower(onOff)
        self.buf[0] = 3
        self.buf[1] = 0xcc
        self.buf[2] = 0x24 - onOff
        self.buf[3] = 0x33
        BLE.run(2)
    end

    def setScene(mode,speed)
        self.buf[0] = 4
        self.buf[1] = 0xbb
        self.buf[2] = mode + 0x25
        self.buf[3] = speed
        self.buf[4] = 0x44
        BLE.run(2)
    end

    def handleNotification()
        if self.buf[0] == 12
            self.showStatus()
        else
            print("BLE: unknown payload")
        end
    end


    def cb(error,op,uuid,handle)
        if error == 0
            if op == 5
                self.connected = false
                print("BLE: did disconnect")
            elif op == 1
                self.getName()
            elif op == 2
                if self.requestStatus == false
                    self.getStatus()
                end
            elif op == 3
                self.connected = true
                BLE.set_svc("1800")
                BLE.set_chr("2a00") # get name
                BLE.run(1)
            elif op == 103
                self.handleNotification()
            end
        else
            print(error)
        end
    end

    def cmdPower(cmd, idx, payload, payload_json)
        var v = int(payload)
        if v > 1
            tasmota.resp_cmnd_error()
        end
        self.setPower(v)
        tasmota.resp_cmnd_str(payload)
    end

    def cmdWhite(cmd, idx, payload, payload_json)
        var v = int(payload)
        if v > 255
            tasmota.resp_cmnd_error()
        end
        self.setWhite(v)
        tasmota.resp_cmnd_str(payload)
    end

    def cmdColor(cmd, idx, payload, payload_json)
        var rgb = bytes(payload)
        if size(rgb) != 3
            tasmota.resp_cmnd_error()
        end
        self.setColor(rgb[0],rgb[1],rgb[2])
        tasmota.resp_cmnd_str(payload)
    end

    def cmdScene(cmd, idx, payload, payload_json)
        var m = int(idx)
        if m > 19
            tasmota.resp_cmnd_error()
        end
        var s = int(payload)
        if s > 255
            tasmota.resp_cmnd_error()
        end
        self.setScene(m,s)
        var r = format('mode:%i,speed:%i',m,s)
        tasmota.resp_cmnd_str(r)
    end
end

ble_triones = BLE_TRIONES("2215220003AB",0)

tasmota.add_cmd('lpower', /c,i,p,j->ble_triones.cmdPower(c,i,p,j)) # only 0/1 - name power could clash with regular Tasmota command
tasmota.add_cmd('white', /c,i,p,j->ble_triones.cmdWhite(c,i,p,j)) # brightness 0 - 255
tasmota.add_cmd('color', /c,i,p,j->ble_triones.cmdColor(c,i,p,j)) # color as hexcode like: 00FF00 
tasmota.add_cmd('scene', /c,i,p,j->ble_triones.cmdScene(c,i,p,j)) # scene 0 - 19, speed 1 (fast )-255 (slow)

#- Protcol from: https://github.com/madhead/saberlight/blob/master/protocols/Triones/protocol.md - Many Thanks!!

0: Seven color cross fade
1: Red gradual change
2: Green gradual change
3: Blue gradual change
4: Yellow gradual change
5: Cyan gradual change
6: Purple gradual change
7: White gradual change
8: Red, Green cross fade
9: Red blue cross fade
10: Green blue cross fade
11: Seven color stobe flash
12: Red strobe flash
13: Green strobe flash
14: Blue strobe flash
15: Yellow strobe flash
16: Cyan strobe flash
17: Purple strobe flash
18: White strobe flash
19: Seven color jumping change

-#
