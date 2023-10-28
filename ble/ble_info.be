import BLE

class BLE_INFO : Driver
    var buf
    var services

    def init(MAC,addr_type)
        var cbp = tasmota.gen_cb(/e,o,u->self.cb(e,o,u))
        self.buf = bytes(-256)
        BLE.conn_cb(cbp,self.buf)
        BLE.set_MAC(bytes(MAC),addr_type)
        BLE.run(6)
        print("###########################################################################")
        print("#                TASMOTA BLE device explorer                              #")
        print("###########################################################################")
    end

    def uuid128ToString(uuid)
        return uuid[0..3].tohex()+"-"+uuid[4..5].tohex()+"-"+uuid[6..7].tohex()+"-"+uuid[8..9].tohex()+"-"+uuid[10..15].tohex()
    end

    #define BLE_GATT_CHR_PROP_BROADCAST                     0x01
    #define BLE_GATT_CHR_PROP_READ                          0x02
    #define BLE_GATT_CHR_PROP_WRITE_NO_RSP                  0x04
    #define BLE_GATT_CHR_PROP_WRITE                         0x08
    #define BLE_GATT_CHR_PROP_NOTIFY                        0x10
    #define BLE_GATT_CHR_PROP_INDICATE                      0x20
    #define BLE_GATT_CHR_PROP_AUTH_SIGN_WRITE               0x40
    #define BLE_GATT_CHR_PROP_EXTENDED                      0x80

    def parseFlags(flags)
        var f = []
        if flags & 0x01 f.push("Broadcast") end
        if flags & 0x02 f.push("Read") end
        if flags & 0x04 f.push("WriteNoResp") end
        if flags & 0x08 f.push("Write") end
        if flags & 0x10 f.push("Notify") end
        if flags & 0x20 f.push("Indicate") end
        if flags & 0x40 f.push("AuthSignWrite") end
        if flags & 0x80 f.push("Extended") end
        return f
    end

    def parseServices()
        var i = 2
        self.services = []
        for svc:range(1,self.buf[1])
            var sz = self.buf[i]/8
            var uuid = self.buf[(i+1)..(i+sz)].reverse()
            # print(sz,uuid)
            i += 1+sz
            if sz == 2
                self.services.push(uuid.tohex())
            else
                var s = self.uuid128ToString(uuid)
                self.services.push(s)
            end
        end
        # print(self.buf[1..self.buf[0]])
        # print(self.services)
        self.getCharacteristics()
    end

    def getCharacteristics()
        print("__________________________")
        print("Service: UUID",self.services[0])
        print("    Characteristics:")
        BLE.set_svc(self.services[0])
        BLE.run(7)
    end

    def parseCharacteristics()
        var i = 2
        for chr:range(1,self.buf[1])
            var sz = self.buf[i]/8
            var uuid = self.buf[(i+1)..(i+sz)]
            var flags = self.buf[i+sz+1]
            var handle = self.buf.get(i+sz+2,2)
            if size(uuid) == 2
                uuid = uuid.reverse().tohex()
            else
                uuid = self.uuid128ToString(uuid.reverse())
            end
            print("        UUID:",uuid,f", handle: 0x{handle:04x} ,",self.parseFlags(flags))
            i += 4+sz
        end
        if size(self.services) > 1
            self.services.remove(0)
            self.getCharacteristics()
        else
            print("_______________________________________________________________")
            print("Got all services and characteristics of connected BLE device!")
            print("###############################################################")
        end
    end

    def cb(error,op,uuid)
        if error == 0
            if op == 6
                self.parseServices()
            end
            if op == 7
                self.parseCharacteristics();
            end
            return
        else
            print(error)
            if op == 6
                print("Try to connect to BLE device ...")
                BLE.run(6)
            end
        end
    end

end

ble_info = BLE_INFO("112233445566",0) # BLE device MAC and address type

tasmota.add_driver(ble_info)
