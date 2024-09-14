#-
  LF24xx.be - HLK-LD24 family 24GHz smart wave motion sensor support for Tasmota via serial and Berry
  port of xsns_102_ld2410.ino from Theo Arends
  SPDX-FileCopyrightText: 2024 Christian Baars
  SPDX-License-Identifier: GPL-3.0-only
-#

class LD2410
    static MAX_GATES                 = 8       # 0 to 8 (= 9) - DO NOT CHANGE

    var moving_distance
    var moving_energy
    var static_distance
    var static_energy
    var detect_distance
    var moving_sensitivity
    var static_sensitivity
    var sensitivity_counter

    def init(major,minor,patch)
        log(f"LD2: found LD2410 {major}.{minor}.{patch}")
    end

    def handleTRG(buf)
        #  0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 18 19 20
        # F4 F3 F2 F1 0B 00 02 AA 00 00 00 00 00 00 37 55 00 F8 F7 F6 F5 - No target
        # F4 F3 F2 F1 0B 00 02 AA 03 46 00 34 00 00 3C 55 00 F8 F7 F6 F5 - Movement and Stationary target
        # F4 F3 F2 F1 0B 00 02 AA 02 54 00 00 00 00 64 55 00 F8 F7 F6 F5 - Stationary target
        # header     |len  |dt|hd|st|movin|me|stati|se|tr|ck|trailer
        # if self.buf[9] != 0
            if buf[6] == 2
                if buf[8] != 0
                    self.moving_distance = buf.get(9,2)
                    self.moving_energy = buf[11];
                    self.static_distance = buf.get(12,2)
                    self.static_energy = buf[14];
                    self.detect_distance = self.buf.get(15,2)
                end
                # self.detect_distance = self.buf.get(16,2)
            elif buf[6] == 1
                log("LD412: engineering mode")
                print(buf)
        #  0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 .. 25 26 27 28 29 30 .. 39 46 47 48 49 50
        # F4 F3 F2 F1 29 00 01 AA 02 00 00 00 00 00 00 .. 00 0D 0D 00 03 02 .. 00 55 00 F8 F7 F6 F5
        #len header     |len  |dt|hd|mm|md|mov distgate 0 .. n |mov dist gate 0 .. n|tr|ck|trailer
            end
        # else
        #     # print(self.buf[1..self.buf[0]])
        # end
    end

    def handleSimple(buf)
        return
    end

    #- display sensor value in the web UI -#
    def show_web()
        if self.moving_distance == nil return nil end
        import string
        var msg = string.format(
                    "{s}LD2410 moving distance{m}%u cm{e}"..
                    "{s}LD2410 static distance{m}%u cm{e}"..
                    "{s}LD2410 detect distance{m}%u cm{e}",
                    self.moving_distance,self.static_distance, self.detect_distance)
        tasmota.web_send_decimal(msg)
    end

    #- add sensor value to teleperiod -#
    def show_json()
        if self.moving_distance == nil return nil end
        import string
        var msg = string.format(",\"LD2410\":{\"distance\":[%i,%i,%i],\"energy\":[%i,%i]}",
        self.moving_distance, self.static_distance, self.detect_distance, self.moving_energy,self.static_energy)
        tasmota.response_append(msg)
    end
end

