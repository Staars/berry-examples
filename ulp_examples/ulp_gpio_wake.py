

"""
GPIO-Wakeup-Example with exporting ULP code to Tasmotas Berry implementation
"""
from esp32_ulp import src_to_binary
import ubinascii

source = """\
# constants from:
# https://github.com/espressif/esp-idf/blob/1cb31e5/components/soc/esp32/include/soc/soc.h
#define DR_REG_RTCIO_BASE            0x3ff48400
#define DR_REG_RTCCNTL_BASE          0x3ff48000

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
#define RTC_GPIO_IN_REG          (DR_REG_RTCIO_BASE + 0x24)
#define RTC_GPIO_IN_NEXT_S  14
#define RTC_CNTL_LOW_POWER_ST_REG          (DR_REG_RTCCNTL_BASE + 0xc0)
#define RTC_CNTL_RDY_FOR_WAKEUP  (BIT(19))
#define RTC_CNTL_RDY_FOR_WAKEUP_M  (BIT(19))
#define RTC_CNTL_RDY_FOR_WAKEUP_V  0x1

# constants from:
# https://github.com/espressif/esp-idf/blob/1cb31e5/components/soc/esp32/include/soc/rtc_io_channel.h
#define RTCIO_GPIO2_CHANNEL          12

    /* Define variables, which go into .bss section (zero-initialized data) */
    .bss
    /* Next input signal edge expected: 0 (negative) or 1 (positive) */
    .global next_edge
next_edge:
    .long 0

    /* Counter started when signal value changes.
       Edge is "debounced" when the counter reaches zero. */
    .global debounce_counter
debounce_counter:
    .long 0

    /* Value to which debounce_counter gets reset.
       Set by the main program. */
    .global debounce_max_count
debounce_max_count:
    .long 0

    /* Total number of signal edges acquired */
    .global edge_count
edge_count:
    .long 0

    /* Number of edges to acquire before waking up the SoC.
       Set by the main program. */
    .global edge_count_to_wake_up
edge_count_to_wake_up:
    .long 0

    /* RTC IO number used to sample the input signal.
       Set by main program. */
    .global io_number
io_number:
    .long 0

    /* Code goes into .text section */
    .text
    .global entry
entry:
    /* Load io_number */
    move r3, io_number
    ld r3, r3, 0

    /* Lower 16 IOs and higher need to be handled separately,
     * because r0-r3 registers are 16 bit wide.
     * Check which IO this is.
     */
    move r0, r3
    jumpr read_io_high, 16, ge

    /* Read the value of lower 16 RTC IOs into R0 */
    READ_RTC_REG(RTC_GPIO_IN_REG, RTC_GPIO_IN_NEXT_S, 16)
    rsh r0, r0, r3
    jump read_done

    /* Read the value of RTC IOs 16-17, into R0 */
read_io_high:
    READ_RTC_REG(RTC_GPIO_IN_REG, RTC_GPIO_IN_NEXT_S + 16, 2)
    sub r3, r3, 16
    rsh r0, r0, r3

read_done:
    and r0, r0, 1
    /* State of input changed? */
    move r3, next_edge
    ld r3, r3, 0
    add r3, r0, r3
    and r3, r3, 1
    jump changed, eq
    /* Not changed */
    /* Reset debounce_counter to debounce_max_count */
    move r3, debounce_max_count
    move r2, debounce_counter
    ld r3, r3, 0
    st r3, r2, 0
    /* End program */
    halt

    .global changed
changed:
    /* Input state changed */
    /* Has debounce_counter reached zero? */
    move r3, debounce_counter
    ld r2, r3, 0
    add r2, r2, 0 /* dummy ADD to use "jump if ALU result is zero" */
    jump edge_detected, eq
    /* Not yet. Decrement debounce_counter */
    sub r2, r2, 1
    st r2, r3, 0
    /* End program */
    halt

    .global edge_detected
edge_detected:
    /* Reset debounce_counter to debounce_max_count */
    move r3, debounce_max_count
    move r2, debounce_counter
    ld r3, r3, 0
    st r3, r2, 0
    /* Flip next_edge */
    move r3, next_edge
    ld r2, r3, 0
    add r2, r2, 1
    and r2, r2, 1
    st r2, r3, 0
    /* Increment edge_count */
    move r3, edge_count
    ld r2, r3, 0
    add r2, r2, 1
    st r2, r3, 0
    /* Compare edge_count to edge_count_to_wake_up */
    move r3, edge_count_to_wake_up
    ld r3, r3, 0
    sub r3, r3, r2
    jump wake_up, eq
    /* Not yet. End program */
    halt

    .global wake_up
wake_up:
    /* Check if the system can be woken up */
    READ_RTC_FIELD(RTC_CNTL_LOW_POWER_ST_REG, RTC_CNTL_RDY_FOR_WAKEUP)
    and r0, r0, 1
    jump wake_up, eq

    /* Wake up the SoC, end program */
    wake
    halt

"""

binary = src_to_binary(source)

# Export section for Berry
code_b64 = ubinascii.b2a_base64(binary).decode('utf-8')[:-1]

print("")
print("#You can paste the following snippet into Tasmotas Berry console:")
print("import ULP")
print("ULP.wake_period(0,20000)")
print("var io_num = ULP.gpio_init(0,0) # GPIO 0 to input ")
print("var c = bytes().fromb64(\""+code_b64+"\")")
print("ULP.load(c)")
print("ULP.set_mem(55,3) #edge_count_to_wake_up")
print("ULP.set_mem(56,io_num) #rtc_gpio_number")
print("ULP.run()")
