#-
 - S3-Eye
 - Example of a board specific driver written in Berry
 -
 - Support for the analog button array and the QMA7981 accelerometer
 - Button readings completely done on the RISCV ULP
 - I2C via ULP would only work without the cam, because pin access must be exlusive :(
 -#

 class S3Eye : Driver
    var wire          #- if wire == nil then the module is not initialized -#
    static button = ["UP","DOWN","PLAY","MENU"]
    var accel
  
    def init()
        self.wire = tasmota.wire_scan(0x12)
        if self.wire
            var v = self.wire.read(0x12,0,1)
            if v != 231 return end  #- wrong device -#
            # activate accelerometer
            self.wire.write(0x12,0x36,0xb6,1)
            self.wire.write(0x12,0x36,0,1)
            var data = self.wire.read(0x12,0x11,1)
            data |= 128;
            self.wire.write(0x12,0x11,data,1)
            self.accel = [0,0,0]
            # init button reader for an analog array of 4 buttons, that change the voltage on GPIO 1 in 4 steps
            # the ULP will measure the voltage and calculate the button index including a flag for a change of the button value
            import ULP
            ULP.wake_period(0,100 * 1000)
            var c = bytes().fromb64("bwDgARMAAAATAAAAEwAAAIKAAAAAAAAAAAAAAAAAFxEAABMBIf69IKEgvSgBoEERgUUBRQbGZSAjLKAWEwcQHIVHY1OnAhMHUDuJR2NepwAFZ5MG95WNR2PYpgATB1e4gUdjQ6cAkUeyQD6FQQGCgEERBsZtPyMuoBYDJ0AYYwflACMioBgFRyMg4BiyQAFFQQGCgKFmg6dGEDcHwP19F/mPI6L2EIKAoWcDp0cQt0bA//0WdY+3xg8AVY8joucQA6dHELcGAAJVjyOi5xADp0cQtwZAAFWPI6LnEAGghUezlbcAhWf9F/2NwgW1Z8GBQRGThweAzgUV6dhHtwYIgP0WdY/ZjczHuEM6whJHWYMTd/cPdfvYR4F2/RZ1j9jH2Ee3BgIAVY/YxxWgmFu3BgiA/RZ1j9mNjNuYW4F2/RZ1j5jbmFu3BgIAVY+Y2xHt2EdBgwWLZd8Z6dxHPsQDVYEAQgVBgUEBgoCYW923nFs+xgNVwQD1tw==")
            # Length in bytes: 376
            ULP.load(c)
            ULP.run()
            ULP.adc_config(0,3,3) # did not work, when applied before ULP.run()
        end
    end

    def read_accel()
        if !self.wire return end  #- exit if not initialized -#
        var b = self.wire.read_bytes(0x12,0x1,6)
        b[0] = b[0] & 252
        b[2] = b[2] & 252
        b[4] = b[4] & 252
        self.accel[0] = (b.geti(0,2))/16
        self.accel[1] = (b.geti(2,2))/16
        self.accel[2] = (b.geti(4,2))/16
    end


    #- trigger a read every second -#
    def every_second()
      self.read_accel()
    end

    def every_100ms()
        import ULP
            if ULP.get_mem(96)               # button updated?
                var b = ULP.get_mem(95)      # button index calculated by the ULP 1-4, 0 is no button pressed
                if b > 0
                    print(self.button[b-1])  # trigger something from here
                end
                ULP.set_mem(96,0)
            end
    end
  
    #- display sensor value in the web UI -#
    def web_sensor()
      if !self.wire return nil end  #- exit if not initialized -#
      import string
      var msg = string.format(
               "{s}QMA7981 acc_x{m}%.3f G{e}"..
               "{s}QMA7981 acc_y{m}%.3f G{e}"..
               "{s}QMA7981 acc_z{m}%.3f G{e}",
                self.accel[0]/1000.0, self.accel[1]/1000.0, self.accel[2]/1000.0)
      tasmota.web_send_decimal(msg)
    end
  
    #- add sensor value to teleperiod -#
    def json_append()
      if !self.wire return nil end  #- exit if not initialized -#
      import string
      var msg = string.format(",\"QMA7981\":{\"AX\":%i,\"AY\":%i,\"AZ\":%i}",
      self.accel[0], self.accel[1], self.accel[2])
      tasmota.response_append(msg)
    end
  
  end
  s3eye = S3Eye()
  tasmota.add_driver(s3eye)
  
