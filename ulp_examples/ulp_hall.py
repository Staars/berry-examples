"""
Hall sensor example with exporting ULP code to Tasmotas Berry implementation
"""
from esp32_ulp import src_to_binary
import ubinascii

source = """
/* ULP Example: Read hall sensor in deep sleep

   For other examples please check:
   https://github.com/espressif/esp-iot-solution/tree/master/examples

   This example code is in the Public Domain (or CC0 licensed, at your option.)

   Unless required by applicable law or agreed to in writing, this
   software is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
   CONDITIONS OF ANY KIND, either express or implied.
 */

/* ULP assembly files are passed through C preprocessor first, so include directives
   and C macros may be used in these files
 */

#include "soc/rtc_cntl_reg.h"
#include "soc/rtc_io_reg.h"
#include "soc/soc_ulp.h"
#include "soc/sens_reg.h"

#define DR_REG_RTCIO_BASE                       0x3ff48400
#define DR_REG_SENS_BASE                        0x3ff48800
#define DR_REG_RTCCNTL_BASE                     0x3ff48000


#define SENS_SAR_TOUCH_CTRL1_REG          (DR_REG_SENS_BASE + 0x0058)
#define SENS_XPD_HALL_FORCE_S  26
#define RTC_IO_XPD_HALL_S  31
#define SENS_HALL_PHASE_FORCE_S  27
#define RTC_IO_HALL_PHASE_S  30
#define SENS_FORCE_XPD_SAR_PD  2 // Force power down
#define SENS_FORCE_XPD_SAR_PU  3 // Force power up
#define SENS_FORCE_XPD_SAR_S  18

#define RTC_IO_HALL_SENS_REG          (DR_REG_RTCIO_BASE + 0x78)
#define SENS_SAR_MEAS_WAIT2_REG          (DR_REG_SENS_BASE + 0x000c)
#define RTC_CNTL_DIAG0_REG           (DR_REG_RTCCNTL_BASE + 0xc0)
#define RTC_CNTL_STATE0_REG          (DR_REG_RTCCNTL_BASE + 0x18)
#define RTC_CNTL_ULP_CP_SLP_TIMER_EN  (BIT(24))

  /* Configure the number of ADC samples to average on each measurement.
     For convenience, make it a power of 2. */
    .set adc_oversampling_factor_log, 2
    .set adc_oversampling_factor, (1 << adc_oversampling_factor_log)
    
    .set threshold_pos   , 7
    .set threshold_neg   , 2

  /* Define variables, which go into .bss section (zero-initialized data) */
  .bss
  .global Sens_Vp0
Sens_Vp0:
  .long 0

  .global Sens_Vn0
Sens_Vn0:
  .long 0

  .global Sens_Vp1
Sens_Vp1:
  .long 0

  .global Sens_Vn1
Sens_Vn1:
  .long 0
  
  .global Sens_Diff_p1
Sens_Diff_p1:
  .long 0
  
  .global Sens_Diff_n1
Sens_Diff_n1:
  .long 0

  /* Code goes into .text section */
  .text
  .global entry
entry:

  /* SENS_XPD_HALL_FORCE = 1, hall sensor force enable, XPD HALL is controlled by SW */
  WRITE_RTC_REG(SENS_SAR_TOUCH_CTRL1_REG, SENS_XPD_HALL_FORCE_S, 1, 1)

  /* RTC_IO_XPD_HALL = 1, xpd hall, Power on hall sensor and connect to VP and VN */
  WRITE_RTC_REG(RTC_IO_HALL_SENS_REG, RTC_IO_XPD_HALL_S, 1, 1)

  /* SENS_HALL_PHASE_FORCE = 1, phase force, HALL PHASE is controlled by SW */
  WRITE_RTC_REG(SENS_SAR_TOUCH_CTRL1_REG, SENS_HALL_PHASE_FORCE_S, 1, 1)

  /* RTC_IO_HALL_PHASE = 0, phase of hall sensor */
  WRITE_RTC_REG(RTC_IO_HALL_SENS_REG, RTC_IO_HALL_PHASE_S, 1, 0)

  /* SENS_FORCE_XPD_SAR, Force power up */
  WRITE_RTC_REG(SENS_SAR_MEAS_WAIT2_REG, SENS_FORCE_XPD_SAR_S, 2, SENS_FORCE_XPD_SAR_PU)

  /* do measurements using ADC */
  /* r2, r3 will be used as accumulator */
  move r2, 0
  move r3, 0
  /* initialize the loop counter */
  stage_rst
measure0:
  /* measure Sar_Mux = 1 to get vp0   */
  adc r0, 0, 1
  add r2, r2, r0

  /* measure Sar_Mux = 4 to get vn0 */
  adc r1, 0, 4
  add r3, r3, r1

  /* increment loop counter and check exit condition */
  stage_inc 1
  jumps measure0, adc_oversampling_factor, lt

  /* divide accumulator by adc_oversampling_factor.
     Since it is chosen as a power of two, use right shift */
  rsh r2, r2, adc_oversampling_factor_log

  /* averaged value is now in r2; store it into Sens_Vp0 */
  move r0, Sens_Vp0
  st r2, r0, 0

  /* r3 divide 4 which means rsh 2 bits */
  rsh r3, r3, adc_oversampling_factor_log
  /* averaged value is now in r3; store it into Sens_Vn0 */
  move r1, Sens_Vn0
  st r3, r1, 0
  
  /* RTC_IO_HALL_PHASE = 1, phase of hall sensor */
  WRITE_RTC_REG(RTC_IO_HALL_SENS_REG, RTC_IO_HALL_PHASE_S, 1, 1)

  /* do measurements using ADC */
  /* r2, r3 will be used as accumulator */
  move r2, 0
  move r3, 0
  /* initialize the loop counter */
  stage_rst
measure1:
  /* measure Sar_Mux = 1 to get vp1   */
  adc r0, 0, 1
  add r2, r2, r0

  /* measure Sar_Mux = 4 to get vn1 */
  adc r1, 0, 4
  add r3, r3, r1

  /* increment loop counter and check exit condition */
  stage_inc 1
  jumps measure1, adc_oversampling_factor, lt

  /* divide accumulator by adc_oversampling_factor.
     Since it is chosen as a power of two, use right shift */
  rsh r2, r2, adc_oversampling_factor_log

  /* averaged value is now in r2; store it into Sens_Vp1 */
  move r0, Sens_Vp1
  st r2, r0, 0

  /* r3 divide 4 which means rsh 2 bits */
  rsh r3, r3, adc_oversampling_factor_log
  /* averaged value is now in r3; store it into Sens_Vn1 */
  move r1, Sens_Vn1
  st r3, r1, 0

/* calculate differences */
    move r3, Sens_Vn1
    ld r3, r3, 0
    move r2, Sens_Vn0
    ld r2, r2, 0
    sub r3, r3, r2
    move r2, Sens_Diff_n1
    st r3,r2,0
    move r3, Sens_Vp1
    ld r3, r3, 0
    move r2, Sens_Vp0
    ld r2, r2, 0
    sub r3, r3, r2
    move r2, Sens_Diff_p1
    st r3,r2,0
    
/* wake up */
    ld r0,r2,0 # Sens_Diff_p1
   .global jmp_threshold
jmp_threshold:
    JUMPR wake_up, threshold_pos, GE

  /* Get ULP back to sleep */
  .global exit
exit:
  halt

  .global wake_up
wake_up:
  /* Check if the SoC can be woken up */
  READ_RTC_REG(RTC_CNTL_DIAG0_REG, 19, 1)
  and r0, r0, 1
  jump exit, eq

  /* Wake up the SoC and stop ULP program */
  wake
  /* Stop the wakeup timer so it does not restart ULP */
  WRITE_RTC_FIELD(RTC_CNTL_STATE0_REG, RTC_CNTL_ULP_CP_SLP_TIMER_EN, 0)
  halt
"""

binary = src_to_binary(source)

# Export section for Berry
code_b64 = ubinascii.b2a_base64(binary).decode('utf-8')[:-1]

file = open ("ulp_template.txt", "w")
file.write(code_b64)

print("")
# For convenience you can add Berry commands to rapidly test out the resulting ULP code in the console
print("#You can paste the following snippet into Tasmotas Berry console:")
print("import ULP")
print("ULP.wake_period(0,3000000)")
print("ULP.adc_config(0,2,3)") # adc1_config_channel_atten(ADC1_CHANNEL_0, ADC_ATTEN_DB_6);
print("ULP.adc_config(3,2,3)") # adc1_config_channel_atten(ADC1_CHANNEL_3, ADC_ATTEN_DB_6); + adc1_config_width(ADC_WIDTH_BIT_12);
print("var c = bytes().fromb64(\""+code_b64+"\")")
print("ULP.load(c)")
print("ULP.run()")
