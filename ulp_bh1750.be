#-
 - Example of ULP driver written in Berry
 -
 - BH1750 driver via ULP of the ESP32
 - uses bitbanging
 -#

class BH1750 : Driver
  var lux
  
  def get_code()
    return bytes().fromb64("dWxwAAwA3AMAAHgAQxGAclEAgHINAABoHwAgctgBAICRD4ByBAAA0BAAAHIEAABoAwAFgkAAAICRD4ByBAAA0AAAgHIEAABoRAAAgAAAALAwAMwpEABAckAAQIABAACQBgBgHAAAALBxBIByDQAAaB8AIHLhAYByDQAAaB8AIHJMAgCADgQA0DECgHINAABoHwAgckQDAIABAMeCHwAAcg0AANACAIBysQKAcg0AAGgfACByhAMAgAwAAGgfACByEgCAciEDgHINAABoHwAgcoQDAIAMAABoHwAgcoEDgHINAABoHwAgcqwCAIAfAAByDAAA0B8AAHIOAADQigCgcgoAYHAoAIBwoQ+AcgQAAGgCAIByHwAAcg0AANABACCAkQSAcg0AAGgfACByTAIAgA4MANDhBIByDQAAaB8AIHJEAwCAAQBxgg4IANBBBYByDQAAaB8AIHJEAwCAAQBlgpEFgHINAABoHwAgcqwCAIAfAAByDQAA0AEAIIBhBIByDQAAaB8AIHIRAIByDQAAaB8AIHJhBoByDQAAaB8AIHIUAQCAHwAAcg0AANABAoByDQAAaB8AIHLxBoByDQAAaB8AIHIUAQCAHwAAcg0AANAfAAByDQAA0B8AAHINAADQAQAggKEHgHINAABoHwAgcnABAICCDIBy8QeAcg0AAGgfACByMAIAgDEIgHINAABoHwAgclwAAIAfAAByDQAA0AEAIIAfAAByDQAA0BIAgHIfAAByDQAA0AEAIIBAHwBAGgAgckACQIAwAgCAHwAAcg0AANABACCAgQ+AcgQAANABAAuCEACAcgQAAGgAAdwbAAFYG3IPgHIIAADQAQAOggUFWBsyAABABQXcGwkB3CsBAAKDMgAAQAQFWBsyAABABAXcGxAAgHIIAABoHwAAcg0AANABACCABAVYGzIAAEAFBdwbCQHcKwEAAoMyAABABQVYGzIAAEByD4ByAACAcggAAGgfAAByDQAA0AEAIIABAAaCBQVYG/QCAIAEBVgbMgAAQAUF3BsyAABACQHcKwEAAoMEBdwbHwAAcg0AANABACCABQVYGzIAAEAFBdwbCQHcKwEAAoMyAABACQFYKwQF3BsfAAByDQAA0AEAIIAAAEB0CAhAcnENgHINAABoHwAgcuQCAIAaAKByEAAAdAgADoXhDYByDQAAaB8AIHIYAwCAHwAAcg0AANABACCADgAAaB8AIHICAIByAABAdJEOgHINAABoHwAgchgDAIAaAKByCgBgcBAAAHQIAA6FHwAAcgwAANAxD4ByDQAAaB8AIHLkAgCAKACAcB8AAHINAADQAQAggA==")
  end

  def init()
    import ULP
    ULP.wake_period(0, 3 * 1000 * 1000)
    ULP.gpio_init(32,0) # SCL
    ULP.gpio_init(33,0) # SDA
    var c = self.get_code()
    ULP.load(c)
    ULP.run()
  end

  #- read from RTC_SLOW_MEM, measuring was done by ULP -#
  def read_lux()
    import ULP
    self.lux = int(ULP.get_mem(250)/1.2)
  end

  #- trigger a read every second -#
  def every_second()
    self.read_lux()
  end

  #- display sensor value in the web UI -#
  def web_sensor()
    import string
    var msg = string.format("{s}BH-1750{m}%i lx{e}",self.lux)
    tasmota.web_send_decimal(msg)
  end

  #- add sensor value to teleperiod -#
  def json_append()
    import string
    var msg = string.format(",\"BH1750\":{\"Illuminance\":%i}",self.lux)
    tasmota.response_append(msg)
  end

end

bh1750 = BH1750()
tasmota.add_driver(bh1750)