class LD2412
    static MAX_GATES = 13       # 0 to 13 (= 14) - DO NOT CHANGE

    var moving_distance
    var moving_energy
    var static_distance
    var static_energy
    var detect_distance
    var moving_sensitivity
    var static_sensitivity
    var sensitivity_counter

    var mode
    var max_mov_gate
    var max_stat_gate
    var mov_gate_energies
    var stat_gate_energies
    var light

    def init(major,minor,patch)
        log(f"LD2: found LD2412 {major}.{minor}.{patch}")
    end

    def handleTRG(buf)
        #  0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 18 19 20
        # F4 F3 F2 F1 0B 00 02 AA 00 00 00 00 00 00 37 55 00 F8 F7 F6 F5 - No target
        # F4 F3 F2 F1 0B 00 02 AA 03 46 00 34 00 00 3C 55 00 F8 F7 F6 F5 - Movement and Stationary target
        # F4 F3 F2 F1 0B 00 02 AA 02 54 00 00 00 00 64 55 00 F8 F7 F6 F5 - Stationary target
        # header     |len  |dt|hd|st|movin|me|stati|se|tr|ck|trailer
        # if self.buf[9] != 0
            if buf[6] == 2
                if buf[8] & 1
                    self.moving_distance = buf.get(9,2)
                    self.moving_energy = buf[11]
                    self.mode = 1 # standard mode
                end
                if buf[8] & 2
                    self.static_distance = buf.get(12,2)
                    self.static_energy = buf[14]
                    self.mode = 1 # standard mode
                end
            elif buf[6] == 1
                self.mode = 2 # engineering mode
        #  0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 .. 25 26 27 28 29 30 .. 39 46 47 48 49 50
        # F4 F3 F2 F1 2b 00 01 AA 02 00 00 00 00 00 00 .. 00 0D 0D 00 03 02 .. 00 55 00 F8 F7 F6 F5
        #len header  |len  |dt|hd|mm|ms|mov distgate 0 .. n |mov dist gate 0 .. n|tr|ck|trailer
                self.max_mov_gate = buf[8]
                self.max_stat_gate = buf[9]
                self.mov_gate_energies = buf[10..23]
                self.stat_gate_energies = buf[24..37]
                if buf[4] > 0x29
                    self.light = buf[38]
                end
                # log("LD412: engineering mode")
                # print(buf)
            end
        # else
        #     # print(self.buf[1..self.buf[0]])
        # end
    end

    def handleSimple(buf)
        return
    end

    
    #- display sensor value in the web UI -#
    def show_web()
        if self.mode == nil return nil end
        import string
        var msg
        if self.mode == 1
            msg = string.format(
                    "{s}LD2412 moving distance{m}%u cm{e}"..
                    "{s}LD2412 static distance{m}%u cm{e}",
                    self.moving_distance,self.static_distance)
        elif self.mode == 2
            msg = string.format(
                "{s}LD2412 max moving gate{m}%u{e}"..
                "{s}LD2412 max static gate{m}%u{e}",
                self.max_mov_gate, self.max_stat_gate)
            if self.light != nil
                msg += f"{{s}}LD2412 light{{m}}{self.light} lx{{e}}"
            end
            var i = 0
            while i < self.MAX_GATES + 1
                var energy = self.mov_gate_energies[i]
                msg += f"{{s}}LD2412 moving gate {i}{{m}}{energy}{{e}}"
                i += 1
            end
            i = 0
            while i < self.MAX_GATES + 1
                var energy = self.stat_gate_energies[i]
                msg += f"{{s}}LD2412 stat gate {i}{{m}}{energy}{{e}}"
                i += 1
            end
        end
        tasmota.web_send_decimal(msg)
    end

    #- add sensor value to teleperiod -#
    def show_json()
        if self.mode == nil return nil end
        import string
        var msg
        if self.mode == 1
            msg = string.format(",\"LD2412\":{\"distance\":[%i,%i],\"energy\":[%i,%i]}",
            self.moving_distance, self.static_distance, self.moving_energy,self.static_energy)
        end
        tasmota.response_append(msg)
    end

end

class LD2420
    static MAX_GATES = 16       # 0 to 15


    var moving_distance
    var moving_energy
    var static_distance
    var static_energy
    var detect_distance
    var moving_sensitivity
    var static_sensitivity
    var sensitivity_counter

    var mode # 0 - simple, 1 - engineering, 2 - TRG
    var pin # string
    var presence # int
    var range
    var gates


    def init(sender,major,minor,patch)
        log(f"LD2: found LD2420 {major}.{minor}.{patch}")
        sender.cmnd_chain = [/->sender.sendCMD(sender.CMND_SET_SYSTEM_PARAM,bytes("000004000000")),/->sender.setCfgMode(false)]
        self.gates = bytes(32)
    end

    def handleTRG(buf)
        #  0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 ...40     41 42 43 44
        # F4 F3 F2 F1 23 00 01 00 00 00 00 00 00 00 37 55 ...     F8 F7 F6 F5 - No target
        # header     |len  |pr |range|gate enrgies as uint16|trailer
        if buf[4] == 0x23 # expected size  (tested with fw 1.5.9)
            self.mode = 2
            self.presence = buf[6]
            self.range = buf.get(7,2)
            self.gates= buf[9..40]
        else
            print(size(buf),buf)
        end
    end

    def handleSimple(buf)
        import string
        var s = buf.asstring()
        var c = string.split(s,"\r\n")
        self.pin = c[0]
        var r = string.split(c[1]," ")
        self.range = int(r[1])
        self.mode = 0
    end

    #- display sensor value in the web UI -#
    def show_web()
        if self.mode == nil return nil end
        var msg
        import string
        if self.mode == 0
            msg = string.format(
                        "{s}LD2420 pin{m}%s{e}"..
                        "{s}LD2420 range{m}%u cm{e}",
                        self.pin,self.range)      
        elif self.mode == 1
        elif self.mode == 2
            msg = string.format(
                        "{s}LD2420 presence{m}%u{e}"..
                        "{s}LD2420 range{m}%u cm{e}",
                        self.presence,self.range)
            var i = 0
            while i < self.MAX_GATES
                var energy = self.gates.get(i*2,2)
                msg += f"{{s}}LD2420 gate {i}{{m}}{energy}{{e}}"
                i += 1
            end
        end
        tasmota.web_send_decimal(msg)
    end

    #- add sensor value to teleperiod -#
    def show_json()
        if self.mode == nil return nil end
        var msg
        import string
        if self.mode == 0
            msg = string.format(",\"LD2420\":{\"pin\":\"%s\",\"range\":%i}",
                self.pin, self.range)   
        elif self.mode == 1
        elif self.mode == 2
            var gate_energies = "["
            var i = 0
            while i < self.MAX_GATES - 1
                var energy = self.gates.get(i*2,2)
                gate_energies += f"{energy},"
                i += 1
            end
            var energy = self.gates.get((i*2)+2,2)
            gate_energies += f"{energy}]"
            msg = string.format(",\"LD2420\":{\"presence\":%i,\"range\":%i,\"gates\":%s}",
                self.presence, self.range, gate_energies)
        end
        tasmota.response_append(msg)
    end
