#-
  WIP ... very unfinished!
  LF2412.be - HLK-LD2412 24GHz smart wave motion sensor support for Tasmota via BLE and Berry
  port of xsns_102_ld2410.ino from Theo Arends
  SPDX-FileCopyrightText: 2022 Christian Baars
  SPDX-License-Identifier: GPL-3.0-only
-#

class LD2412 : Driver
    var buf
    var current_func, next_func

    static MAX_GATES                 = 13       # 0 to 13 (= 14) - DO NOT CHANGE
    static CMND_START_CONFIGURATION  = 0xFF
    static CMND_END_CONFIGURATION    = 0xFE
    static CMND_SET_DISTANCE         = 0x60
    static CMND_READ_PARAMETERS      = 0x61
    static CMND_START_ENGINEERING    = 0x62
    static CMND_END_ENGINEERING      = 0x63
    static CMND_SET_SENSITIVITY      = 0x64
    static CMND_GET_FIRMWARE         = 0xA0
    static CMND_SET_BAUDRATE         = 0xA1
    static CMND_FACTORY_RESET        = 0xA2
    static CMND_REBOOT               = 0xA3

    static CMND_BLE_NOTIFY           = 0xA8     # not needed for LD2412

    static config_header = bytes("FDFCFBFA")
    static config_footer = bytes("04030201")
    static target_header = bytes("F4F3F2F1")
    static target_footer = bytes("F8F7F6F5")

    var moving_distance
    var moving_energy
    var static_distance
    var static_energy
    var detect_distance
    var moving_sensitivity
    var static_sensitivity
    var sensitivity_counter

    def sendBLE(packet)
        import BLE
        self.buf.setbytes(1,packet)
        self.buf[0] = size(packet)
        BLE.set_chr("FFF2")
        BLE.run(2,false)
        log(f"LD2: send {packet}",3)
        self.then(/->self.wait()) #fallback, if calling function does not "reset" this
    end

    def sendCMD(cmd,val)
        var val_len = 0
        if val != nil
            val_len = size(val)
        end
        var sz = 4 + 2 + 2 + val_len + 4 # header + len + cmd + val + footer
        var cmd_buf = bytes(-sz)
        cmd_buf.setbytes(0,self.config_header)
        cmd_buf[4] = 2 + val_len
        cmd_buf[6] = cmd
        if val != nil
            cmd_buf.setbytes(8,val)
        end
        cmd_buf.setbytes(8+val_len,self.config_footer)
        self.sendBLE(cmd_buf)
    end

    def init(MAC)
        log("BLE: start LD2412 driver")
        import BLE
        self.buf = bytes(-256)
        var cbp = tasmota.gen_cb(/e,o,u,h->self.cb(e,o,u,h)) # create a callback function pointer
        self.moving_sensitivity = bytes(-(self.MAX_GATES + 1))
        self.static_sensitivity = bytes(-(self.MAX_GATES + 1))
        BLE.conn_cb(cbp,self.buf)
        BLE.set_MAC(bytes(MAC),0) # addrType: 0
        BLE.run(6,false) # read all services, was needed in tests
        log("BLE: discover services")
        self.then(/->self.subscribe())
    end

    def subscribe()
        import BLE
        BLE.set_svc("FFF0")
        BLE.set_chr("FFF1")
        BLE.run(3,true)
        self.then(/->self.bootStepStart())
    end

    # def initNoti()
    #     self.sendCMD(self.CMND_BLE_NOTIFY,bytes().fromstring("HiLink")) #48694c696e6b = HiLink in HEX
    #     print("LD2: Init notifications")
    #     self.then(/->self.bootStepStart())
    # end

    def bootStepStart()
        self.setCfgMode(true)
        self.then(/->self.getFW())
    end

    def getFW()
        self.sendCMD(self.CMND_GET_FIRMWARE)
        log("LD2: Request FW")
        self.then(/->self.bootStepEnd())
    end

    def bootStepEnd()
        self.setCfgMode(false)
        self.then(/->self.wait())
    end

    def factoryReset()
        self.sendCMD(self.CMND_FACTORY_RESET)
        log("LD2: Factory reset")
        self.then(/->self.setCfgMode(false))
    end

    def setCfgMode(on)
        if on == true
            self.sendCMD(self.CMND_START_CONFIGURATION,bytes("0100"))
            log("LD2: Start config mode")
        else
            self.sendCMD(self.CMND_END_CONFIGURATION)
            log("LD2: Stop config mode")
        end
    end

    def setEngMode(on)
        if on == true
            self.sendCMD(self.CMND_START_ENGINEERING,bytes("0100"))
            log("LD2: Start engineering mode")
        else
            self.sendCMD(self.CMND_END_ENGINEERING)
            log("LD2: Stop engineering mode")
        end
        self.then(/->self.setCfgMode(false))
    end

    def setMaxDistAndNoOneDur(max_mov_dist_range, max_stat_dist_range, no_one_duration)
        var val = bytes(-18)
        val[2] = max_mov_dist_range
        val[6] = 1
        val[8] = max_stat_dist_range
        val[12] = 2
        val.set(14,no_one_duration,-2) #big-endian
        self.sendCMD(self.CMND_SET_DISTANCE,val)
        self.then(/->self.setCfgMode(false))
    end

    def settGateSensitivity(gate, moving_sensitivity, static_sensitivity)
        var val = bytes(-18)
        val[2] = gate
        val[6] = 1
        val[8] = moving_sensitivity
        val[12] = 2
        val[14] = static_sensitivity
        self.sendCMD(self.CMND_SET_SENSITIVITY,val)
    end

    def settAllSensitivity(sensitivity)
        var val = bytes(-18)
        val[2] = 0xff
        val[3] = 0xff
        val[6] = 1
        val[8] = sensitivity
        val[12] = 2
        val[14] = sensitivity
        self.sendCMD(self.CMND_SET_SENSITIVITY,val)
    end

    # our little promise implementation
    def wait()
        # do nothing
    end

    def then(func)
        # save function pointers for callback, typically expecting a closure
        self.next_func = func
        self.current_func = self.wait
    end

    def every_second()
        self.current_func()
        if self.moving_distance != nil
            # very unfinished
            # print(self.buf[1..self.buf[0]])
        end
    end

    def handleCFG()
        # BLE buffer shifted one byte to the right
        #  0  1  2  3  4  5  6  7  8  9  10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38
        # len FD FC FB FA 1C 00 61 01 00 00 AA 08 08 08 32 32 28 1E 14 0F 0F 0F 0F 00 00 28 28 1E 1E 14 14 14 05 00 04 03 02 01 - Default
        if self.buf[7] == self.CMND_READ_PARAMETERS
            print("LD2: moving_distance_gate",self.buf[13],"static_distance_gate",self.buf[14],"no one duration",self.buf.get(33,-2))
            for i:0..self.MAX_GATES
                print("LD2: moving sens",i, self.buf(15+i), "static sens",i, self.buf(24+i))
            end
        elif self.buf[7] == self.CMND_START_CONFIGURATION || self.buf[7] == self.CMND_END_CONFIGURATION
            self.current_func = self.next_func # could be a "promise" waiting
            log("LD2: Sensor ACK")
        elif self.buf[7] == self.CMND_GET_FIRMWARE
            #  0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 18 19 20 21 22
            # len FD FC FB FA 0C 00 A0 01 00 00 00 01 07 01 16 15 09 22 04 03 02 01
            #    header     |len  |ty|hd|ack  |ftype|major|minor      |trailer
            #               |   12|  | 1|    0|  256|  1.7|   22091516|
            import string
            var s  = string.format("LD2: Firmware version V%d.%02d.%02d%02d%02d%02d",self.buf[14],self.buf[13],self.buf[18],self.buf[17],self.buf[16],self.buf[15])
            log(s)
        else
            print(self.buf[1..self.buf[0]])
        end
    end

    def handleTRG()
        # BLE buffer shifted one byte to the right
        #  0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 18 19 20 21 22 23
        # 17 F4 F3 F2 F1 0D 00 02 AA 00 00 00 00 00 00 37 00 00 55 00 F8 F7 F6 F5 - No target
        # 17 F4 F3 F2 F1 0D 00 02 AA 03 46 00 34 00 00 3C 00 00 55 00 F8 F7 F6 F5 - Movement and Stationary target
        # 17 F4 F3 F2 F1 0D 00 02 AA 02 54 00 00 00 00 64 00 00 55 00 F8 F7 F6 F5 - Stationary target
        #len header     |len  |dt|hd|st|movin|me|stati|se|detec|tr|ck|trailer
        if self.buf[9] != 0
            if self.buf[7] == 2
                self.moving_distance = self.buf.get(10,2)
                self.moving_energy = self.buf[12];
                self.static_distance = self.buf.get(13,2)
                self.static_energy = self.buf[15];
                self.detect_distance = self.buf.get(16,2)
            else
                log("LD2: engineering mode")
            end
        else
            # print(self.buf[1..self.buf[0]])
        end
    end

    def handle_noti()
        if self.buf[1] == 0xfd
            self.handleCFG()
        elif self.buf[1] == 0xf4
            self.handleTRG()
        else
            print(self.buf[1..self.buf[0]])
        end
    end

    def cb(error,op,uuid,handle)
        if error == 0
            if op == 103
                self.handle_noti()
                return
            end
            self.current_func = self.next_func
            log("BLE: Op: {op}",3)
            return
        end
        log("BLE: Error: {error}",1)
    end

    def serviceSensitivities()
        if self.sensitivity_counter < 0
            self.setCfgMode(false)
            log("LD2: Did set sensitivities",2)
            self.then(/->self.setCfgMode(false))
        else
            self.settGateSensitivity(self.sensitivity_counter,self.moving_sensitivity[self.sensitivity_counter],self.static_sensitivity[self.sensitivity_counter])
            self.sensitivity_counter -= 1
            self.then(/->self.serviceSensitivities())
            print("LD2:",self.sensitivity_counter + 1,"steps left")
        end
    end

    #- console commands -#
    def cmndDuration(cmd, idx, payload, payload_json)
        var pl = int(payload)
        self.setCfgMode(true)
        if pl == 0
            self.then(/->self.factoryReset())
        else
            self.then(/->self.setMaxDistAndNoOneDur(8, 8, pl))
        end
        tasmota.resp_cmnd({"Duration":pl})
    end

    def cmndMovingSens(cmd, idx, payload, payload_json)
        import string
        var pl = string.split(payload,",")
        var i = 0
        for s:pl
            self.moving_sensitivity[i] = int(s) #TODO error check
            i += 1
        end
        self.sensitivity_counter = self.MAX_GATES
        self.setCfgMode(true)
        self.then(/->self.serviceSensitivities())
        tasmota.resp_cmnd({"MovingSens":pl})
    end

    def cmndStaticSens(cmd, idx, payload, payload_json)
        import string
        var pl = string.split(payload,",")
        var i = 0
        for s:pl
            self.static_sensitivity[i] = int(s) #TODO error check
            i += 1
        end
        self.sensitivity_counter = self.MAX_GATES
        self.setCfgMode(true)
        self.then(/->self.serviceSensitivities())
        tasmota.resp_cmnd({"StaticSens":pl})
    end

    def cmndEngMode(cmd, idx, payload, payload_json)
        var pl = int(payload) > 0
        self.setCfgMode(true)
        self.then(/->self.setEngMode(pl))
        tasmota.resp_cmnd({"Engineering mode":payload})
    end

    #- display sensor value in the web UI -#
    def web_sensor()
        if self.moving_distance == nil return nil end
        import string
        var msg = string.format(
                 "{s}LD2412 moving distance{m}%u cm{e}"..
                 "{s}LD2412 static distance{m}%u cm{e}"..
                 "{s}LD2412 detect distance{m}%u cm{e}",
                 self.moving_distance,self.static_distance, self.detect_distance)
        tasmota.web_send_decimal(msg)
      end
    
      #- add sensor value to teleperiod -#
      def json_append()
        if self.moving_distance == nil return nil end
        import string
        var msg = string.format(",\"LD2412\":{\"distance\":[%i,%i,%i],\"energy\":[%i,%i]}",
        self.moving_distance, self.static_distance, self.detect_distance, self.moving_energy,self.static_energy)
        tasmota.response_append(msg)
      end
end

var ld2412 = LD2412("1D734F47B7F2") # MAC of the device
tasmota.add_driver(ld2412)

tasmota.add_cmd('LD2412Duration',/c,i,p,j->ld2412.cmndDuration(c,i,p,j))
tasmota.add_cmd('LD2412MovingSens',/c,i,p,j->ld2412.cmndMovingSens(c,i,p,j))
tasmota.add_cmd('LD2412StaticSens',/c,i,p,j->ld2412.cmndStaticSens(c,i,p,j))
tasmota.add_cmd('LD2412EngMode',/c,i,p,j->ld2412.cmndEngMode(c,i,p,j))
