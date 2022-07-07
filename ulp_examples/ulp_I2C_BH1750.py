"""
BH1750 example with exporting ULP code to Tasmotas Berry implementation
"""
from esp32_ulp import src_to_binary
import ubinascii

source = """

// needs database in ulp module !!

#include "soc/rtc_cntl_reg.h"
#include "soc/rtc_io_reg.h"
#include "soc/soc_ulp.h"
#include "stack.s"

.bss
i2c_started:
  .long 0
i2c_didInit:
  .long 0

.text
#.global jump_point
#jump_point:
#    jump entry

#include "soc/rtc_cntl_reg.h"
#include "soc/rtc_io_reg.h"
#include "soc/soc_ulp.h"
#include "stack.s"

.set BH1750_ADDR_W, 0x46
.set BH1750_ADDR_R, 0x47
.set BH1750_ON,0x01
.set BH1750_RSET,0x07
.set BH1750_ONE, 0x20
.set BH1750_ONE_LOW, 0x23

.bss
   .global sample_counter
sample_counter:
   .long 0
   .global result
result:
   .long 0
   .global stack
stack:
   .skip 100
   .global stackEnd
stackEnd:
   .long 0

.text
   .global entry
entry:
   move r3,stackEnd
   psr
   jump Task_BH1750
   move r1, sample_counter    /* Read sample counter */
   ld r0, r1, 0
   add r0, r0, 1              /* Increment */
   st r0, r1, 0               /* Save counter in memory */
   jumpr clear, 3, ge
   jump exit
clear:
   move r1, sample_counter
   ld r0, r1, 0
   .set zero, 0x00
    move r0, zero
   st r0, r1, 0
   jump wake_up
   /* value within range, end the program */
   .global exit
exit:
   halt

   .global wake_up
wake_up:
   /* Check if the system can be woken up */
   READ_RTC_REG(RTC_CNTL_DIAG0_REG, 19, 1)
   and r0, r0, 1
   jump exit, eq
   /* Wake up the SoC, end program */
   wake
   WRITE_RTC_FIELD(RTC_CNTL_STATE0_REG, RTC_CNTL_ULP_CP_SLP_TIMER_EN, 0)
   halt

.global Read_BH1750
Read_BH1750:
   move r1, BH1750_ADDR_R
   push r1
   psr
   jump i2c_start_cond          // i2c Start
   ld r2, r3, 4                 // Address+Read
   psr
   jump i2c_write_byte
   jumpr popfail, 1, ge
   pop r1
   move r2,0
   psr
   jump i2c_read_byte
   push r0
   move r2,1 // last byte
   psr
   jump i2c_read_byte
   push r0
   psr
   jump i2c_stop_cond
   pop r0 // Low-byte
   pop r2 // Hight-byte
   lsh r2,r2,8
   or r2,r2,r0
   move r0,r2
   move r1, result
   st r0, r1, 0
   move r2,0 // OK
   ret


.global Cmd_Write_BH1750
Cmd_Write_BH1750:
   psr
   jump i2c_start_cond           // i2c Start
   ld r2, r3, 12                 // Address+Write
   psr
   jump i2c_write_byte
   jumpr popfail,1,ge
   ld r2, r3, 8                  // Command
   psr
   jump i2c_write_byte
   jumpr popfail, 1, ge
   psr
   jump i2c_stop_cond            // i2c Stop
   ret

.global Start_BH1750
Start_BH1750:
   move r1, BH1750_ADDR_W
   push r1
   move r1, BH1750_ON
   push r1
   psr
   jump Cmd_Write_BH1750         // power on
   pop r1
   move r1, BH1750_ONE
   push r1
   psr
   jump Cmd_Write_BH1750         // once H
   pop r1
   pop r1
   ret

.global Task_BH1750
Task_BH1750:
   psr
   jump Start_BH1750
   move r2, 200                  // Wait 150ms
   psr
   jump waitMs
   psr
   jump Read_BH1750
   ret

popfail:
   pop r1                        // pop caller return address
   move r2,1
   ret

// Wait for r2 milliseconds
.global waitMs
waitMs:
   wait 8000
   sub r2,r2,1
   jump doneWaitMs,eq
   jump waitMs
doneWaitMs:
   ret
   
.global i2c_start_cond
.global i2c_stop_cond
.global i2c_write_bit
.global i2c_read_bit
.global i2c_write_byte
.global i2c_read_byte

.macro I2C_delay
  wait 50   // if number equ 10 then clock gap is minimal 4.7us
.endm

.macro read_SCL
  READ_RTC_REG(RTC_GPIO_IN_REG, RTC_GPIO_IN_NEXT_S + 9, 1)
.endm

.macro read_SDA
  READ_RTC_REG(RTC_GPIO_IN_REG, RTC_GPIO_IN_NEXT_S + 8, 1)
.endm

.macro set_SCL
  WRITE_RTC_REG(RTC_GPIO_ENABLE_W1TC_REG, RTC_GPIO_ENABLE_W1TC_S + 9, 1, 1)
.endm

.macro clear_SCL
  WRITE_RTC_REG(RTC_GPIO_ENABLE_W1TS_REG, RTC_GPIO_ENABLE_W1TS_S + 9, 1, 1)
.endm

.macro set_SDA
  WRITE_RTC_REG(RTC_GPIO_ENABLE_W1TC_REG, RTC_GPIO_ENABLE_W1TC_S + 8, 1, 1)
.endm

.macro clear_SDA
  WRITE_RTC_REG(RTC_GPIO_ENABLE_W1TS_REG, RTC_GPIO_ENABLE_W1TS_S + 8, 1, 1)
.endm


i2c_start_cond:
  move r1,i2c_didInit
  ld r0,r1,0
  jumpr didInit,1,ge
  move r0,1
  st r0,r1,0
  WRITE_RTC_REG(RTC_GPIO_OUT_REG, RTC_GPIO_OUT_DATA_S + 9, 1, 0)
  WRITE_RTC_REG(RTC_GPIO_OUT_REG, RTC_GPIO_OUT_DATA_S + 8, 1, 0)
didInit:
  move r2,i2c_started
  ld r0,r2,0
  jumpr not_started,1,lt  // if started, do a restart condition
  set_SDA         // set SDA to 1
  I2C_delay
  set_SCL
clock_stretch:        // TODO: Add timeout
  read_SCL
  jumpr clock_stretch,1,lt
  I2C_delay         // Repeated start setup time, minimum 4.7us
not_started:
  clear_SDA         // SCL is high, set SDA from 1 to 0.
  I2C_delay
  clear_SCL
  move r0,1
  st r0,r2,0
  ret
  
i2c_stop_cond:
  clear_SDA         // set SDA to 0
  I2C_delay
  set_SCL
clock_stretch_stop:
  read_SCL
  jumpr clock_stretch_stop,1,lt
  I2C_delay         // Stop bit setup time, minimum 4us
  set_SDA         // SCL is high, set SDA from 0 to 1
  I2C_delay
  move r2,i2c_started
  move r0,0
  st r0,r2,0
  ret
  
i2c_write_bit:         // Write a bit to I2C bus
  jumpr bit0,1,lt
  set_SDA
  jump bit1
bit0:
  clear_SDA
bit1:
  I2C_delay         // SDA change propagation delay
  set_SCL
  I2C_delay
clock_stretch_write:
  read_SCL
  jumpr clock_stretch_write,1,lt
  clear_SCL
  ret
  
i2c_read_bit:         // Read a bit from I2C bus
  set_SDA         // Let the slave drive data
  I2C_delay
  set_SCL
clock_stretch_read:
  read_SCL
  jumpr clock_stretch_read,1,lt
  I2C_delay
  read_SDA        // SCL is high, read out bit
  clear_SCL
  ret           // bit in r0
  
i2c_write_byte:       // Return 0 if ack by the slave.
  stage_rst
next_bit:
  and r0,r2,0x80
  psr
  jump i2c_write_bit
  lsh r2,r2,1
  stage_inc 1
  jumps next_bit,8,lt
  psr
  jump i2c_read_bit
  ret
  
i2c_read_byte:         // Read a byte from I2C bus
  push r2
  move r2,0
  stage_rst
next_bit_read:
  psr
  jump i2c_read_bit
  lsh r2,r2,1
  or r2,r2,r0
  stage_inc 1
  jumps next_bit_read,8,lt
  pop r0
  psr
  jump i2c_write_bit
  move r0,r2
  ret

.macro push rx
  st \rx,r3,0
  sub r3,r3,1
.endm

.macro pop rx
  add r3,r3,1
  ld \rx,r3,0
.endm

// Prepare subroutine jump
.macro psr
  .set addr,(.+16)
  move r1,addr
  push r1
.endm

// Return from subroutine
.macro ret
  pop r1
  jump r1
.endm
"""


