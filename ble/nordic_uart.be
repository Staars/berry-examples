#------------------------------------------------------------------------------
- NRF Connect UART 2 Tasmota
- use with App NRF Toolbox - Nordic UART Service
- use Log console
- first command must be '123456' as PIN at application level
- phone app will show direct command response, not the whole log
-------------------------------------------------------------------------------#

import BLE
var cbuf = bytes(-255)

class NRFUART : Driver
    var current_func, next_func
    var pin_ready
    var ssid, pwd, imp_state, msg_buffer, ble_server_up
    static PIN = "123456" # 🤫

    static nordic_svc = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
    static RX  = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
    static TX  = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

    def init()
        import cb
        var cbp = cb.gen_cb(/e,o,u,h->self.cb(e,o,u,h))
        BLE.serv_cb(cbp,cbuf)
        # BLE.set_svc(self.imp_svc)
        self.current_func = /->self.add_TX()
        log("BLE: ready for Nordic UART via BLE")
        self.pin_ready = false
        self.msg_buffer = []
        self.ble_server_up = false
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

    def sendTX(r)
        var resp_left = nil
        if size(r) > size(cbuf) - 2
            log(f"message too large with {size(r)} chars!! ... will cut it",3)
            resp_left = r[253..]
            r = r[0..253]
        end
        BLE.set_chr(self.TX)
        cbuf[0] = size(r)
        var r_buf = bytes().fromstring(r)
        log(r_buf)
        cbuf.setbytes(1,r_buf)
        log(cbuf)
        BLE.run(211)
        if resp_left == nil
            self.then(/->self.wait())
        else
            self.then(/->self.sendTX(resp_left))
        end
    end

    def execCmd(c)
        var resp
        if self.pin_ready == true
            resp = tasmota.cmd(c).tostring()
            log(f"{c}->{resp}",1)
        else
            if c == self.PIN
                resp = "PIN accepted ... enter commands"
                self.pin_ready = true
            else
                resp = "Wrong PIN!!"
                print(c,self.PIN)
            end
        end
        self.sendTX(resp)
    end

    def cb(error,op,uuid,handle)
        # print(error,op,uuid,handle)
        if op == 201
            print("Handles:",cbuf[1..cbuf[0]])
            self.ble_server_up = true
        elif op == 221

        elif op == 222
            if handle == 6
                self.then(/->self.execCmd((cbuf[1..cbuf[0]]).asstring()))
            end
        elif op == 227

        elif op == 228
            log("BLE: Disconnected",1)
            self.pin_ready = false
        elif op == 229
            # print("Status:",cbuf[1..cbuf[0]])
        end
        if error == 0 && op != 229
            self.current_func = self.next_func
        end
    end

    # custom section
    def add_TX()
        BLE.set_svc(self.nordic_svc)
        BLE.set_chr(self.TX)
        cbuf.setbytes(0,bytes("0100"))
        BLE.run(211)
        self.then(/->self.add_RX())
    end
    def add_RX()
        BLE.set_chr(self.RX)
        var b = bytes().fromstring("Please enter PIN first.")
        cbuf.setbytes(1,b)
        cbuf[0] = size(b)
        BLE.run(211)
        self.then(/->self.add_ScanResp())
    end
    # services and characteristics are set, now start the server with first set of advertisement data
    def add_ADV()
        import string
        var svcuuid = string.tr(self.nordic_svc,"-","")
        var payload = bytes("0201061107") + bytes(svcuuid).reverse() # flags and Nordic svc uuid
        cbuf[0] = size(payload)
        cbuf.setbytes(1,payload)
        BLE.run(201)
        self.then(/->self.wait())
    end
    # unused example function, could be called from add_fff2()
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

var nrfuart = NRFUART()
tasmota.add_driver(nrfuart)
