# helper script to export ULP code from an ESP-IDF project to Tasmotas Berry
#
# usage: launch "python3 binS2Berry.py" in root folder of the project


from os import listdir
from os import path
from os.path import join
import sys
import re

def get_files():
    if not path.exists('build'):
        print("Please start script in valid ESP_IDF project folder with completed build!")
        return {}
    files = listdir('build')
    if len(files) == 0:
        print("Empty build folder, this should never happen!!")
        return {}
    asm = ""
    map = ""
    for file in files:
        if "bin.S" in file:
            asm = join("build",file)
        if ".map" in file:
                map = join("build",file)
    return asm, map

def parse_map_file(map_file):
    print("Parsing map file ...")
    global_vars = []
    with open(map_file, 'r', encoding='UTF-8') as file:
        while (line := file.readline()):
            if "PROVIDE (ulp_" in line:
                    m = line[line.find('(')+1:line.find(')')]
                    global_vars.append(m)
    return global_vars


def parse_asm_file(asm_file):
    print("Parsing asm file ...")
    code = ""
    size_in_file = 0
    with open(asm_file, 'r', encoding='UTF-8') as file:
        while (line := file.readline()):
            if line.startswith(".byte") or line.startswith("0x"):
                hexstring = line.replace(".byte ","").replace(", ","").replace("0x","")
    #            print(hexstring)
                code += hexstring.rstrip().replace("\n","")
            if line.startswith(".word"):
                tokens = line.split(" ")
                size_in_file = int(tokens[1])
            
    code_size = int(len(code)/2)
    if code_size != size_in_file:
        print("Parsing error!")
        print("Mismatch of size in file:",size_in_file," vs parsed size:", code_size)
    if code_size%4 != 0:
        print("Parsing error!")
        print("No long word alignement.")
    return code, code_size
    
def print_output(code,code_size,global_vars):
    print("### Global vars (including function labels):")
    for var in global_vars:
        rtc_addr = int((int(var.split(" ")[-1],0)-0x50000000)/4)
        if rtc_addr == 0:
            print("!!! Make sure, that the next line is a jump to the global entry point or the entry point itself !!!")
        var = var.replace("ulp_","")
        print("#",var," -> ULP.get_mem(",rtc_addr,")")
    print("")
    print("#You can paste the following snippet into Tasmotas Berry console:")
    print("import ULP")
    print("ULP.wake_period(0,1000 * 1000)")
    print("ULP.gpio_init(32,0)")
    print("ULP.gpio_init(33,0)")
    print("c = bytes(\""+code+"\")")
    print("# Length in bytes:",code_size)
    
    if code_size > 255:
        function = """
        # Code size too big for standard settting, you can try this hack.
        # Do never open an issue about it, this is only a walkaround while  developing!
        def ulp_save(b)
          import ULP
          var idx = b.get(4, 2)        # TEXT_OFFSET (bytes)
          var last = idx + b.get(6, 2) + b.get(8,2)    # TEXT_SIZE (bytes) + DATA_SIZE (bytes)
          var addr = 0
          while idx < last
              print("addr",addr,"idx",idx,"last",last)
            ULP.set_mem(addr, b.get(idx, 4))
            addr += 1
            idx += 4
          end
        end
        """
        print(function)
    else:
        print("ULP.load(c)")
    
    print("ULP.run()")

def main(args):
    print("Parsing /build folder ...")
    asm_file, map_file = get_files()
    print(asm_file, map_file)
    code, code_size = parse_asm_file(asm_file)
    global_vars = parse_map_file(map_file)
    print_output(code, code_size, global_vars)


if __name__ == '__main__':
  sys.exit(main(sys.argv))
# end if
