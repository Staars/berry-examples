#-
  EQ3 BT Smart Bluetooth Thermostat Driver for Tasmota
  Based on official protocol documentation
  SPDX-License-Identifier: GPL-3.0-only
-#

class EQ3BTSmart : Driver
    var buf
    var current_func, next_func
    var mac_address, pin, is_subscribed
    var is_connected
    
    # Service UUID (vendor specific)
    static SERVICE = "3e135142-654f-9090-134a-a6ff5bb77046"
    
    # Characteristic UUIDs (write and notify)
    static CHAR_WRITE = "3fa4585a-ce4a-3bad-db4b-b8df8179ea09"
    static CHAR_NOTIFY = "d0e8434d-cd29-0996-af41-6c90f4e0eb2a"
    
    # Command IDs (corrected per protocol spec)
    static CMD_SET_DATETIME = 0x03
    static CMD_SET_TEMP = 0x41
    static CMD_SET_COMFORT = 0x43
    static CMD_SET_ECO = 0x44
    static CMD_MODIFY_COMFORT_ECO = 0x11
    static CMD_BOOST = 0x45
    static CMD_MODE = 0x40
    static CMD_LOCK = 0x80
    static CMD_SET_OFFSET = 0x13
    static CMD_WINDOW_MODE = 0x14
    static CMD_READ_SCHEDULE = 0x20
    static CMD_SET_SCHEDULE = 0x10
    
    # Notification IDs
    static NOTIF_STATUS = 0x02
    static NOTIF_SCHEDULE = 0x21
    
    # Temperature constants
    static EQ3BT_MIN_TEMP = 5.0
    static EQ3BT_MAX_TEMP = 29.5
    static EQ3BT_OFF_TEMP = 4.5
    static EQ3BT_ON_TEMP = 30.0
    
    # Mode constants (for display)
    static MODE_AUTO = 0
    static MODE_MANUAL = 1
    static MODE_HOLIDAY = 2
    static MODE_BOOST = 3
    
    # Lock status
    static LOCK_UNLOCKED = 0
    static LOCK_WINDOW = 1
    static LOCK_MANUAL = 2
    static LOCK_BOTH = 3
    
    # Device state
    var target_temperature
    var mode
    var valve_position
    var low_battery
    var lock_status
    var dst_active
    var window_open
    var comfort_temp
    var eco_temp
    var temp_offset
    
    def init(MAC, pin)
        import BLE
        self.buf = bytes(-64)
        var cbp = tasmota.gen_cb(/e,o,u,h->self.cb(e,o,u,h))
        
        self.mac_address = MAC
        self.is_connected = false
        self.current_func = /->self.wait()
        self.mode = -1
        self.lock_status = 0
        self.is_subscribed = false
        
        BLE.conn_cb(cbp, self.buf)
        BLE.set_MAC(bytes(MAC), 0, pin)
        BLE.set_svc(self.SERVICE)
        
        log(f"EQ3: Initialized for MAC: {MAC}", 2)
    end

    def connect(next_action)
        import BLE
        if self.is_connected || self.is_subscribed
            log("EQ3: Already connected or subscribed, executing action immediately", 3)
            # Already subscribed - execute action immediately, may reconnect if needed
            if next_action != nil
                next_action()
            end
            return
        end
        
        log("EQ3: Connecting and subscribing to notifications...", 2)
        # Not connected - defer action until callback
        if next_action != nil
            self.then(next_action)
        end
        # Subscribe to notifications on the notify characteristic
        BLE.set_chr(self.CHAR_NOTIFY)
        BLE.run(3)  # Subscribe (connects if needed)
    end
    
    def disconnect()
        import BLE
        log("EQ3: Disconnecting...", 3)
        BLE.run(5)  # Disconnect
        self.is_connected = false
        self.then(/->self.wait())
    end

    def writeCommand(cmd_data)
        import BLE
        self.buf.setbytes(1, cmd_data)
        self.buf[0] = size(cmd_data)
        # Write to write characteristic
        BLE.set_chr(self.CHAR_WRITE)
        BLE.run(2, true)  # Write operation
        log(f"EQ3: Write command: {cmd_data.tohex()}", 3)
        self.then(/->self.wait()) # not super nice, but only common function for this
    end
    
    # Sync time with thermostat (triggers status notification)
    def syncTime()
        var now = tasmota.time_dump(tasmota.rtc()['local'])
        var cmd = bytes(-7)
        cmd[0] = self.CMD_SET_DATETIME
        cmd[1] = now['year'] % 100
        cmd[2] = now['month']
        cmd[3] = now['day']
        cmd[4] = now['hour']
        cmd[5] = now['min']
        cmd[6] = now['sec']
        self.writeCommand(cmd)
        log(f"EQ3: Sync time: {now['year']}-{now['month']:02d}-{now['day']:02d} {now['hour']:02d}:{now['min']:02d}:{now['sec']:02d}", 3)
    end
    
    # Set target temperature (triggers status notification)
    def setTemperature(temp)
        if temp < self.EQ3BT_MIN_TEMP || temp > self.EQ3BT_MAX_TEMP
            log(f"EQ3: Temperature out of range: {temp}", 2)
            return
        end
        
        var temp_byte = int(temp * 2)
        var cmd = bytes(-2)
        cmd[0] = self.CMD_SET_TEMP
        cmd[1] = temp_byte
        self.writeCommand(cmd)
        log(f"EQ3: Set temperature: {temp} °C", 2)
    end
    
    # Set mode: 0x00 = auto, 0x40 = manual
    def setMode(auto_mode)
        var cmd = bytes(-2)
        cmd[0] = self.CMD_MODE
        cmd[1] = auto_mode ? 0x00 : 0x40
        self.writeCommand(cmd)
        var mode_str = auto_mode ? "auto" : "manual"
        log(f"EQ3: Set mode: {mode_str}", 2)
    end
    
    # Set boost mode
    def setBoost(enable)
        var cmd = bytes(-2)
        cmd[0] = self.CMD_BOOST
        cmd[1] = enable ? 0x01 : 0x00
        self.writeCommand(cmd)
        log(f"EQ3: Set boost: {enable}", 2)
    end
    
    # Set lock
    def setLock(enable)
        var cmd = bytes(-2)
        cmd[0] = self.CMD_LOCK
        cmd[1] = enable ? 0x01 : 0x00
        self.writeCommand(cmd)
        log(f"EQ3: Set lock: {enable}", 2)
    end
    
    # Activate comfort temperature preset
    def activateComfort()
        var cmd = bytes(-1)
        cmd[0] = self.CMD_SET_COMFORT
        self.writeCommand(cmd)
        log("EQ3: Activate comfort temperature", 2)
    end
    
    # Activate eco temperature preset
    def activateEco()
        var cmd = bytes(-1)
        cmd[0] = self.CMD_SET_ECO
        self.writeCommand(cmd)
        log("EQ3: Activate eco temperature", 2)
    end
    
    # Modify comfort and eco preset temperatures
    def setComfortEcoTemps(comfort_temp, eco_temp)
        var cmd = bytes(-3)
        cmd[0] = self.CMD_MODIFY_COMFORT_ECO
        cmd[1] = int(comfort_temp * 2)
        cmd[2] = int(eco_temp * 2)
        self.writeCommand(cmd)
        log(f"EQ3: Set comfort={comfort_temp}°C, eco={eco_temp}°C", 2)
    end
    
    # Set temperature offset (-3.5 to +3.5)
    def setOffset(offset)
        if offset < -3.5 || offset > 3.5
            log(f"EQ3: Offset out of range: {offset}", 2)
            return
        end
        var offset_byte = int((offset * 2) + 7)
        var cmd = bytes(-2)
        cmd[0] = self.CMD_SET_OFFSET
        cmd[1] = offset_byte
        self.writeCommand(cmd)
        log(f"EQ3: Set offset: {offset} °C", 2)
    end
    
    # Set window open mode (temp and duration in minutes, multiple of 5)
    def setWindowMode(temp, minutes)
        if minutes % 5 != 0 || minutes < 0 || minutes > 60
            log(f"EQ3: Window duration must be 0-60 in 5-min steps", 2)
            return
        end
        var cmd = bytes(-3)
        cmd[0] = self.CMD_WINDOW_MODE
        cmd[1] = int(temp * 2)
        cmd[2] = int(minutes / 5)
        self.writeCommand(cmd)
        log(f"EQ3: Set window mode: {temp}°C for {minutes} min", 2)
    end
    
    # Set holiday mode (temp, end date/time)
    def setHoliday(temp, day, month, year, hour, minutes)
        # Minutes must be 0 or 30
        if minutes != 0 && minutes != 30
            log("EQ3: Holiday minutes must be 0 or 30", 2)
            return
        end
        var cmd = bytes(-6)
        cmd[0] = self.CMD_MODE
        cmd[1] = int((temp * 2) + 128)
        cmd[2] = day
        cmd[3] = year % 100
        cmd[4] = (hour * 2) + int(minutes / 30)
        cmd[5] = month
        self.writeCommand(cmd)
        log(f"EQ3: Set holiday: {temp}°C until {day}/{month}/{year} {hour}:{minutes:02d}", 2)
    end
    
    # Open valve (set to ON temperature)
    def setOpen()
        var temp_byte = int(self.EQ3BT_ON_TEMP * 2)
        var cmd = bytes(-2)
        cmd[0] = self.CMD_SET_TEMP
        cmd[1] = temp_byte
        self.writeCommand(cmd)
        log("EQ3: Set to OPEN (30°C)", 2)
    end
    
    # Close valve (set to OFF temperature)
    def setClose()
        var temp_byte = int(self.EQ3BT_OFF_TEMP * 2)
        var cmd = bytes(-2)
        cmd[0] = self.CMD_SET_TEMP
        cmd[1] = temp_byte
        self.writeCommand(cmd)
        log("EQ3: Set to CLOSE (4.5°C)", 2)
    end

    # Parse status notification (0x02) - Full 15 byte format
    def parseStatus()
        if self.buf[0] < 6
            log(f"EQ3: Status data too short: {self.buf[0]} bytes", 2)
            return
        end
        
        # Log raw data for debugging
        log(f"EQ3: Raw status data ({self.buf[0]} bytes): {self.buf[1..self.buf[0]].tohex()}", 3)
        
        var notif_id = self.buf[1]
        if notif_id != self.NOTIF_STATUS
            log(f"EQ3: Not a status notification: 0x{notif_id:02X}", 2)
            return
        end
        
        var subtype = self.buf[2]
        if subtype != 0x01
            log(f"EQ3: Unexpected status subtype: 0x{subtype:02X}", 2)
            return
        end
        
        # Parse mode byte (index 3) - BITMASK format
        # Bit 0 (0x01): Manual mode (0=auto, 1=manual)
        # Bit 1 (0x02): Vacation mode
        # Bit 2 (0x04): Boost mode
        # Bit 3 (0x08): DST active
        # Bit 4 (0x10): Window open detected
        # Bit 5 (0x20): Locked
        # Bit 6 (0x40): Unknown
        # Bit 7 (0x80): Low battery
        var mode_byte = self.buf[3]
        var is_manual = (mode_byte & 0x01) != 0
        var is_vacation = (mode_byte & 0x02) != 0
        var is_boost = (mode_byte & 0x04) != 0
        var dst_active = (mode_byte & 0x08) != 0
        self.window_open = (mode_byte & 0x10) != 0
        var is_locked = (mode_byte & 0x20) != 0
        self.low_battery = (mode_byte & 0x80) != 0
        
        # Determine primary mode
        if is_boost
            self.mode = self.MODE_BOOST
        elif is_vacation
            self.mode = self.MODE_HOLIDAY
        elif is_manual
            self.mode = self.MODE_MANUAL
        else
            self.mode = self.MODE_AUTO
        end
        
        # Parse valve position (index 4) - percentage (0-100)
        self.valve_position = self.buf[4]
        
        # Index 5 should be 0x04
        var byte5 = self.buf[5]
        if byte5 != 0x04
            log(f"EQ3: Warning - Byte 5 expected 0x04, got 0x{byte5:02X}", 2)
        end
        
        # Parse target temperature (index 6) - half degrees
        self.target_temperature = self.buf[6] / 2.0
        
        # Parse vacation data (bytes 7-10) if vacation mode active
        var vacation_info = ""
        if is_vacation && self.buf[0] >= 10
            var vac_day = self.buf[7]
            var vac_year = self.buf[8] + 2000
            var vac_time_encoded = self.buf[9]
            var vac_month = self.buf[10]
            var vac_hour = vac_time_encoded / 2
            var vac_min = (vac_time_encoded % 2) * 30
            vacation_info = f" until {vac_day}/{vac_month}/{vac_year} {vac_hour}:{vac_min:02d}"
        end
        
        # Parse extended data (bytes 11-15) if available
        if self.buf[0] >= 15
            var window_temp = self.buf[11] / 2.0
            var window_interval = self.buf[12] * 5  # in minutes
            self.comfort_temp = self.buf[13] / 2.0
            self.eco_temp = self.buf[14] / 2.0
            self.temp_offset = (self.buf[15] - 7) / 2.0
            
            log(f"EQ3: Window={window_temp}°C/{window_interval}min, Comfort={self.comfort_temp}°C, Eco={self.eco_temp}°C, Offset={self.temp_offset}°C", 3)
        end
        
        # Build mode string
        var mode_parts = []
        if is_manual
            mode_parts.push("manual")
        else
            mode_parts.push("auto")
        end
        if is_vacation mode_parts.push("vacation") end
        if is_boost mode_parts.push("boost") end
        if self.window_open mode_parts.push("window") end
        if dst_active mode_parts.push("dst") end
        
        var mode_str = mode_parts[0]
        for i:1..size(mode_parts)-1
            mode_str = mode_str .. "+" .. mode_parts[i]
        end
        
        import json
        var status_json = {
            "EQ3": {
                "MAC": self.mac_address,
                "Mode": mode_str,
                "TargetTemp": self.target_temperature,
                "Valve": self.valve_position,
                "Locked": is_locked,
                "LowBattery": self.low_battery
            }
        }
        
        if self.buf[0] >= 15
            status_json["EQ3"]["ComfortTemp"] = self.comfort_temp
            status_json["EQ3"]["EcoTemp"] = self.eco_temp
            status_json["EQ3"]["TempOffset"] = self.temp_offset
        end
        
        log(f"EQ3: {json.dump(status_json)}{vacation_info}", 2)
        
        # Disconnect after receiving status
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
            log(f"EQ3: Disconnected (error: {error})", 3)
            self.is_connected = false
            return
        end
        
        if error != 0
            log(f"EQ3: BLE Error: {error}, op: {op}", 1)
            return
        end
        
        self.is_connected = true
        
        # Operation codes:
        # 1 = Read completed
        # 2 = Write completed
        # 3 = Subscribe completed
        # 103 = Notification received
        
        if op == 3  # Subscribe completed
            log("EQ3: Subscribe OK", 3)
            self.is_subscribed = true
            
        elif op == 103  # Notification received
            log(f"EQ3: Notification received, len: {self.buf[0]}", 3)
            
            # Parse notification data
            if self.buf[0] >= 2
                var notif_id = self.buf[1]
                
                if notif_id == self.NOTIF_STATUS
                    self.parseStatus()
                elif notif_id == self.NOTIF_SCHEDULE
                    log("EQ3: Schedule notification received (not parsed)", 2)
                else
                    log(f"EQ3: Unknown notification: 0x{notif_id:02X}", 2)
                    log(f"EQ3: Raw data: {self.buf[1..self.buf[0]].tohex()}", 4)
                end
            end
            
        elif op == 2  # Write completed
            log("EQ3: Write OK", 3)
        elif op == 1  # Read completed
            log("EQ3: Read OK", 3)
        else
            log(f"EQ3: Unknown op: {op}", 2)
        end
        
        # Call next function in chain
        if self.next_func != nil
            self.current_func = self.next_func
            self.next_func = nil
        end
    end

    # Console Commands
    def cmndConnect(cmd, idx, payload, payload_json)
        self.connect(/->self.syncTime())
        tasmota.resp_cmnd({"Status": "Connecting and syncing time"})
    end

    def cmndTemp(cmd, idx, payload, payload_json)
        var temp = real(payload)
        if temp >= self.EQ3BT_MIN_TEMP && temp <= self.EQ3BT_MAX_TEMP
            self.connect(/->self.setTemperature(temp))
            tasmota.resp_cmnd({"Temperature": temp})
        else
            tasmota.resp_cmnd({"Error": "Temperature must be between 5 and 29.5°C"})
        end
    end
    
    def cmndMode(cmd, idx, payload, payload_json)
        import string
        var mode_str = string.tolower(payload)
        
        if mode_str == "auto"
            self.connect(/->self.setMode(true))
            tasmota.resp_cmnd({"Mode": "auto"})
        elif mode_str == "manual"
            self.connect(/->self.setMode(false))
            tasmota.resp_cmnd({"Mode": "manual"})
        else
            tasmota.resp_cmnd({"Error": "Mode must be 'auto' or 'manual'"})
        end
    end
    
    def cmndBoost(cmd, idx, payload, payload_json)
        var enable = (payload == "1" || payload == "on" || payload == "true")
        self.connect(/->self.setBoost(enable))
        tasmota.resp_cmnd({"Boost": enable})
    end
    
    def cmndLock(cmd, idx, payload, payload_json)
        var enable = (payload == "1" || payload == "on" || payload == "true")
        self.connect(/->self.setLock(enable))
        tasmota.resp_cmnd({"Lock": enable})
    end
    
    def cmndComfort(cmd, idx, payload, payload_json)
        self.connect(/->self.activateComfort())
        tasmota.resp_cmnd({"Status": "Activating comfort temperature"})
    end
    
    def cmndEco(cmd, idx, payload, payload_json)
        self.connect(/->self.activateEco())
        tasmota.resp_cmnd({"Status": "Activating eco temperature"})
    end
    
    def cmndSetComfortEco(cmd, idx, payload, payload_json)
        # Expects format: "comfort,eco" e.g. "23,18.5"
        import string
        var temps = string.split(payload, ',')
        if size(temps) != 2
            tasmota.resp_cmnd({"Error": "Format: comfort,eco (e.g. '23,18.5')"})
            return
        end
        var comfort = real(temps[0])
        var eco = real(temps[1])
        if comfort >= self.EQ3BT_MIN_TEMP && comfort <= self.EQ3BT_MAX_TEMP &&
           eco >= self.EQ3BT_MIN_TEMP && eco <= self.EQ3BT_MAX_TEMP
            self.connect(/->self.setComfortEcoTemps(comfort, eco))
            tasmota.resp_cmnd({"Comfort": comfort, "Eco": eco})
        else
            tasmota.resp_cmnd({"Error": "Temps must be between 5 and 29.5°C"})
        end
    end
    
    def cmndOffset(cmd, idx, payload, payload_json)
        var offset = real(payload)
        if offset >= -3.5 && offset <= 3.5
            self.connect(/->self.setOffset(offset))
            tasmota.resp_cmnd({"Offset": offset})
        else
            tasmota.resp_cmnd({"Error": "Offset must be between -3.5 and 3.5°C"})
        end
    end
    
    def cmndWindow(cmd, idx, payload, payload_json)
        # Expects format: "temp,minutes" e.g. "12,15"
        import string
        var params = string.split(payload, ',')
        if size(params) != 2
            tasmota.resp_cmnd({"Error": "Format: temp,minutes (e.g. '12,15')"})
            return
        end
        var temp = real(params[0])
        var minutes = int(params[1])
        self.connect(/->self.setWindowMode(temp, minutes))
        tasmota.resp_cmnd({"WindowTemp": temp, "Duration": minutes})
    end
    
    def cmndOpen(cmd, idx, payload, payload_json)
        self.connect(/->self.setOpen())
        tasmota.resp_cmnd({"Status": "Opening valve (30°C)"})
    end
    
    def cmndClose(cmd, idx, payload, payload_json)
        self.connect(/->self.setClose())
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
                 "{s}EQ3 MAC{m}%s{e}"..
                 "{s}EQ3 Target Temp{m}%.1f °C{e}"..
                 "{s}EQ3 Valve{m}%d %%{e}",
                 self.mac_address, self.target_temperature, self.valve_position)
        
        if self.mode != nil && self.mode >= 0
            var mode_str = "Unknown"
            if self.mode == self.MODE_AUTO mode_str = "Auto"
            elif self.mode == self.MODE_MANUAL mode_str = "Manual"
            elif self.mode == self.MODE_HOLIDAY mode_str = "Holiday"
            elif self.mode == self.MODE_BOOST mode_str = "Boost"
            end
            msg = msg .. string.format("{s}EQ3 Mode{m}%s{e}", mode_str)
        end
        
        if self.comfort_temp != nil
            msg = msg .. string.format("{s}EQ3 Comfort{m}%.1f °C{e}", self.comfort_temp)
        end
        
        if self.eco_temp != nil
            msg = msg .. string.format("{s}EQ3 Eco{m}%.1f °C{e}", self.eco_temp)
        end
        
        if self.temp_offset != nil
            msg = msg .. string.format("{s}EQ3 Offset{m}%.1f °C{e}", self.temp_offset)
        end
        
        if self.window_open
            msg = msg .. "{s}EQ3 Window{m}OPEN{e}"
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
        import json
        
        var data = {
            "MAC": self.mac_address,
            "TargetTemp": self.target_temperature,
            "Valve": self.valve_position
        }
        
        if self.mode != nil && self.mode >= 0
            var mode_str = ["Auto", "Manual", "Holiday", "Boost"][self.mode]
            data['Mode'] = mode_str
        end
        
        if self.comfort_temp != nil
            data['ComfortTemp'] = self.comfort_temp
        end
        
        if self.eco_temp != nil
            data['EcoTemp'] = self.eco_temp
        end
        
        if self.temp_offset != nil
            data['TempOffset'] = self.temp_offset
        end
        
        if self.window_open != nil
            data['WindowOpen'] = self.window_open
        end
        
        if self.low_battery != nil
            data['LowBattery'] = self.low_battery
        end
        
        var msg = string.format(",\"EQ3\":%s", json.dump(data))
        tasmota.response_append(msg)
    end