global_label_counter = 0
macros = []


def replace_line(line, macro, args):
    section = ""
    print("Replace:")
    print(line)
    print("with Macro:")
    print(macro)
    global global_label_counter
    
    local_defines = []

    for macro_line in macro["text"]:
        macro_line = macro_line.rstrip()
        if "(." in macro_line:
            section += "macro_label"+str(global_label_counter)+":\n"
            macro_line = macro_line.replace("(.","(macro_label"+str(global_label_counter)).replace(")","/4)")
            global_label_counter += 1
            
        if ".set" in macro_line:
  
            definition = macro_line.split(" ")[-1].split(",")
            print("$$$$$ Found local define:",local_defines,macro_line,macro_line.split(" "))
            local_defines.append(definition)
            print("Definition:")
            print(definition)
            continue
        tokens = macro_line.split(" ")
        for local_define in local_defines:
            print("%%%%",local_define,macro_line)
            macro_line = macro_line.replace(local_define[0],local_define[1])

        arg_index = 0
        for arg in macro["args"]:
            print(macro_line.strip("\r"))
            macro_line = macro_line.rstrip().replace('\r','#r') # CR -> face palm
            macro_line = macro_line.replace("#"+arg,args[arg_index]).replace("\\"+arg,args[arg_index])
            
            arg_index += 1
        
        print("######",macro_line)
        next_macro, next_args = check_for_macro(macro_line.replace('\t',''))
        print(next_macro, next_args)
        while next_macro != "":
            print("Next Macro")
            print(next_macro, next_args,macro_line)
            macro_line = replace_line(macro_line, next_macro, next_args)
            print(macro_line)
            next_macro, next_args = check_for_macro(macro_line)

        section += macro_line + "\n"
        
        
    return section
        
        
