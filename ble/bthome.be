# Tasmota BLE server example (BTHome)
import BLE
var cbuf = bytes(-255)

class BTHOME : Driver
    var current_func, next_func
    var temperature, humidity, name

    def init()
        var cbp = tasmota.gen_cb(/e,o,u,h->self.cb(e,o,u,h))
        BLE.serv_cb(cbp,cbuf)
        self.current_func = /->self.update_ADV()
        self.name = "Tas BTHome"
        self.temperature = 25.0
        self.humidity = 50.55
        print("BLE: BTHome demo")
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

    def cb(error,op,uuid,handle)
        print(error,op,uuid,handle)
        if error == 0
            self.current_func = self.next_func
        end
    end

    def getTemperature()
        var t = bytes("020000") # type is 02, last 2 bytes placeholder
        t.seti(1,int(self.temperature * 100),2)
        return t
    end

    def getHumidity()
        var h = bytes("030000") # type is 03, last 2 bytes placeholder
        h.seti(1,int(self.humidity * 100),2)
        return h
    end

    def update_SVC_data()
        var len_svc = bytes("0016") # pos 0 is placeholder for length
        var uuid_info = bytes("D2FC40") # uuid FCD2 and Info 40 (no encryption)
        # var svc_data = bytes("0a16D2FC4002C40903BF13") # demo payload from https://bthome.io/format/
        var t = self.getTemperature()
        var h = self.getHumidity()
        var svc_data = len_svc + uuid_info + t + h
        svc_data[0] = size(svc_data) - 1
        return svc_data
    end

    def update_ADV()
        var flags = bytes("020106")
        var name =  bytes("0009") + bytes().fromstring(self.name)
        name[0] = size(self.name) + 1
        var svc_data = self.update_SVC_data()
        var payload = flags + name + svc_data
        print("BTHOME payload:",payload)
        cbuf[0] = size(payload)
        cbuf.setbytes(1,payload)
        BLE.run(201)
        self.then(/->self.wait())
    end
end

var bthome = BTHOME()
tasmota.add_driver(bthome)
