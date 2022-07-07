"""
LED-Example with exporting ULP code to Tasmotas Berry implementation
"""
from esp32_ulp import src_to_binary
import ubinascii

source = """\
# constants from:
# https://github.com/espressif/esp-idf/blob/1cb31e5/components/soc/esp32/include/soc/soc.h
#define DR_REG_RTCIO_BASE            0x3ff48400

# constants from:
# https://github.com/espressif/esp-idf/blob/1cb31e5/components/soc/esp32/include/soc/rtc_io_reg.h
#define RTC_IO_TOUCH_PAD2_REG        (DR_REG_RTCIO_BASE + 0x9c)
#define RTC_IO_TOUCH_PAD2_MUX_SEL_M  (BIT(19))
#define RTC_GPIO_OUT_REG             (DR_REG_RTCIO_BASE + 0x0)
#define RTC_GPIO_ENABLE_W1TS_REG     (DR_REG_RTCIO_BASE + 0x10)
#define RTC_GPIO_ENABLE_W1TC_REG     (DR_REG_RTCIO_BASE + 0x14)
#define RTC_GPIO_ENABLE_W1TS_S       14
#define RTC_GPIO_ENABLE_W1TC_S       14
#define RTC_GPIO_OUT_DATA_S          14

# constants from:
# https://github.com/espressif/esp-idf/blob/1cb31e5/components/soc/esp32/include/soc/rtc_io_channel.h
#define RTCIO_GPIO2_CHANNEL          12

# When accessed from the RTC module (ULP) GPIOs need to be addressed by their channel number
.set gpio, RTCIO_GPIO2_CHANNEL
.set token, 0xcafe  # magic token

.text
  jump entry

magic: .long 0 # ulp.get_mem(1)
state: .long 0 # ulp.get_mem(2)

.global entry
entry:
  # load magic flag
  move r0, magic
  ld r1, r0, 0

  # test if we have initialised already
  sub r1, r1, token
  jump after_init, eq  # jump if magic == token (note: "eq" means the last instruction (sub) resulted in 0)

init:
  # connect GPIO to ULP (0: GPIO connected to digital GPIO module, 1: GPIO connected to analog RTC module)
  WRITE_RTC_REG(RTC_IO_TOUCH_PAD2_REG, RTC_IO_TOUCH_PAD2_MUX_SEL_M, 1, 1);

  # GPIO shall be output, not input
  WRITE_RTC_REG(RTC_GPIO_OUT_REG, RTC_GPIO_OUT_DATA_S + gpio, 1, 1);

  # store that we're done with initialisation
  move r0, magic
  move r1, token
  st r1, r0, 0

after_init:
  move r1, state
  ld r0, r1, 0

  move r2, 1
  sub r0, r2, r0  # toggle state
  st r0, r1, 0  # store updated state

  jumpr on, 0, gt  # if r0 (state) > 0, jump to 'on'
  jump off  # else jump to 'off'

on:
  # turn on led (set GPIO)
  WRITE_RTC_REG(RTC_GPIO_ENABLE_W1TS_REG, RTC_GPIO_ENABLE_W1TS_S + gpio, 1, 1)
  sleep 0
  jump exit

off:
  # turn off led (clear GPIO)
  WRITE_RTC_REG(RTC_GPIO_ENABLE_W1TC_REG, RTC_GPIO_ENABLE_W1TC_S + gpio, 1, 1)
  sleep 1
  jump exit

exit:
  halt  # go back to sleep until next wakeup period
"""

binary = src_to_binary(source)

# Export section for Berry
code_b64 = ubinascii.b2a_base64(binary).decode('utf-8')[:-1]

file = open ("ulp_heartbeat.txt", "w")
file.write(code_b64)

print("")
print("#You can paste the following snippet into Tasmotas Berry console:")
print("import ULP")
print("ULP.wake_period(0,500000) # on time")
print("ULP.wake_period(1,200000) # off time ")
print("var c = bytes().fromb64(\""+code_b64+"\")")
print("ULP.load(c)")
print("ULP.run()")
