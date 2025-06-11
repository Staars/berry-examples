#------------------------------------------------------------------------------
- Fake heartrate server to get IRK
- will save device to mi32cfg and track this device after reboot
-------------------------------------------------------------------------------#
import BLE
var cbuf = bytes(-255)

class IRK : Driver
    var current_func, next_func

    def init()
        import cb
        var cbp = cb.gen_cb(/e,o,u,h->self.cb(e,o,u,h))
        BLE.serv_cb(cbp,cbuf)
        self.current_func = /->self.add_bpm()
        log("BLE: start hearrate server",1)
    end

    def every_50ms()
        self.current_func()
    end

    def wait()
    end

    def then(func)
        # save function pointers for callback, typically expecting a closure
        self.next_func = func
        self.current_func = /->self.wait()
    end

    def updateMI32cfg()
        import json
        import string
        import persist
        var i = BLE.info()["connection"]
        var d = {}
        log(f"Authenticated: {i}")
        d["MAC"] = string.tr(i["peerID_addr"],":","")
        d["name"] = ""
        try
            d["key"] = bytes(i["IRK"]).reverse().tohex()
            d["name"] = i["name"]
        except ..
            log("M32: could not get IRK, is firmware configured with -DCONFIG_BT_NIMBLE_NVS_PERSIST=y ??",1)
            return
        end
        d["PID"] = "0000"
        var j = []
        var f
        try
            f = open("mi32cfg","r")
            j = json.load(f.read())
            j.push(d)
            f.close()
        except ..
            j.push(d)
        end
        f = open("mi32cfg","w")
        f.write(json.dump(j))
        f.close()
        log(f"Saved {j.tostring()} to mi32cfg")
        persist.setmember(d["name"],cbuf[1..cbuf[0]].tob64()) # not used yet
    end

    def cb(error,op,uuid,handle)
        print(error,op,uuid,handle)
        if op == 201
            print("Handles:",cbuf[1..cbuf[0]])
        elif op == 227
            print("MAC:",cbuf[1..cbuf[0]])
        elif op == 228
            log("Disconnected")
        elif op == 229
            print("Status:",cbuf[1..cbuf[0]])
        elif op == 230
            self.updateMI32cfg()
        end
        if error == 0 && op != 229
            self.current_func = self.next_func
        end
    end

    # custom section
    def add_bpm()
        BLE.set_svc("180D") # Heart Rate Service
        BLE.set_chr("2A37") # Heart Rate Measurements Characteristics (BPM)
        cbuf.setbytes(0,bytes("0100"))
        BLE.run(211,true, 1554) # READ | READ_ENC | NOTIFY |  READ_AUTHENT
        self.then(/->self.add_loc())
    end
    def add_loc()
        BLE.set_chr("2A38") # Body Sensor Location
        var b = bytes().fromstring("Please enter PIN first.")
        cbuf.setbytes(1,b)
        cbuf[0] = size(b)
        BLE.run(211)
        self.then(/->self.add_ScanResp())
    end

    def add_ADV()
        var payload = bytes("02010603020D18") # flags and heartrate svc uuid
        cbuf[0] = size(payload)
        cbuf.setbytes(1,payload)
        BLE.run(201)
        self.then(/->self.wait())
    end

    def add_ScanResp()
        var local_name = "Tasmota BLE"
        var payload = bytes("0201060008") + bytes().fromstring(local_name) # 00 before 08  is a placeholder
        payload[3] = size(local_name) + 1 # ..set size of name
        cbuf[0] = size(payload)
        cbuf.setbytes(1,payload)
        BLE.run(202)
        self.then(/->self.add_ADV())
    end
end

var irk = IRK()
tasmota.add_driver(irk)
