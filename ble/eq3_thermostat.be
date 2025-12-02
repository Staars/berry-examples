#-
  EQ3 BT Smart Bluetooth Thermostat Driver for Tasmota
  Based on python-eq3bt protocol
  SPDX-License-Identifier: GPL-3.0-only
-#

class EQ3BTSmart : Driver
    var buf
    var current_func, next_func
    var mac_address
    var is_connected
    
    # Service UUID (vendor specific)
    static SERVICE = "3e135142-654f-9090-134a-a6ff5bb77046"
    
    # Characteristic UUIDs (write and notify)
    static CHAR_WRITE = "3fa4585a-ce4a-3bad-db4b-b8df8179ea09"
    static CHAR_NOTIFY = "d0e8434d-cd29-0996-af41-6c90f4e0eb2a"
    
    # Command IDs
    static PROP_ID_QUERY = 0x00
    static PROP_ID_RETURN = 0x01
    static PROP_INFO_QUERY = 0x03
    static PROP_INFO_RETURN = 0x02
    static PROP_COMFORT_ECO_CONFIG = 0x11
    static PROP_OFFSET = 0x13
    static PROP_WINDOW_OPEN_CONFIG = 0x14
    static PROP_SCHEDULE_QUERY = 0x20
    static PROP_SCHEDULE_RETURN = 0x21
    static PROP_MODE_WRITE = 0x40
    static PROP_TEMPERATURE_WRITE = 0x41
    static PROP_COMFORT = 0x43
    static PROP_ECO = 0x44
    static PROP_BOOST = 0x45
    static PROP_LOCK = 0x80
    
    # Temperature constants
    static EQ3BT_AWAY_TEMP = 12.0
    static EQ3BT_MIN_TEMP = 5.0
    static EQ3BT_MAX_TEMP = 29.5
    static EQ3BT_OFF_TEMP = 4.5
    static EQ3BT_ON_TEMP = 30.0
    
    # Mode constants
    static MODE_UNKNOWN = -1
    static MODE_CLOSED = 0
    static MODE_OPEN = 1
    static MODE_AUTO = 2
    static MODE_MANUAL = 3
    static MODE_AWAY = 4
    static MODE_BOOST = 5
    
    # Device state
    var target_temperature
    var mode
    var valve_position
    var low_battery
    var is_locked
    var is_boost
    var window_open
    var comfort_temp
    var eco_temp
    var temp_offset
    var device_serial
    var firmware_version
    
    def init(MAC)
        import BLE
        self.buf = bytes(-64)
        var cbp = tasmota.gen_cb(/e,o,u,h->self.cb(e,o,u,h))
        
        self.mac_address = MAC
        self.is_connected = false
        self.current_func = /->self.wait()
        
        BLE.conn_cb(cbp, self.buf)
        BLE.set_MAC(bytes(MAC), 0)
        BLE.set_svc(self.SERVICE)
        
        tasmota.log(f"EQ3: Initialized for MAC: {MAC}", 2)
    end

    def connect()
        import BLE
        if self.is_connected
            tasmota.log("EQ3: Already connected", 3)
            return
        end
        
        tasmota.log("EQ3: Connecting and subscribing to notifications...", 2)
        # Subscribe to notifications on the notify characteristic
        BLE.set_chr(self.CHAR_NOTIFY)
        BLE.run(3, true)  # Subscribe (connects if needed)
    end
    
    def disconnect()
        import BLE
        if !self.is_connected
            return
        end
        
        BLE.run(5)  # Disconnect
        self.then(/->self.wait())
    end

    def writeCommand(cmd_data)
        import BLE
        self.buf.setbytes(1, cmd_data)
        self.buf[0] = size(cmd_data)
        # Write to write characteristic
        BLE.set_chr(self.CHAR_WRITE)
        BLE.run(2, true)  # Write operation
        tasmota.log(f"EQ3: Write command: {cmd_data}", 3)
    end
    
    # Query device status
    def queryStatus()
        # Include current time in status query to sync thermostat clock
        var now = tasmota.time_dump(tasmota.rtc()['local'])
        var cmd = bytes(-6)
        cmd[0] = self.PROP_INFO_QUERY  # 0x03
        cmd[1] = now['year'] % 100     # Year (last 2 digits)
        cmd[2] = now['month']          # Month (1-12)
        cmd[3] = now['day']            # Day (1-31)
        cmd[4] = now['hour']           # Hour (0-23)
        cmd[5] = now['min']            # Minute (0-59)
        self.writeCommand(cmd)
        tasmota.log(f"EQ3: Query status with time sync: {now['year']}-{now['month']:02d}-{now['day']:02d} {now['hour']:02d}:{now['min']:02d}", 3)
        self.then(/->self.wait())
    end
    
    # Query device ID (serial number)
    def queryID()
        var cmd = bytes(-1)
        cmd[0] = self.PROP_ID_QUERY
        self.writeCommand(cmd)
        self.then(/->self.wait())
    end
    
    # Set target temperature
    def setTemperature(temp)
        if temp < self.EQ3BT_MIN_TEMP || temp > self.EQ3BT_MAX_TEMP
            tasmota.log(f"EQ3: Temperature out of range: {temp}", 2)
            return
        end
        
        var temp_byte = int(temp * 2)  # Temperature is stored as half degrees
        var cmd = bytes(-2)
        cmd[0] = self.PROP_TEMPERATURE_WRITE
        cmd[1] = temp_byte
        self.writeCommand(cmd)
        tasmota.log(f"EQ3: Set temperature: {temp} °C", 2)
        self.then(/->self.disconnect())
    end
    
    # Set mode (manual/auto)
    def setMode(mode_val)
        var cmd = bytes(-2)
        cmd[0] = self.PROP_MODE_WRITE
        cmd[1] = mode_val
        self.writeCommand(cmd)
        tasmota.log(f"EQ3: Set mode: {mode_val}", 2)
        self.then(/->self.disconnect())
    end
    
    # Set boost mode
    def setBoost(enable)
        var cmd = bytes(-2)
        cmd[0] = self.PROP_BOOST
        cmd[1] = enable ? 1 : 0
        self.writeCommand(cmd)
        tasmota.log(f"EQ3: Set boost: {enable}", 2)
        self.then(/->self.disconnect())
    end
    
    # Set lock
    def setLock(enable)
        var cmd = bytes(-2)
        cmd[0] = self.PROP_LOCK
        cmd[1] = enable ? 1 : 0
        self.writeCommand(cmd)
        tasmota.log(f"EQ3: Set lock: {enable}", 2)
        self.then(/->self.disconnect())
    end
    
    # Set comfort temperature
    def setComfortTemp(temp)
        var temp_byte = int(temp * 2)
        var cmd = bytes(-2)
        cmd[0] = self.PROP_COMFORT
        cmd[1] = temp_byte
        self.writeCommand(cmd)
        tasmota.log(f"EQ3: Set comfort temp: {temp} °C", 2)
        self.then(/->self.disconnect())
    end
    
    # Set eco temperature
    def setEcoTemp(temp)
        var temp_byte = int(temp * 2)
        var cmd = bytes(-2)
        cmd[0] = self.PROP_ECO
        cmd[1] = temp_byte
        self.writeCommand(cmd)
        tasmota.log(f"EQ3: Set eco temp: {temp} °C", 2)
        self.then(/->self.disconnect())
    end
    
    # Set temperature offset
    def setOffset(offset)
        # Offset is in range -3.5 to 3.5, stored as (offset + 3.5) * 2
        var offset_byte = int((offset + 3.5) * 2)
        var cmd = bytes(-2)
        cmd[0] = self.PROP_OFFSET
        cmd[1] = offset_byte
        self.writeCommand(cmd)
        tasmota.log(f"EQ3: Set offset: {offset} °C", 2)
        self.then(/->self.disconnect())
    end
    
    # Open valve (set to ON temperature)
    def setOpen()
        var temp_byte = int(self.EQ3BT_ON_TEMP * 2)
        var cmd = bytes(-2)
        cmd[0] = self.PROP_TEMPERATURE_WRITE
        cmd[1] = temp_byte
        self.writeCommand(cmd)
        tasmota.log("EQ3: Set to OPEN (30°C)", 2)
        self.then(/->self.disconnect())
    end
    
    # Close valve (set to OFF temperature)
    def setClose()
        var temp_byte = int(self.EQ3BT_OFF_TEMP * 2)
        var cmd = bytes(-2)
        cmd[0] = self.PROP_TEMPERATURE_WRITE
        cmd[1] = temp_byte
        self.writeCommand(cmd)
        tasmota.log("EQ3: Set to CLOSE (4.5°C)", 2)
        self.then(/->self.disconnect())
    end

    # Parse status response (PROP_INFO_RETURN = 0x02)
    def parseStatus()
        if self.buf[0] < 3
            tasmota.log(f"EQ3: Status data too short: {self.buf[0]} bytes", 2)
            return
        end
        
        var cmd_id = self.buf[1]
        if cmd_id != self.PROP_INFO_RETURN
            tasmota.log(f"EQ3: Unexpected response: {cmd_id}", 2)
            return
        end
        
        # Parse status byte (index 2)
        # Bit 0: manual mode (0=auto, 1=manual)
        # Bit 1: away mode
        # Bit 2: boost mode
        # Bit 3: dst (daylight saving time)
        # Bit 4: window open
        # Bit 5: locked
        # Bit 6: unknown
        # Bit 7: low battery
        
        var status = self.buf[2]
        self.mode = (status & 0x01) ? self.MODE_MANUAL : self.MODE_AUTO
        var away = (status & 0x02) != 0
        self.is_boost = (status & 0x04) != 0
        self.window_open = (status & 0x10) != 0
        self.is_locked = (status & 0x20) != 0
        self.low_battery = (status & 0x80) != 0
        
        if away
            self.mode = self.MODE_AWAY
        elif self.is_boost
            self.mode = self.MODE_BOOST
        end
        
        # Parse valve position (index 3) - percentage
        if self.buf[0] >= 4
            self.valve_position = self.buf[3]
        end
        
        # Parse target temperature (index 4) - half degrees
        if self.buf[0] >= 5
            self.target_temperature = self.buf[4] / 2.0
        end
        
        import json
        var status_json = {
            "EQ3": {
                "Mode": self.mode,
                "TargetTemp": self.target_temperature,
                "Valve": self.valve_position,
                "LowBattery": self.low_battery,
                "Boost": self.is_boost,
                "Locked": self.is_locked,
                "WindowOpen": self.window_open
            }
        }
        tasmota.log(f"EQ3: {json.dump(status_json)}", 2)
        
        self.disconnect()
    end
    
    # Parse ID response (PROP_ID_RETURN = 0x01)
    def parseID()
        if self.buf[0] < 3
            tasmota.log(f"EQ3: ID data too short: {self.buf[0]} bytes", 2)
            return
        end
        
        var cmd_id = self.buf[1]
        if cmd_id != self.PROP_ID_RETURN
            tasmota.log(f"EQ3: Unexpected response: {cmd_id}", 2)
            return
        end
        
        # Parse serial number and firmware version
        # The exact format may vary - this is a simplified version
        tasmota.log(f"EQ3: Device ID data (raw): {self.buf[2..self.buf[0]]}", 3)
        
        self.disconnect()
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
            tasmota.log("EQ3: Disconnect OK", 3)
            self.is_connected = false
            return
        end
        
        if error != 0
            tasmota.log(f"EQ3: BLE Error: {error}, op: {op}", 1)
            return
        end
        
        self.is_connected = true
        
        # Operation codes:
        # 1 = Read completed
        # 2 = Write completed
        # 3 = Subscribe completed
        # 103 = Notification received
        
        if op == 3  # Subscribe completed
            tasmota.log("EQ3: Subscribe OK", 3)
            
        elif op == 103  # Notification received
            tasmota.log(f"EQ3: Notification from UUID: {uuid}, len: {self.buf[0]}", 4)
            
            # Parse notification data
            if self.buf[0] >= 2
                var cmd_id = self.buf[1]
                
                if cmd_id == self.PROP_INFO_RETURN
                    self.parseStatus()
                elif cmd_id == self.PROP_ID_RETURN
                    self.parseID()
                else
                    tasmota.log(f"EQ3: Unknown notification cmd: {cmd_id}", 2)
                    tasmota.log(f"EQ3: Raw data: {self.buf[1..self.buf[0]]}", 4)
                end
            end
            
        elif op == 2  # Write completed
            tasmota.log("EQ3: Write OK", 3)
        elif op == 1  # Read completed
            tasmota.log("EQ3: Read OK", 3)
        else
            tasmota.log(f"EQ3: Unknown op: {op}", 2)
        end
        
        # Call next function in chain
        self.current_func = self.next_func
    end

    # Console Commands
    def cmndConnect(cmd, idx, payload, payload_json)
        self.connect()
        self.then(/->self.queryStatus())
        tasmota.resp_cmnd({"Status": "Connecting"})
    end

    def cmndTemp(cmd, idx, payload, payload_json)
        var temp = real(payload)
        if temp >= self.EQ3BT_MIN_TEMP && temp <= self.EQ3BT_MAX_TEMP
            self.connect()
            self.then(/->self.setTemperature(temp))
            tasmota.resp_cmnd({"Temperature": temp})
        else
            tasmota.resp_cmnd({"Error": "Temperature must be between 5 and 29.5°C"})
        end
    end
    
    def cmndMode(cmd, idx, payload, payload_json)
        import string
        var mode_str = string.tolower(payload)
        var mode_val = self.MODE_MANUAL
        
        if mode_str == "auto"
            mode_val = self.MODE_AUTO
        elif mode_str == "manual"
            mode_val = self.MODE_MANUAL
        else
            tasmota.resp_cmnd({"Error": "Mode must be 'auto' or 'manual'"})
            return
        end
        
        self.connect()
        self.then(/->self.setMode(mode_val))
        tasmota.resp_cmnd({"Mode": mode_str})
    end
    
    def cmndRead(cmd, idx, payload, payload_json)
        self.connect()
        self.then(/->self.queryStatus())
        tasmota.resp_cmnd({"Status": "Reading status"})
    end
    
    def cmndID(cmd, idx, payload, payload_json)
        self.connect()
        self.then(/->self.queryID())
        tasmota.resp_cmnd({"Status": "Reading device ID"})
    end
    
    def cmndBoost(cmd, idx, payload, payload_json)
        var enable = (payload == "1" || payload == "on" || payload == "true")
        self.connect()
        self.then(/->self.setBoost(enable))
        tasmota.resp_cmnd({"Boost": enable})
    end
    
    def cmndLock(cmd, idx, payload, payload_json)
        var enable = (payload == "1" || payload == "on" || payload == "true")
        self.connect()
        self.then(/->self.setLock(enable))
        tasmota.resp_cmnd({"Lock": enable})
    end
    
    def cmndComfort(cmd, idx, payload, payload_json)
        var temp = real(payload)
        if temp >= self.EQ3BT_MIN_TEMP && temp <= self.EQ3BT_MAX_TEMP
            self.connect()
            self.then(/->self.setComfortTemp(temp))
            tasmota.resp_cmnd({"ComfortTemp": temp})
        else
            tasmota.resp_cmnd({"Error": "Temperature must be between 5 and 29.5°C"})
        end
    end
    
    def cmndEco(cmd, idx, payload, payload_json)
        var temp = real(payload)
        if temp >= self.EQ3BT_MIN_TEMP && temp <= self.EQ3BT_MAX_TEMP
            self.connect()
            self.then(/->self.setEcoTemp(temp))
            tasmota.resp_cmnd({"EcoTemp": temp})
        else
            tasmota.resp_cmnd({"Error": "Temperature must be between 5 and 29.5°C"})
        end
    end
    
    def cmndOffset(cmd, idx, payload, payload_json)
        var offset = real(payload)
        if offset >= -3.5 && offset <= 3.5
            self.connect()
            self.then(/->self.setOffset(offset))
            tasmota.resp_cmnd({"Offset": offset})
        else
            tasmota.resp_cmnd({"Error": "Offset must be between -3.5 and 3.5°C"})
        end
    end
    
    def cmndOpen(cmd, idx, payload, payload_json)
        self.connect()
        self.then(/->self.setOpen())
        tasmota.resp_cmnd({"Status": "Opening valve (30°C)"})
    end
    
    def cmndClose(cmd, idx, payload, payload_json)
        self.connect()
        self.then(/->self.setClose())
        tasmota.resp_cmnd({"Status": "Closing valve (4.5°C)"})
    end

    def cmndDisconnect(cmd, idx, payload, payload_json)
        self.disconnect()
        tasmota.resp_cmnd({"Status": "Disconnected"})
    end

    # Web UI Display
    def web_sensor()
        if self.target_temperature == nil return nil end
        import string
        var msg = string.format(
                 "{s}EQ3 Target Temp{m}%.1f °C{e}"..
                 "{s}EQ3 Valve{m}%d %%{e}",
                 self.target_temperature, self.valve_position)
        
        if self.mode != nil
            var mode_str = "Unknown"
            if self.mode == self.MODE_AUTO mode_str = "Auto"
            elif self.mode == self.MODE_MANUAL mode_str = "Manual"
            elif self.mode == self.MODE_AWAY mode_str = "Away"
            elif self.mode == self.MODE_BOOST mode_str = "Boost"
            end
            msg = msg .. string.format("{s}EQ3 Mode{m}%s{e}", mode_str)
        end
        
        if self.low_battery
            msg = msg .. "{s}EQ3 Battery{m}LOW{e}"
        end
        
        tasmota.web_send_decimal(msg)
    end
    
    # Telemetry JSON
    def json_append()
        if self.target_temperature == nil return nil end
        import string
        var msg = string.format(",\"EQ3\":{\"TargetTemp\":%.1f,\"Valve\":%d,\"Mode\":%d}",
            self.target_temperature, self.valve_position, self.mode)
        
        if self.low_battery != nil
            msg = msg .. string.format(",\"LowBattery\":%s", self.low_battery ? "true" : "false")
        end
        
        tasmota.response_append(msg)
    end
