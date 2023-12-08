#-
 - ULP driver for Ulanzi clock written in Berry
 -
 - Support for analog read of built in battery and light sensor
 - Alternative to xsns_02_analog.ino
 - Shall free up CPU resources for LED animations
 -#

class ULANZI_ADC
  var battery, light

  def init()
    self.load_ULP()
    tasmota.add_driver(self)
  end

  def load_ULP()
    import ULP
    if int(tasmota.cmd("status 2")["StatusFWR"]["Core"]) == 2
      ULP.adc_config(6,3,3) # battery
      ULP.adc_config(7,3,3) # light
    else
      ULP.adc_config(6,3,12) # battery
      ULP.adc_config(7,3,12) # light
    end
    ULP.wake_period(0,1000 * 1000) # timer register 0 - every 1000 millisecs
    var c = bytes().fromb64("dWxwAAwAXAAAAAwAcwGAcg4AANAaAAByDgAAaAAAgHIAAEB0HQAAUBAAAHAQAAB0EAAGhUAAwHKDAYByDAAAaAAAgHIAAEB0IQAAUBAAAHAQAAB0EAAGhUAAwHKTAYByDAAAaAAAALA=") 
    ULP.load(c) 
    ULP.run() 
  end

  #- these memory adresses get populated by the ULP programm -#
  def read_values()
    import ULP
    # (ulp_sample_counter = 0x5000005c) -> ULP.get_mem(23) 
    # (ulp_battery_last_result = 0x50000060) -> ULP.get_mem(24) 
    # (ulp_light_last_result = 0x50000064) -> ULP.get_mem(25)
    self.battery = ULP.get_mem(24)
    self.light = ULP.get_mem(25)
  end

  #- trigger a read every second -#
  def every_second()
    self.read_values()
  end

  #- display sensor value in the web UI -#
  def web_sensor()
    var msg = format(
             "{s}ADC Battery{m}%i mV{e}"..
             "{s}ADC Light{m}%i mV{e}",
              self.battery, self.light)
    tasmota.web_send_decimal(msg)
  end

  #- add sensor value to teleperiod -#
  def json_append()
    var msg = format(",\"Analog\":{\"Battery\":%i,\"Light\":%i}",
                    self.battery, self.light)
    tasmota.response_append(msg)
  end

end

return ULANZI_ADC()
