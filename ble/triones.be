import BLE

class BLE_TRIONES : Driver
    var buf
    var connected

    def init(MAC,addr_type)
        var cbp = tasmota.gen_cb(/e,o,u,h->self.cb(e,o,u,h))
        self.buf = bytes(-256)
        BLE.conn_cb(cbp,self.buf)
        self.connected = false
        BLE.set_MAC(bytes(MAC),addr_type)
        BLE.set_svc("ffd0")
        BLE.set_chr("ffd4")
        BLE.run(3)
        tasmota.add_driver(self)
    end

    def getStatus()
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
        if self.buf[1] != 0x66 && self.buf[12] != 0x99
            print("BLE: unknown info format, wrong magic numbers")
            return
        end
        var power = "off"
        if self.buf[3] == 0x23
            power = "on"
        end
        var mode = "static"
        if self.buf[4] != 0x41 # static = 0x41, built-in = 0x25-0x38
            mode = "mode"+(self.buf[4]-0x25)
        end
        var speed = self.buf[6]
        var red = self.buf[7]
        var green = self.buf[8]
        var blue = self.buf[9]
        var white = self.buf[10]
        mqtt.publish("tele/triones",format('{"Power":"%s","Mode":"%s","Speed":%u,"Color":%02x%02x%02x,"Brightness":%u}',power,mode,speed,red,green,blue,white))
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

    def setEffect(mode,speed)
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
end

ble_triones = BLE_TRIONES("2215220003AB",0) # change MAC to your value, address type is probably always 0