end

# Initialize with MAC address
# Replace with your thermostat's MAC address
var eq3 = EQ3BTSmart("001A2209AEDA")
tasmota.add_driver(eq3)

# Register console commands
tasmota.add_cmd('EQ3Connect', /c,i,p,j->eq3.cmndConnect(c,i,p,j))
tasmota.add_cmd('EQ3Temp', /c,i,p,j->eq3.cmndTemp(c,i,p,j))
tasmota.add_cmd('EQ3Mode', /c,i,p,j->eq3.cmndMode(c,i,p,j))
tasmota.add_cmd('EQ3Read', /c,i,p,j->eq3.cmndRead(c,i,p,j))
tasmota.add_cmd('EQ3ID', /c,i,p,j->eq3.cmndID(c,i,p,j))
tasmota.add_cmd('EQ3Boost', /c,i,p,j->eq3.cmndBoost(c,i,p,j))
tasmota.add_cmd('EQ3Lock', /c,i,p,j->eq3.cmndLock(c,i,p,j))
tasmota.add_cmd('EQ3Comfort', /c,i,p,j->eq3.cmndComfort(c,i,p,j))
tasmota.add_cmd('EQ3Eco', /c,i,p,j->eq3.cmndEco(c,i,p,j))
tasmota.add_cmd('EQ3Offset', /c,i,p,j->eq3.cmndOffset(c,i,p,j))
tasmota.add_cmd('EQ3Open', /c,i,p,j->eq3.cmndOpen(c,i,p,j))
tasmota.add_cmd('EQ3Close', /c,i,p,j->eq3.cmndClose(c,i,p,j))
tasmota.add_cmd('EQ3Disconnect', /c,i,p,j->eq3.cmndDisconnect(c,i,p,j))
