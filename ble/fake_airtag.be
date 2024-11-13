#------------------------------------------------------------------------------
- Fake airtag
- source data can be copy from existing AirTag(clone)
- or generated, i.e. confirmed to work with: 
  https://github.com/MatthewKuKanich/FindMyFlipper/blob/main/AirTagGeneration/generate_keys.py
-------------------------------------------------------------------------------#

import BLE
var cbuf = bytes(-255)

class AIRTAG
    var current_func, next_func
    var did_init, mac_changed

    def init()
        import cb
        var cbp = cb.gen_cb(/e,o,u,h->self.cb(e,o,u,h))
        BLE.serv_cb(cbp,cbuf)
        self.mac_changed = false
        self.did_init = false
        var minitvl = int(1000 / 0.625)
        var maxitvl = int(2000 / 0.625)
        cbuf.setbytes(0,bytes("050200000000"))
        cbuf.seti(2,minitvl,2)
        cbuf.seti(4,maxitvl,2)
        BLE.run(232)
        self.current_func = /->self.add_ADV()
    end

    def every_50ms()
        self.current_func()
    end

    def wait() end

    def then(func)
        self.next_func = func
        self.current_func = /->self.wait()
    end

    def every_second()
        if self.did_init == true && self.mac_changed == false
            var m = bytes("aabbccddeeff").reverse() # native byteorder of ble_addr_t
            BLE.set_MAC(m,1)
            BLE.run(231)
            log("AIR: start sending")
            self.mac_changed = true
            self.current_func = /->self.add_ADV()
        end
    end

    def cb(error,op,uuid,handle)
        print(f"{error},{op},{uuid:x},{handle:x}")
        if op == 201
            self.did_init = true
        end
        if error == 0 && op != 229
            self.current_func = self.next_func
        end
    end

    def add_ADV()
        var payload = bytes("1eff4c00121900") # fill in correct data
        cbuf[0] = size(payload)
        cbuf.setbytes(1,payload)
        BLE.run(201)
        self.then(/->self.wait())
    end
end

var airtag = AIRTAG()
tasmota.add_driver(airtag)

