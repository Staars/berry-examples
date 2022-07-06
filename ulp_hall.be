#-
 - Example of ULP driver written in Berry
 -
 - Support for hall sensor of the ESP32
 - Allow wake from deep sleep
 -#

class HALL : Driver
  var p0, p1, n0, n1, diff_p, diff_n
  var thresh_p, thresh_n

  def init()
    import ULP
    ULP.wake_period(0,1000000)
    ULP.adc_config(0,2,3)
    ULP.adc_config(3,2,3)
    var c = bytes("756c70000c00ec00000018001606681d1e05fc1f1606ec1d1e01781f030ec819020080720300807200004074040000500a000070110000501f0000701000007404000a852a00c072b0038072020000682f00c072c1038072070000681e05781f020080720300807200004074040000500a000070110000501f0000701000007404000a852a00c072d0038072020000682f00c072e103807207000068e30380720f0000d0c20380720a0000d02f002070020480720b000068d30380720f0000d0b20380720a0000d02f002070f20380720b000068080000d007000582000000b03000cc2910004072d0004080010000900600601c000000b0")
    ULP.load(c)
    ULP.run()
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
