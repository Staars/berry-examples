#-
  Comet Blue Bluetooth Thermostat Driver for Tasmota
  SPDX-License-Identifier: GPL-3.0-only
-#

class CometBlue : Driver
    var buf
    var current_func, next_func
    var mac_address
    var pin_code
    var is_connected
    
    # Service UUID
    static SERVICE = "47e9ee00-47e9-11e4-8939-164230d1df67"
    
    # Characteristic UUIDs
    static UUID_DATETIME = "ee01"
    static UUID_MONDAY = "ee10"
    static UUID_TUESDAY = "ee11"
    static UUID_WEDNESDAY = "ee12"
    static UUID_THURSDAY = "ee13"
    static UUID_FRIDAY = "ee14"
    static UUID_SATURDAY = "ee15"
    static UUID_SUNDAY = "ee16"
    static UUID_HOLIDAY_1 = "ee20"
    static UUID_HOLIDAY_2 = "ee21"
    static UUID_HOLIDAY_3 = "ee22"
    static UUID_HOLIDAY_4 = "ee23"
    static UUID_HOLIDAY_5 = "ee24"
    static UUID_HOLIDAY_6 = "ee25"
    static UUID_HOLIDAY_7 = "ee26"
    static UUID_HOLIDAY_8 = "ee27"
    static UUID_SETTINGS = "ee2a"
    static UUID_TEMPERATURE = "ee2b"
    static UUID_BATTERY = "ee2c"
    static UUID_FW_VERSION = "ee2d"
    static UUID_LCD_TIMEOUT = "ee2e"
    static UUID_PIN = "ee30"

    
    static UNCHANGED_VALUE = 0x80
    
    # Temperature data
    var current_temperature
    var target_temp_low
    var target_temp_high
    var manual_temp
    var offset_temp
    var window_open_detection
    var window_open_minutes
    
    # Other data
    var battery_level
    var status_flags
    var authenticated

    def init(MAC, pin)
        import BLE
        self.buf = bytes(-64)
        var cbp = tasmota.gen_cb(/e,o,u,h->self.cb(e,o,u,h))
        
        self.mac_address = MAC
        self.pin_code = pin
        self.authenticated = false
        self.is_connected = false
        self.current_func = /->self.wait()
        
        BLE.conn_cb(cbp, self.buf)
        BLE.set_MAC(bytes(MAC), 0)
        BLE.set_svc(self.SERVICE)
        
        print("CB: Initialized for MAC:", MAC)
        # Don't connect yet - wait for first command
    end

    def connect()
        import BLE
        if self.is_connected
            print("CB: Already connected")
            return
        end
        
        print("CB: Connecting...")
        BLE.set_chr(self.fullUUID(self.UUID_PIN))
        
        # Prepare PIN in little-endian format
        var pin_bytes = bytes(-4)
        var pin_val = self.pin_code
        for i: 0..3
            pin_bytes[i] = pin_val & 0xFF  # Little-endian!
            pin_val = pin_val >> 8
        end
        
        self.buf.setbytes(1, pin_bytes)
        self.buf[0] = 4
        BLE.run(2, true)  # Connect and write PIN
        print("CB: Sent PIN:", pin_bytes)
    end
    
    def disconnect()
        import BLE
        if !self.is_connected
            return
        end
        
        BLE.run(5)  # Disconnect
        self.then(/->self.wait())
    end

    def fullUUID(uuid16)
        return f"47e9{uuid16}-47e9-11e4-8939-164230d1df67"
    end

    def sendBLE(uuid, data)
        import BLE
        self.buf.setbytes(1, data)
        self.buf[0] = size(data)
        BLE.set_chr(uuid)
        BLE.run(2, true)  # Write operation
        print("CB: Write to UUID", uuid, "data:", data)
    end
    
    def readBLE(uuid)
        import BLE
        BLE.set_chr(uuid)
        BLE.run(1)  # Read operation
        print("CB: Read from UUID", uuid)
    end

    def readTemperature()
        self.readBLE(self.fullUUID(self.UUID_TEMPERATURE))
        self.then(/->self.wait())
    end
    
    def readBattery()
        self.readBLE(self.fullUUID(self.UUID_BATTERY))
        self.then(/->self.wait())
    end

    def readStatus()
        self.readBLE(self.fullUUID(self.UUID_SETTINGS))
        self.then(/->self.wait())
    end

    def readLCDTimeout()
        self.readBLE(self.fullUUID(self.UUID_LCD_TIMEOUT))
        self.then(/->self.wait())
    end

    def parseTemperature()
        if self.buf[0] >= 7
            # Format: current | manual | target_low | target_high | offset | window_detect | window_minutes
            self.current_temperature = self.buf[1] / 2.0
            self.manual_temp = self.buf[2] / 2.0
            self.target_temp_low = self.buf[3] / 2.0
            self.target_temp_high = self.buf[4] / 2.0
            self.offset_temp = self.buf[5] / 2.0
            self.window_open_detection = self.buf[6]
            self.window_open_minutes = self.buf[7]
            
            self.authenticated = true
            
            print("CB: Current:", self.current_temperature, "°C")
            print("CB: Manual:", self.manual_temp, "°C")
            print("CB: Target Low:", self.target_temp_low, "°C")
            print("CB: Target High:", self.target_temp_high, "°C")
            print("CB: Offset:", self.offset_temp, "°C")
        else
            print("CB: Temperature data too short:", self.buf[0], "bytes")
        end
        self.disconnect()
    end
    
    def parseBattery()
        if self.buf[0] >= 1
            self.battery_level = self.buf[1]# * 100 / 255
            print("CB: Battery:", self.battery_level, "%") # not sure, if correct
        end
        self.disconnect()
    end

    def parseStatus()
        if self.buf[0] >= 3
            # Status is 3 bytes (24 bits)
            self.status_flags = (self.buf[3] << 16) | (self.buf[2] << 8) | self.buf[1]
            
            # Decode status flags
            var childlock = (self.status_flags & 0x80) != 0
            var manual_mode = (self.status_flags & 0x1) != 0
            var motor_moving = (self.status_flags & 0x100) != 0
            var antifrost = (self.status_flags & 0x10) != 0
            var low_battery = (self.status_flags & 0x800) != 0
            var satisfied = (self.status_flags & 0x80000) != 0
            
            print("CB: Status - Manual:", manual_mode, "Motor:", motor_moving)
            print("CB: Status - LowBat:", low_battery, "ChildLock:", childlock)
            print("CB: Status - AntiFrost:", antifrost, "Satisfied:", satisfied)
        end
        self.disconnect()
    end

    def parseLCDTimeout()
        if self.buf[0] >= 2
            var default_timeout = self.buf[1]
            var current_timeout = self.buf[2]
            print("CB: LCD timeout:", current_timeout, "sec (default:", default_timeout, ")")
        end
        self.disconnect()
    end

    def setTemperature(temp_low, temp_high)
        var temp_low_byte = int(temp_low * 2)
        var temp_high_byte = int(temp_high * 2)
        
        # Format: current(128) | manual(128) | target_low | target_high | offset(0) | window_det(128) | window_min(128)
        var temp_data = bytes(-7)
        temp_data[0] = 128  # Current temp - unchanged (set by device)
        temp_data[1] = 128  # Manual temp - unchanged
        temp_data[2] = temp_low_byte
        temp_data[3] = temp_high_byte
        temp_data[4] = 0x00  # Offset unchanged
        temp_data[5] = 128  # Window detection - unchanged
        temp_data[6] = 128  # Window minutes - unchanged
        
        self.sendBLE(self.fullUUID(self.UUID_TEMPERATURE), temp_data)
        print("CB: Set temp range:", temp_low, "-", temp_high, "°C")
        self.then(/->self.disconnect())
    end
    
    def setManualTemperature(temp)
        var temp_byte = int(temp * 2)
        
        # Format: current(128) | manual | target_low(128) | target_high(128) | offset(0) | window_det(128) | window_min(128)
        var temp_data = bytes(-7)
        temp_data[0] = 128  # Current temp - unchanged (set by device)
        temp_data[1] = temp_byte  # Manual temperature - THIS is what we set
        temp_data[2] = 128  # Target low - unchanged
        temp_data[3] = 128  # Target high - unchanged
        temp_data[4] = 0x00  # Offset unchanged
        temp_data[5] = 128  # Window detection - unchanged
        temp_data[6] = 128  # Window minutes - unchanged
        
        self.sendBLE(self.fullUUID(self.UUID_TEMPERATURE), temp_data)
        print("CB: Set manual temp:", temp, "°C")
        self.then(/->self.disconnect())
    end

    def setLCDTimeout(timeout_seconds)
        var lcd_data = bytes(-2)
        lcd_data[0] = timeout_seconds & 0xFF  # Set both to same value
        lcd_data[1] = timeout_seconds & 0xFF
        
        self.sendBLE(self.fullUUID(self.UUID_LCD_TIMEOUT), lcd_data)
        print("CB: Set LCD timeout:", timeout_seconds, "sec")
        self.then(/->self.disconnect())
    end

    # Promise-like async handling
    def wait()
        # Placeholder - do nothing
    end

    def then(func)
        self.next_func = func
        self.current_func = self.wait
    end

    def every_100ms()
        self.current_func()
    end

    # BLE callback handler
    def cb(error, op, uuid, handle)
        if op == 5  # Disconnect completed
            print("CB: Disconnect OK")
            self.is_connected = false
            return
        end
        if error != 0
            print("CB: BLE Error:", error, "op:", op)
            return
        end
        self.is_connected = true # might be reverted on op == 5
        # Operation codes:
        # 1 = Read completed
        # 2 = Write completed
        # 3 = Subscribe completed
        # 5 = Disconnect completed
        # 103 = Notification received
        
        if op == 1  # Read completed
            print(f"CB: Read OK, handle:{handle}, uuid: {uuid:x}, len: {self.buf[0]}")
            
            # Parse based on handle found by trial-and-erro
            if handle == 61
                self.parseTemperature()
            elif handle == 63
                self.parseBattery()
            elif handle == 59
                self.parseStatus()
            elif handle == 69
                self.parseLCDTimeout()
            else
                print("CB: Unknown handle, raw data:", self.buf[1..self.buf[0]])
            end
            
        elif op == 2  # Write completed
            print("CB: Write OK")
        elif op == 103  # Notification
            print("CB: Notification from UUID:", uuid)
        else
            print(error, op, uuid, handle)
        end
        
        # Call next function in chain
        self.current_func = self.next_func
    end

    # Console Commands
    def cmndConnect(cmd, idx, payload, payload_json)
        self.connect()
        self.then(/->self.readTemperature())
        tasmota.resp_cmnd({"Status": "Connecting"})
    end

    def cmndTemp(cmd, idx, payload, payload_json)
        var temp = real(payload)
        if temp >= 8.0 && temp <= 28.0
            self.connect()
            self.then(/->self.setManualTemperature(temp))
            tasmota.resp_cmnd({"Temperature": temp})
        else
            tasmota.resp_cmnd({"Error": "Temperature must be between 8 and 28°C"})
        end
    end
    
    def cmndTempRange(cmd, idx, payload, payload_json)
        import string
        var temps = string.split(payload, ",")
        if size(temps) == 2
            var temp_low = real(temps[0])
            var temp_high = real(temps[1])
            if temp_low >= 8.0 && temp_high <= 28.0 && temp_low < temp_high
                self.connect()
                self.then(/->self.setTemperature(temp_low, temp_high))
                tasmota.resp_cmnd({"TempLow": temp_low, "TempHigh": temp_high})
            else
                tasmota.resp_cmnd({"Error": "Invalid temperature range"})
            end
        else
            tasmota.resp_cmnd({"Error": "Use format: low,high (e.g., 18,22)"})
        end
    end
    
    def cmndRead(cmd, idx, payload, payload_json)
        self.connect()
        self.then(/->self.readTemperature())
        tasmota.resp_cmnd({"Status": "Reading temperature"})
    end
    
    def cmndBattery(cmd, idx, payload, payload_json)
        self.connect()
        self.then(/->self.readBattery())
        tasmota.resp_cmnd({"Status": "Reading battery"})
    end

    def cmndStatus(cmd, idx, payload, payload_json)
        self.connect()
        self.then(/->self.readStatus())
        tasmota.resp_cmnd({"Status": "Reading device status"})
    end

    def cmndLCD(cmd, idx, payload, payload_json)
        var timeout = int(payload)
        if timeout >= 0 && timeout <= 255
            self.connect()
            self.then(/->self.setLCDTimeout(timeout))
            tasmota.resp_cmnd({"LCDTimeout": timeout})
        else
            tasmota.resp_cmnd({"Error": "Timeout must be 0-255 seconds"})
        end
    end

    def cmndDisconnect(cmd, idx, payload, payload_json)
        self.disconnect()
        tasmota.resp_cmnd({"Status": "Disconnected"})
    end

    # Web UI Display
    def web_sensor()
        if self.current_temperature == nil return nil end
        import string
        var msg = string.format(
                 "{s}Comet Blue Current{m}%.1f °C{e}"..
                 "{s}Comet Blue Target Low{m}%.1f °C{e}"..
                 "{s}Comet Blue Target High{m}%.1f °C{e}",
                 self.current_temperature, self.target_temp_low, self.target_temp_high)
        if self.battery_level != nil
            msg = msg .. string.format("{s}Comet Blue Battery{m}%d %%{e}", self.battery_level)
        end
        tasmota.web_send_decimal(msg)
    end
    
    # Telemetry JSON
    def json_append()
        if self.current_temperature == nil return nil end
        import string
        var msg = string.format(",\"CometBlue\":{\"CurrentTemp\":%.1f,\"TargetLow\":%.1f,\"TargetHigh\":%.1f,\"ManualTemp\":%.1f,\"Offset\":%.1f}",
            self.current_temperature, self.target_temp_low, self.target_temp_high, self.manual_temp, self.offset_temp)
        if self.battery_level != nil
            msg = msg .. string.format(",\"Battery\":%d", self.battery_level)
        end
        tasmota.response_append(msg)
    end
end

# Initialize with MAC address and PIN
# Replace with your thermostat's MAC address and PIN
var comet = CometBlue("D4CA6AA73704", 000000)
tasmota.add_driver(comet)

# Register console commands
tasmota.add_cmd('CBConnect', /c,i,p,j->comet.cmndConnect(c,i,p,j))
tasmota.add_cmd('CBTemp', /c,i,p,j->comet.cmndTemp(c,i,p,j))
tasmota.add_cmd('CBTempRange', /c,i,p,j->comet.cmndTempRange(c,i,p,j))
tasmota.add_cmd('CBRead', /c,i,p,j->comet.cmndRead(c,i,p,j))
tasmota.add_cmd('CBBattery', /c,i,p,j->comet.cmndBattery(c,i,p,j))
tasmota.add_cmd('CBStatus', /c,i,p,j->comet.cmndStatus(c,i,p,j))
tasmota.add_cmd('CBLCD', /c,i,p,j->comet.cmndLCD(c,i,p,j))
tasmota.add_cmd('CBDisconnect', /c,i,p,j->comet.cmndDisconnect(c,i,p,j))