end

class LD2 : Driver
    var buf
    var ser, sensor, MAC
    var cmnd_chain, timeout

    static CMND_START_CONFIGURATION  = 0xFF
    static CMND_END_CONFIGURATION    = 0xFE
    static CMND_READ_VERSION         = 0x00
    static CMND_READ_SERIAL_NUM      = 0x11
    static CMND_SET_SYSTEM_PARAM     = 0x12

    static CMND_SET_DISTANCE         = 0x60
    static CMND_READ_PARAMETERS      = 0x61
    static CMND_START_ENGINEERING    = 0x62
    static CMND_END_ENGINEERING      = 0x63
    static CMND_SET_SENSITIVITY      = 0x64

    static CMND_GET_FIRMWARE         = 0xA0
    static CMND_SET_BAUDRATE         = 0xA1
    static CMND_FACTORY_RESET        = 0xA2
    static CMND_REBOOT               = 0xA3
    static CMND_GET_MAC              = 0xA5
    static CMND_SET_DIST_RES         = 0xAA
    static CMND_GET_DIST_RES         = 0xAB

    static config_header = bytes("FDFCFBFA")
    static config_footer = bytes("04030201")
    static target_header = bytes("F4F3F2F1")
    static target_footer = bytes("F8F7F6F5")
    static simple_on_header = bytes("4F4E0D0A") # bytes().fromstring("ON")
    static simple_off_header = bytes("4F46460D0A") # bytes().fromstring("OFF")

    def init(rx,tx,baud)
        log("LD2: start LD24xx driver")
        self.ser = serial(rx,tx,baud)
        self.buf = bytes(64)
        self.ser.read() # read to /dev/null
        self.cmnd_chain = [/->self.getFW(),/->self.getVersion(),/->self.getMAC(),/->self.setCfgMode(false)]
        self.setCfgMode(true)
    end

    def init_sensor(sensor_type, major, minor, patch)
        if sensor_type == 2410
            self.sensor = LD2410(major,minor,patch)
        elif sensor_type == 2412
            self.sensor = LD2412(major,minor,patch)
        elif sensor_type == 2420
            self.sensor = LD2420(self, major,minor,patch)
        else
            log("LD2: ERROR - unknown sensor!!")
            return
        end
    end

    # common commands for the LD24xx family

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
        self.ser.write(cmd_buf)
        print(cmd_buf)
    end


    def getVersion()
        self.timeout = 2 # seconds
        self.sendCMD(self.CMND_READ_VERSION)
        log("LD2: Request Version, try to identify sensor type")
    end

    def getFW()
        self.timeout = 2 # seconds
        self.sendCMD(self.CMND_GET_FIRMWARE)
        log("LD2: Request FW, try to identify sensor type")
    end

    def getMAC()
        self.timeout = 2 # seconds
        self.sendCMD(self.CMND_GET_MAC,bytes("0100"))
        log("LD2: Request MAC")
    end

    def factoryReset()
        self.sendCMD(self.CMND_FACTORY_RESET)
        log("LD2: Factory reset")
    end

    def setCfgMode(on)
        if on == true
            self.sendCMD(self.CMND_START_CONFIGURATION,bytes("0100"))
            log("LD2: Start config mode",3)
        else
            self.sendCMD(self.CMND_END_CONFIGURATION)
            log("LD2: Stop config mode",3)
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
        self.timeout = 2 # seconds
    end

    def setDistRes(res)
        var payload = bytes("0000")
        payload[0] = res
        self.sendCMD(self.CMND_SET_DIST_RES,payload)
        self.timeout = 2 # seconds
    end

    def setMaxDistAndNoOneDur(max_mov_dist_range, max_stat_dist_range, no_one_duration)
        var val = bytes(-18)
        val[2] = max_mov_dist_range
        val[6] = 1
        val[8] = max_stat_dist_range
        val[12] = 2
        val.set(14,no_one_duration,-2) #big-endian
        self.sendCMD(self.CMND_SET_DISTANCE,val)
        self.timeout = 2 # seconds
    end

    def settGateSensitivity(gate, moving_sensitivity, static_sensitivity)
        var val = bytes(-18)
        val[2] = gate
        val[6] = 1
        val[8] = moving_sensitivity
        val[12] = 2
        val[14] = static_sensitivity
        self.sendCMD(self.CMND_SET_SENSITIVITY,val)
        self.timeout = 2 # seconds
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
        self.timeout = 2 # seconds
    end

    # driver loop and helper functions

    def clean_buffer()
        # clean by shifting everything after a valid footer to the left
        var i = 0
        var sz = size(self.buf)

        while i < sz
            if self.buf[i] != 0x04 && self.buf[i] != 0xf8
                i += 1
                continue
            end
            if sz > i + 3
                if self.buf[i..i+3] == self.config_footer || self.buf[i..i+3] == self.target_footer
                    self.buf = self.buf[i+4..]
                    return
                end
            end
            i += 1
        end
        if i == sz # garbage or fully intact
            self.buf.clear()
        else
        end
    end

    def next_cmnd()
        if size(self.cmnd_chain) > 0
            var function = self.cmnd_chain[0]
            function()
            if size(self.cmnd_chain) > 1
                self.cmnd_chain = self.cmnd_chain[1..]
            else
                self.cmnd_chain = []
                self.timeout = nil
            end
        end
    end

    # read loop
    def every_50ms()
        if self.ser != nil
            self.buf..self.ser.read()
            if size(self.buf) > 11 # shortest possible packet is 12
                self.handle_read()
            end
        end
        self.clean_buffer()
    end

    def every_second()
        if self.timeout != nil
            if self.timeout > 0
                self.timeout -= 1
            else
                log("LD2: timeout ... proceed with next command")
                self.timeout = nil
                self.next_cmnd()
            end
        end
    end

    # handler and parser
    def parseVersion()
        #  0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 18 19 20 21 22
        # FD FC FB FA 0D 00 00 01 00 00 07 00 76 31 2E 34 2E 31 34 04 03 02 01
        # header     |len  |ty|hd|ack  |length|string              |trailer
        #            |   13|  | 1|    0|  7   |v1.4.14             |
        var s = self.buf[13..12+self.buf[10]].asstring()
        import string
        var fw = string.split(s,".")
        var major = int(fw[0])
        var minor = int(fw[1])
        var patch = int(fw[2])
        # var s  = string.format("LD2: Sensor version V%d.%02d.%02d%02d%02d%02d",self.buf[13],self.buf[12],self.buf[17],self.buf[16],self.buf[15],self.buf[14])
        # log(s)
        if self.sensor == nil
            self.init_sensor(2420, major, minor, patch)  # maybe there are more sensors that do not respond to getFW()
        end
    end

    def parseFW()
        #  0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 18 19 20 21
        # FD FC FB FA 0C 00 A0 01 00 00 00 01 07 01 16 15 09 22 04 03 02 01
        # header     |len  |ty|hd|ack  |ftype|major|minor      |trailer
        #            |   12|  | 1|    0|  256|  1.7|   22091516|
        var ftype = self.buf.get(10,2)
        var major = self.buf.get(13,1)
        var minor = self.buf.get(12,1)
        var patch = self.buf.get(14,2)
        import string
        var s  = string.format("LD2: Firmware version V%d.%02d.%02d%02d%02d%02d",self.buf[13],self.buf[12],self.buf[17],self.buf[16],self.buf[15],self.buf[14])
        # log(s)
        log(f"LD2: FW type {ftype:x}")
        if ftype == 256
            self.init_sensor(2410, major, minor, patch)
        elif ftype == 0x2412
            self.init_sensor(2412, major, minor, patch)
        end
    end

    def handleCFG()
        #  0  1  2  3  4  5  6  7  8  9  10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37
        #  FD FC FB FA 1C 00 61 01 00 00 AA 08 08 08 32 32 28 1E 14 0F 0F 0F 0F 00 00 28 28 1E 1E 14 14 14 05 00 04 03 02 01 - Default
        var cmd = self.buf[6]
        var ack = self.buf[7] == 1
        if cmd == self.CMND_READ_PARAMETERS
            print("LD2: moving_distance_gate",self.buf[12],"static_distance_gate",self.buf[13],"no one duration",self.buf.get(32,-2))
            for i:0..self.sensor.MAX_GATES
                print("LD2: moving sens",i, self.buf[14+i], "static sens",i, self.buf[23+i])
            end
        elif cmd == self.CMND_START_CONFIGURATION || cmd == self.CMND_END_CONFIGURATION
            # do nothing
        elif cmd == self.CMND_READ_VERSION
            self.parseVersion()
        elif cmd == self.CMND_GET_FIRMWARE
            self.parseFW()
        elif cmd == self.CMND_GET_MAC
            if ack
                self.MAC = self.buf[10..15].tohex()
                log(f"LD2: has MAC {self.MAC}")
            else
                log("LD2: did not get MAC")
            end
        else
            print(self.buf)
        end
        if ack == true
            log("LD2: Sensor ACK",3)
            self.next_cmnd()
        else
            log("LD2: Sensor NACK !!!",2)
        end
    end

    def handle_read()
        if self.buf[0] == 0xfd
            self.handleCFG()
        elif self.buf[0] == 0xf4
            if self.sensor != nil
                self.sensor.handleTRG(self.buf)
            end
        elif self.buf[0] == 0x4f
            if self.sensor != nil
                self.sensor.handleSimple(self.buf)
            end
        else
            print(self.buf)
            self.buf = self.buf[1..] # 
        end
    end

    def serviceSensitivities()
        if self.sensitivity_counter < 0
            self.setCfgMode(false)
            log("LD2: Did set sensitivities",2)
        else
            self.settGateSensitivity(self.sensitivity_counter,self.moving_sensitivity[self.sensitivity_counter],self.static_sensitivity[self.sensitivity_counter])
            self.sensitivity_counter -= 1
            print("LD2:",self.sensitivity_counter + 1,"steps left")
        end
    end

    #- console commands -#
    def cmndDuration(cmd, idx, payload, payload_json)
        var pl = int(payload)
        self.setCfgMode(true)
        if pl == 0
            self.factoryReset()
        else
            self.setMaxDistAndNoOneDur(8, 8, pl)
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
        self.sensitivity_counter = self.sensor.MAX_GATES
        self.setCfgMode(true)
        self.serviceSensitivities()
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
        self.sensitivity_counter = self.sensor.MAX_GATES
        self.setCfgMode(true)
        self.serviceSensitivities()
        tasmota.resp_cmnd({"StaticSens":pl})
    end

    def cmndEngMode(cmd, idx, payload, payload_json)
        var pl = int(payload) > 0
        self.setCfgMode(true)
        self.cmnd_chain.push(/->self.setEngMode(pl))
        tasmota.resp_cmnd({"Engineering mode":payload})
        self.cmnd_chain.push(/->self.setCfgMode(false))
    end

    def cmndDistRes(cmd, idx, payload, payload_json)
        var pl = int(payload)
        self.setCfgMode(true)
        self.cmnd_chain.push(/->self.setDistRes(pl))
        tasmota.resp_cmnd({"Distance resolution":payload})
        self.cmnd_chain.push(/->self.setCfgMode(false))
    end

    #- display sensor value in the web UI -#
    def web_sensor()
        if self.sensor != nil
            self.sensor.show_web()
        end
    end

    #- add sensor value to teleperiod -#
    def json_append()
        if self.sensor != nil
            self.sensor.show_json()
        end
    end
end

var ld2 = LD2(3,4,115200) # or 256000 baud
tasmota.add_driver(ld2)

tasmota.add_cmd('LD2Duration',/c,i,p,j->ld2.cmndDuration(c,i,p,j))
tasmota.add_cmd('LD2MovingSens',/c,i,p,j->ld2.cmndMovingSens(c,i,p,j))
tasmota.add_cmd('LD2StaticSens',/c,i,p,j->ld2.cmndStaticSens(c,i,p,j))
tasmota.add_cmd('LD2EngMode',/c,i,p,j->ld2.cmndEngMode(c,i,p,j))
tasmota.add_cmd('LD2DistRes',/c,i,p,j->ld2.cmndDistRes(c,i,p,j))
