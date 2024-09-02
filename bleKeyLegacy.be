#######################################################################
# BLE legacy bind key generator for ESP32 - ESP32C3 - ESP32S3
#
# use : `import keyGenLeg`
#
# Provides BLE bindings and a Web UI
#######################################################################

var keyGenLeg = module('keyGenLeg')


# List of PRODUCT_ID:
#   339: For 'YLYK01YL'
#   950: For 'YLKG07YL/YLKG08YL'
#   959: For 'YLYB01YL-BHFRC'
#   1254: For 'YLYK01YL-VENFAN'
#   1678: For 'YLYK01YL-FANCL'
#


#################################################################################
# Globals
#################################################################################
import math
import BLE

UUID_SERVICE = "fe95"
UUID_AUTH = '0001'
UUID_FIRMWARE_VERSION = '0004'
UUID_AUTH_INIT = '0010'
UUID_BEACON_KEY = '0014'


MI_KEY1 = bytes('90CA85DE')
MI_KEY2 = bytes('92AB54FA')
PID = 950

buf = bytes(-64)

#################################################################################
# BLE_keyGenLeg_UI
#
# WebUI for the legacy bind key generator
#################################################################################
class BLE_keyGenLeg_UI

    var token, rev_MAC, MAC, fw_version
    var current_func, next_func
    var msg, key, shallSendKey

    def reverseMac(mac)
        var reMAC = bytes(-6)
        for i:0..5
            reMAC[i] = mac[5-i]
        end
        return reMAC
    end

    def mixBase(mac)
        var buf = bytes(-8)
        buf[0] = mac[0]
        buf[1] = mac[2]
        buf[2] = mac[5]
        return buf
    end

    def mixA(mac,PID)
        var buf = self.mixBase(mac)
        buf[3] = PID & 0xff
        buf[4] = PID & 0xff
        buf[5] = mac[4]
        buf[6] = mac[5]
        buf[7] = mac[1]
        return buf
    end

    def mixB(mac,PID)
        var buf = self.mixBase(mac)
        buf[3] = (PID >> 8) & 0xff
        buf[4] = mac[4]
        buf[5] = mac[0]
        buf[6] = mac[5]
        buf[7] = PID & 0xff
        return buf
    end

    def cipherInit(key)
        var perm = bytes(-256)
        for i:0..255
            perm[i] = i & 0xff
        end
        var keyLen = size(key)
        var j = 0
        for i:0..255
            j += perm[i] + key[i % keyLen]
            j = j & 0xff
            var temp = perm[i]
            perm[i] = perm[j]
            perm[j] = temp
        end
        return perm
    end

    def cipherCrypt(inp, perm)
        var index1 = 0
        var index2 = 0
        var _size = size(inp)

        var output = bytes(-_size)
        for i:0.._size-1
            index1 += 1
            index1 = index1 & 0xff
            index2 += perm[index1]
            index2 = index2 & 0xff
            var temp = perm[index1]
            perm[index1] = perm[index2]
            perm[index2] = temp
            var idx = perm[index1] + perm[index2]
            idx = idx & 0xff
            var outputByte = inp[i] ^ perm[idx]
            output[i] = outputByte & 0xff
        end
        return output
    end

    def cipher(key, inp)
        var _perm = self.cipherInit(key)
        return self.cipherCrypt(inp, _perm)
    end
    
    def generateRandomToken()
        var token = bytes(-12)
        for i:0..11
            token[i] = math.rand()%255
        end
        return token
    end

    def init()
        var cbp = cb.gen_cb(/e,o,u,h->self.cb(e,o,u,h))
        BLE.conn_cb(cbp,buf)
        self.current_func = self.wait
        self.msg = ""
        self.key = ""
        self.shallSendKey=false
    end

    def log(msg)
        print(msg)
        if self.msg==''
            self.msg=msg
        else
            self.msg+="\\n"
            self.msg+=msg
        end
    end

    def every_second()
        self.current_func()
    end

    def wait()
        # do nothing
    end

    def then(func)
        # save function pointers for callback
        self.next_func = func
        self.current_func = self.wait
    end
    
    def pair(MAC)
        self.MAC = MAC
        self.token = self.generateRandomToken()
        self.log(format("Generated random token: %s",str(self.token)))
        self.rev_MAC = self.reverseMac(bytes(MAC))
        self.log(format("Try to connect to: %s",MAC))
        self.log("Long press pair button, LED should blink shortly!")
        BLE.set_MAC(bytes(MAC),0)
        BLE.set_svc(UUID_SERVICE,true)
        BLE.run(7,true)
        self.then(/->self.authInit())
    end

    def cb(error,op,uuid,handle)
        print("BLE Op:",op,"UUID:",uuid)
        if error == 0
            if op == 103
                print("Got notification...")
                self.current_func = /->self.func4()
                return
            end
            self.current_func = self.next_func # fulfil our promise ;)
            return
        else
            print(error,op,uuid,handle)
        end
        if op == 5
            self.log("Did successfully disconnect.")
        elif error < 3
            self.log("BLE error, did disconnect!")
        elif error > 2
            self.log("BLE error, will disconnect!")
            BLE.run(5) # disconnect
        end
    end

    def authInit()
        import BLE
        BLE.set_chr(UUID_AUTH_INIT)
        buf.setbytes(1,MI_KEY1)
        buf[0] = size(MI_KEY1)
        BLE.run(2,true)
        self.then(/->self.subscribeAuth())
    end

    def subscribeAuth()
        self.log("Did connect, subscribe to UUID_AUTH")
        BLE.set_chr(UUID_AUTH)
        BLE.run(3,true)
        self.then(/->self.writeMixToAuth())
    end
    def writeMixToAuth()
        self.log("Write to UUID_AUTH")
        # self.current_func = self.wait
        BLE.set_chr(UUID_AUTH)
        var _mixA = self.mixA(self.rev_MAC,PID)
        var _buf = self.cipher(_mixA,self.token)
        buf.setbytes(1,_buf)
        buf[0] = size(_buf)
        BLE.run(2,true)
        self.next_func = self.wait
    end
    # virtual func3 is just waiting for the notification in the cb
    def func4()
        BLE.set_chr(UUID_AUTH)
        var _buf = self.cipher(self.token, MI_KEY2)
        print(_buf)
        buf.setbytes(1,_buf)
        buf[0] = size(_buf)
        print("size:", buf[0])
        BLE.run(2,true)
        self.then(/->self.readFW())
    end
    def readFW()
        self.log("Will read FW version")
        BLE.set_chr(UUID_FIRMWARE_VERSION)
        BLE.run(1)
        self.then(/->self.readKey())
    end
    def readKey()
        self.log("Got FW version, will read key")
        self.fw_version = self.cipher(self.token, buf[1..buf[0]]).asstring()
        self.log(self.fw_version)
        BLE.set_chr(UUID_BEACON_KEY)
        BLE.run(1)
        self.then(/->self.receiveKey())
    end
    def receiveKey()
        import string
        print("Got key with length:", buf[0])
        var key = self.cipher(self.token, buf[1..buf[0]])
        self.key = string.split(str(key),"'")[1]
        self.log(format("Bind Key: %s", self.key))
        if int(self.fw_version) == 1
            self.log("Old firmware type ... will convert key to:")
            var _s = string.split(self.key,12)
            self.key = _s[0] + "8D3D3C97" + _s[1]
        else
            self.log("New firmware typee ... will convert key to:")
            self.key += "FFFFFFFF"
        end
        self.log(self.key)
        self.log("Success!! Will disconnect sensor.")
        self.shallSendKey = true;
        BLE.run(5)
        self.then(/->self.addKeyToSensor())
    end
    def addKeyToSensor()
        var keyMAC = self.key + self.MAC
        tasmota.cmd("mi32key "+keyMAC)
        self.then(/->self.wait())
    end

    def saveCfg()
        tasmota.cmd("mi32cfg")
    end

 
  # create a method for adding a button to the console menu
  # the button 'BLE scan' redirects to '/ble_key_l?'
  def web_add_button()
    import webserver
    webserver.content_send(
      "<form id=but_ble_key_l style='display: block;' action='ble_key_l' method='get'><button>BLE Key Gen legacy</button></form>")
  end
  
  #######################################################################
  # Display the compatible devices
  #######################################################################
  
  def show_devices()
    import webserver
    import string
    import MI32
    webserver.content_send("<p>Compatible devices:<p><select name='sensors' id='sens'>")
    var num = MI32.devices()-1
    for i:0..num
        if MI32.get_name(i) == "YLKG08"
            var mac = MI32.get_MAC(i)
            var mac_str = string.split(str(mac),"'")[1]
            webserver.content_send(format("<option value=%s>YLKG08 - MAC: %s</option>",mac_str,mac_str))
            self.log(format("Found YLKG08 with MAC: %s",mac_str))
        end
    end
    webserver.content_send("</select><br><br>")
    if num>0
        webserver.content_send("<button onclick='pair()'>Generate Key</button><br>")
    end

  end
  
  #######################################################################
  # Upload javascript
  #######################################################################
  
  def upl_js()
    import webserver
    var script_start = "<script>function update(cmnd){if(!cmnd){cmnd='loop=1'}var xr=new XMLHttpRequest();xr.onreadystatechange=()=>{if(xr.readyState==4&&xr.status==200){"
                       "var cr=xr.response.replace(/bytes\\(\\'([^']+)\\'\\)/g,'$1'); const r=JSON.parse(cr);if('LOG' in r){let l=eb('log');l.value+=r.LOG+'\\n';l.scrollTop=l.scrollHeight;}else if('KEY' in r){eb('key').innerHTML='Key: '+r.KEY}"
                       "};};xr.open('GET','/ble_key_l?'+cmnd,true);xr.send();};setInterval(update,250);"
    var script_1     = "function save(){update('save=1');}"
                       "function pair(){update('pair='+eb('sens').value);eb('log').value+='Start pairing with: '+eb('sens').value+'\\n';}"
    var script_2     = "</script>"
                        # str.replace(/bytes\(\'([^']+)\'\)/g,"$1")

     webserver.content_send(script_start)
     webserver.content_send(script_1)
     webserver.content_send(script_2)
  end

  #######################################################################
  # Display the complete page
  #######################################################################
  def page_ble_key_l()
    import webserver
    import string
    import json

    if !webserver.check_privileged_access() return nil end
    
    # AJAX response
    if webserver.has_arg("loop")
        if self.shallSendKey==true
            self.shallSendKey=false
            webserver.content_response(format("{\"KEY\":\"%s\"}",self.key))
            return
        end
        if self.msg==''
            webserver.content_response("{\"OK\":[]}")
        else
            webserver.content_response(format("{\"LOG\":\"%s\"}",self.msg))
            self.msg=''
        end
        return
    elif webserver.has_arg("pair")
        webserver.content_response("{\"OK\":[]}")
        var mac = webserver.arg("pair")
        self.log("Connect requested from WebGUI.")
        self.pair(mac)
        return
    elif webserver.has_arg("save")
        webserver.content_response("{\"OK\":[]}")
        self.saveCfg()
        self.shallSendKey=false
        self.log("Saving mi32cfg.")
        return
    end

    # regular web page
    webserver.content_start("BLE legacy key generator")       #- title of the web page -#
    webserver.content_send_style()            #- send standard Tasmota styles -#

    webserver.content_send("<style>.parent{display:flex;flex-flow:row wrap;}.parent > *{flex: 1 100%;}tr:nth-child(even){background-color: #f2f2f230;}.box {margin: 5px;padding: 5px;border-radius: 0.8rem;background-color: rgba(221, 221, 221, 0.2);}@media all and (min-width: 600px){.side{flex:1 auto;}}@media all and (min-width:800px){.main{flex:3 0px;}.side-1{order:1;}.main{order:2;}.side-2{order:3;}.footer{order: 4;}}</style>")

    self.upl_js()                             #- send own JS -#

    webserver.content_send("<div class='parent'><header class='box'><h2> BLE legacy key generator / MI32</h2><p style='text-align:right;'>... powered by BERRY</p></header>")
    webserver.content_send("<div class='box side side-1'>Using only sensors visible to the MI32 driver.<br>Check your 'mi32cfg' or<br>enable scanning for new sensors<br>with 'mi32option3 0'.")
    self.show_devices()
    webserver.content_send("</div>")
    webserver.content_send(
      "<div class='box side side-2'><p id='key'></p><br><button onclick='save()'>Save to mi32cfg</button></div>") #- close .box-# 
    webserver.content_send("<div class='large box main'><h3>Log:</h3><textarea id='log' style='min-width:600px'>Waiting for driver ...\n</textarea>")
    webserver.content_send("</div><br>")

    webserver.content_send("<p></p></div><br>")        #- close .parent div-#

    webserver.content_button(webserver.BUTTON_MANAGEMENT) #- button back to management page -#
    webserver.content_stop()                        #- end of web page -#
  end

  #######################################################################
  # Web Controller, called by POST to `/ble_key_l`
  #######################################################################
  def page_ble_key_l_ctl()
    import webserver
    import string
    if !webserver.check_privileged_access() return nil end

    try
      #---------------------------------------------------------------------#
      # To do.
      #---------------------------------------------------------------------#
      if webserver.has_arg("ble_key_l")
        print("key generator")
        self.page_ble_key_l()
      else
        raise "value_error", "Unknown command"
      end
    except .. as e, m
      print(format("BRY: Exception> '%s' - %s", e, m))
      #- display error page -#
      webserver.content_start("Parameter error")      #- title of the web page -#
      webserver.content_send_style()                  #- send standard Tasmota styles -#

      webserver.content_send(format("<p style='width:340px;'><b>Exception:</b><br>'%s'<br>%s</p>", e, m))

      webserver.content_button(webserver.BUTTON_MANAGEMENT) #- button back to management page -#
      webserver.content_send("<p></p>")
      webserver.content_stop()                        #- end of web page -#
    end
  end

  #- ---------------------------------------------------------------------- -#
  # respond to web_add_handler() event to register web listeners
  #- ---------------------------------------------------------------------- -#
  #- this is called at Tasmota start-up, as soon as Wifi/Eth is up and web server running -#
  def web_add_handler()
    import webserver
    #- we need to register a closure, not just a function, that captures the current instance -#
    webserver.on("/ble_key_l", / -> self.page_ble_key_l(), webserver.HTTP_GET)
    webserver.on("/ble_key_l", / -> self.page_ble_key_l_ctl(), webserver.HTTP_POST)
  end
end

keyGenLeg.BLE_keyGenLeg_UI = BLE_keyGenLeg_UI


#- create and register driver in Tasmota -#
if tasmota
  var BLE_keyGenLeg_UI = keyGenLeg.BLE_keyGenLeg_UI()
  tasmota.add_driver(BLE_keyGenLeg_UI)
  ## can be removed if put in 'autoexec.bat'
  BLE_keyGenLeg_UI.web_add_handler()
  def pair(cmd, idx, payload, payload_json)
    BLE_keyGenLeg_UI.pair(payload)
    return true
  end
  tasmota.add_cmd('pair', pair) # MAC of the dimmer
end

return keyGenLeg

#- Example

import keyGenLeg

-#