def check_for_macro(line):
    tokens = line.split(" ")
    print("Tokens:",tokens)
    for macro in macros:
        if macro["name"] in tokens:
            index = tokens.index(macro["name"])
            args = tokens[index+1:]
            if len(args) == len(macro["args"]):
#                line = replace_line(line,macro,args)
                return macro,args
            else:
                print("Wrong number of args")
                return macro,args
    
    return "", []

def expand_macro(source):
    new_source = ""
    for line in source.split("\n"):
        tokens = line.split(" ")
        print(tokens)
        macro, args = check_for_macro(line)
        if macro != "":
            line = replace_line(line,macro,args)

        new_source += line+"\n"
    return new_source
                

def find_macros(source):
    new_source = ""
    found_macro = False
    line_number = 0
    for line in source.split("\n"):
        line_number += 1
        if line.startswith(".macro"):
            found_macro = True
            first_line = line.split(" ")
            new_macro = {}
            new_macro["name"] = first_line[1]
            new_macro["args"] = []
            new_macro["const"] = []
            new_macro["text"] = []
            for el in first_line[2:]:
                if "=" in el:
                    new_macro["const"].append(el)
                else:
                    new_macro["args"].append(el)
        elif found_macro:
            if line.startswith(".endm"):
                macros.append(new_macro)
                found_macro = False
            else:
                for const in  new_macro["const"]:
                    line = line.replace("\\"+const.split("=")[0],const.split("=")[1])
                new_macro["text"].append(line)
        else:
            if len(line):
                new_source += line+"\n"
    return new_source

#print(macros)
#print(new_source)


# print(new_source)
new_source = find_macros(source)
print("######## Macros: ######")
print(macros)
new_source = expand_macro(new_source)
print(new_source)
print(new_source)


binary = src_to_binary(new_source)

# Export section for Berry
code_b64 = ubinascii.b2a_base64(binary).decode('utf-8')[:-1]

file = open ("ulp_template.txt", "w")
file.write(code_b64)

print("")
# For convenience you can add Berry commands to rapidly test out the resulting ULP code in the console
print("#You can paste the following snippet into Tasmotas Berry console:")
print("import ULP")
print("ULP.wake_period(0,3 * 1000 * 1000)")
print("ULP.gpio_init(32,0)")
print("ULP.gpio_init(33,0)")
print("var c = bytes().fromb64(\""+code_b64+"\")")
print("ULP.load(c)")
print("ULP.run()")

