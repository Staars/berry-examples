"""
Template for exporting ULP code to Tasmotas Berry implementation
"""
from esp32_ulp import src_to_binary

source = """
# replace this multiline string with the content of an .S file

# included header files will not work, but you will find missing defines there and can insert the missing lines here manually
# look for the console output of `micropython thisfile.py` to see, where you find the vars from Berry, i.e. 0001 my_var -> ULP.get_mem(1)

# !!! YOU MUST PLACE A JUMP TO THE ENTRY POINT AT THE FIRST POSITION IN THE .text SECTION !!!


    jump entry      # must be the first command !!
    
.global my_var
my_var: .long 0     # global var in .text section, which is default section if not declared otherwise

.global entry       # typical entry point declaration, but we always jump to this point from address 0 in Tasmota!!
entry:
    halt            # stop ULP program
"""

binary = src_to_binary(source)

# Export section for Berry
code  = ""
for l in binary:
    l = hex(l)
    if(len(l)<4):
        l = "0x0" + l[-1]
    code += l[2:]
print(code)

file = open ("ulp_template.txt", "w")
file.write(code)

print("")
# For convenience you can add Berry commands to rapidly test out the resulting ULP code in the console
# This could also be used in an init function of a Tasmota driver
print("#You can paste the following snippet into Tasmotas Berry console:")
print("import ULP")
print("ULP.wake_period(0,500000)")
print("var c = bytes(\""+code+"\")")
print("ULP.load(c)")
print("ULP.run()")