end

# Initialize with your thermostat's MAC address and PIN
# Replace with your actual values
var eq3 = EQ3BTSmart("001A221FCB75", 016414)  # PIN as integer
tasmota.add_driver(eq3)

# Register console commands
tasmota.add_cmd('EQ3Connect', /c,i,p,j->eq3.cmndConnect(c,i,p,j))
tasmota.add_cmd('EQ3Temp', /c,i,p,j->eq3.cmndTemp(c,i,p,j))
tasmota.add_cmd('EQ3Mode', /c,i,p,j->eq3.cmndMode(c,i,p,j))
tasmota.add_cmd('EQ3Boost', /c,i,p,j->eq3.cmndBoost(c,i,p,j))
tasmota.add_cmd('EQ3Lock', /c,i,p,j->eq3.cmndLock(c,i,p,j))
tasmota.add_cmd('EQ3Comfort', /c,i,p,j->eq3.cmndComfort(c,i,p,j))
tasmota.add_cmd('EQ3Eco', /c,i,p,j->eq3.cmndEco(c,i,p,j))
tasmota.add_cmd('EQ3SetComfortEco', /c,i,p,j->eq3.cmndSetComfortEco(c,i,p,j))
tasmota.add_cmd('EQ3Offset', /c,i,p,j->eq3.cmndOffset(c,i,p,j))
tasmota.add_cmd('EQ3Window', /c,i,p,j->eq3.cmndWindow(c,i,p,j))
tasmota.add_cmd('EQ3Open', /c,i,p,j->eq3.cmndOpen(c,i,p,j))
tasmota.add_cmd('EQ3Close', /c,i,p,j->eq3.cmndClose(c,i,p,j))
tasmota.add_cmd('EQ3Disconnect', /c,i,p,j->eq3.cmndDisconnect(c,i,p,j))
