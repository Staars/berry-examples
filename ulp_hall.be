#-
 - Example of ULP driver written in Berry
 -
 - Support for hall sensor of the ESP32
 - Allow wake from deep sleep
 -#

class HALL : Driver
  var p0, p1, n0, n1, diff_p, diff_n
  var thresh_p, thresh_n
  
  def get_code()
    return bytes().fromb64("dWxwAAwA7AAAABgAFgZoHR4F/B8WBuwdHgF4HwMOyBkCAIByAwCAcgAAQHQEAABQCgAAcBEAAFAfAABwEAAAdAQACoUqAMBysAOAcgIAAGgvAMBywQOAcgcAAGgeBXgfAgCAcgMAgHIAAEB0BAAAUAoAAHARAABQHwAAcBAAAHQEAAqFKgDActADgHICAABoLwDAcuEDgHIHAABo4wOAcg8AANDCA4ByCgAA0DsAIHACBIByCwAAaNMDgHIPAADQsgOAcgoAANAvACBw8gOAcgsAAGgIAADQBwAFggAAALAwAMwpEABActAAQIABAACQBgBgHAAAALA=")  end

  def init()
    import ULP
    ULP.wake_period(0,1000000)
    ULP.adc_config(0,2,3)
    ULP.adc_config(3,2,3)
    var c = self.get_code()
    ULP.load(c)
    ULP.run()
  end
  
  #- Very specific for the ULP code, greater/equal P difference-#
  def set_thres(threshold)
    import ULP
    var c = self.get_code()
    var jmp_threshold = 51 # can change, when ULP code changes
    var pos = (3+jmp_threshold)*4
    var cmd = c[pos..pos+4]
    cmd.set(0,threshold,2) # upper 16 bit
    ULP.set_mem(51,cmd.get(0, 4))
  end

  #- read from RTC_SLOW_MEM, measuring was done by ULP -#
  def read_voltage()
    import ULP
    self.p0 = ULP.get_mem(59)
    self.n0 = ULP.get_mem(60)
    self.p1 = ULP.get_mem(61)
    self.n1 = ULP.get_mem(62)
    self.diff_p = ULP.get_mem(63)
    self.diff_n = ULP.get_mem(64)
  end

  #- trigger a read every second -#
  def every_second()
    self.read_voltage()
  end

  #- display sensor value in the web UI -#
  def web_sensor()
    import string
    var msg = string.format(
             "{s}<hr>{m}<hr>{e}"
             "{s}Hall sensor{m}ULP readings:{e}"
             "{s}P0 {m}%i{e}"..
             "{s}P1 {m}%i{e}"..
             "{s}Diff P {m}%i{e}"..
             "{s}N0 {m}%i{e}"..
             "{s}N1 {m}%i{e}"..
             "{s}Diff N {m}%i{e}",
                  self.p0, self.p1, self.diff_p, self.n0, self.n1, self.diff_n)
    tasmota.web_send_decimal(msg)
  end

  #- add sensor value to teleperiod -#
  def json_append()

    import string
    var msg = string.format(",\"Hall\":{\"P0\":%i,\"P1\":%i,\"DP\":%i,\"N0\":%i,\"N1\":%i,\"Dn\":%i}",
                                 self.p0, self.p1, self.diff_p, self.n0, self.n1, self.diff_n)
    tasmota.response_append(msg)
  end

end

hall = HALL()
tasmota.add_driver(hall)

def usleep(cmd, idx, payload, payload_json)
    import ULP
    ULP.sleep(int(payload))
end
tasmota.add_cmd('usleep', usleep)

def hall_thres(cmd, idx, payload, payload_json)
    import ULP
    import string
    if payload != ""
        hall.set_thres(int(payload))
    end
    tasmota.resp_cmnd(string.format('{"hall threshold":%i}', ULP.get_mem(51)))
end
tasmota.add_cmd('hall_thres', hall_thres)
