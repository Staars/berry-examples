#######################################################################
# MI bind key generator for ESP32 - ESP32C3 - ESP32S3
#
# use : `import keyGen`
#
# Provides BLE bindings and a Web UI
#######################################################################

var keyGen = module('keyGen')

#################################################################################
# mi helper class
#################################################################################
class MI32_Extended : MI32
    static svc = "fe95"
    static UPNP = '0010' # protocol identifier names
    static AVDTP = '0019'

    static CMD_GET_INFO = bytes("a2000000")
    static CMD_SET_KEY = bytes("15000000")
    static CMD_LOGIN = bytes("24000000")
    static CMD_AUTH = bytes("13000000")
    
    static CMD_SEND_DATA = bytes("000000030400")
    static CMD_SEND_DID = bytes("000000000200")
    static CMD_SEND_KEY = bytes("0000000b0100")
    static CMD_SEND_INFO = bytes("0000000a0200")
    
    static RCV_RDY = bytes("00000101")
    static RCV_OK = bytes("00000100")
    static RCV_TOUT = bytes("000001050100")
    static RCV_ERR = bytes("000001050300")

    static INIT = -1
    static RECV_INFO = 0
    static SEND_KEY = 1
    static RECV_KEY = 2
    static SEND_DID = 3
    static CONFIRM = 4
    static COMM = 5


    var state

    def supported(name)
        if  name == "LYWSD03" || name == "MHOC401"
            return true
        end
        return false
    end

    def addKey()
        var keyMAC = self.key + self.MAC
        tasmota.cmd("mi32key "+keyMAC)
    end

    def saveCfg()
        tasmota.cmd("mi32cfg")
    end

end

#################################################################################
# Globals
#################################################################################

ble = BLE()
mi = MI32_Extended()

#################################################################################
# MI32_keyGen_UI
#
# WebUI for the bind key generator
#################################################################################
class MI32_keyGen_UI

    var token, rev_MAC, MAC
    var current_func, next_func
    var msg, ownKey, shallSendKey
    var receive_frames, received_data, send_data, remote_info, remote_key, did_ct
    var buf, webCmd
    var log_reader, log_level
    var chunks, chunkIdx

    def copyBufToPos(target,pos,source)
        for i:0..size(source)-1
            target[pos+i] = source[i]
        end
    end

    def reverseMac(mac)
        var reMAC = bytes(-6)
        for i:0..5
            reMAC[i] = mac[5-i]
        end
        return reMAC
    end

    def sendData(data,chr)
        ble.set_svc(mi.svc)
        ble.set_chr(chr)
        self.buf[0] = size(data)
        self.copyBufToPos(self.buf,1,data)
        return ble.run(2,0)
    end

    def subscribe(chr)
        ble.set_svc(mi.svc)
        ble.set_chr(chr)
        print("Subscribe to: ",chr)
        return ble.run(3,1)
    end

    def init()
        var cbp = tasmota.gen_cb(/e,o,u->self.cb(e,o,u))
        self.buf = bytes(-64)
        ble.conn_cb(cbp,self.buf)
        self.current_func = self.wait
        self.ownKey = ""
        self.shallSendKey=false
        self.log_reader = tasmota_log_reader()
        self.log_level = 2
        var line = self.log_reader.get_log(self.log_level)
        while line != nil
            line = self.log_reader.get_log(self.log_level)
        end  # purge log
    end

    def call_JS_func(cmd,args)
        import string
        if args == nil
            args = ""
        end
        var _args = string.format("[\"%s\"]",args)
        self.webCmd = string.format("{\"CMD\":[\"%s\",%s]}",cmd,_args) # cmd is a JS function name with args as an array
    end

    def every_50ms()
    # def every_second()
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
        import string
        self.MAC = MAC
        self.rev_MAC = self.reverseMac(bytes(MAC))
        print("Try to connect to: ",MAC)
        ble.set_MAC(bytes(MAC),0)
        mi.state = mi.INIT
        self.call_JS_func("genOwnKey")
        self.then(/->self.func1())
        self.subscribe(mi.UPNP)
    end
    def func1()
        print("Did connect ...")
        self.then(/->self.getInfo())
        self.subscribe(mi.AVDTP)  
    end

    def sendChunks()
        import string
        if self.chunks>self.chunkIdx
            var from = 2+(self.chunkIdx*18)
            var to = 2+(self.chunkIdx*18)+18
            if self.lastChunk!=0 && self.chunkIdx == self.chunks-1
                to = 2+(self.chunkIdx*18)+self.lastChunk
            end
            var chunk = self.buf[from..to]
            var idx = string(self.chunkIdx+1)
            var packet = bytes(idx+"00")+chunk
            self.chunkIdx+=1
            self.then(/->self.sendChunks())
            self.sendData(packet,mi.AVDTP)
        else
            self.then(/->self.wait())
        end
    end

    def write_parcel(ch, data)
        var chunk_size=18
        var length = size(self.received_data)
        self.chunks = length/chunk_size
        self.lastChunk = length-self.chunks*chunk_size
        if self.lastChunk!=0
            self.chunks+=1
        end
        self.chunkIdx = 0
        self.sendChunks()
    end

    def confirm_handler(frm)
        if frm == 0x11
            print("Mi authentication successful!")
        elif frm == 0x12
            print("Mi authentication failed!")
        elif frm == 0x21
            print("Mi login successful!")
        elif frm == 0x23
            print("Mi login failed!")
        else
            print("Mi unknown response...")
        end
    end

    def getFrm()
        var frm = self.buf[1]
        if self.buf[0] > 2
            frm += 0x100*self.buf[2]
        end
        print("Frame :",frm)
        return frm
    end
    
    def handleRec()
        print("Received data from sensor.")
        var frm = self.getFrm()
        if frm == 0
            self.receive_frames = self.buf.geti(5,2)
            print("Expecting frames:",self.receive_frames)
            self.received_data = bytes('')
            self.current_func = /->self.recReady()
        else
            self.received_data += self.buf[3..self.buf[0]] #data[2:]
            print(self.received_data)
            self.current_func = /->self.wait()
        end
        if frm == self.receive_frames
            self.current_func = /->self.recOK()
            mi.state+=1
            print("Next state:",mi.state)
        end
    end

    def handleSend()
        print("Will send data to sensor.")
        var frm = self.getFrm()
        if frm != 0
            return
        end
        if self.buf[3..self.buf[0]] == mi.RCV_RDY
            print("Mi ready to receive key")
            self.ble.write_parcel(mi.AVDTP, self.send_data)
        elif self.buf[3..self.buf[0]] == mi.RCV_TOUT
            print("Mi sent RCV timeout.")
        elif self.buf[3..self.buf[0]] == mi.RCV_ERR
            print("Mi sent some RCV error?")
        elif self.buf[3..self.buf[0]] == mi.RCV_OK
            print("Mi confirmed key receive")
            mi.state+=1
            print("Next state:",mi.state)
        end
    end

    def handleCOMM()
        print("Pairing complete!!") # not implemented yet
    end

    def handleNotif()
        if mi.state == mi.RECV_INFO || mi.state == mi.RECV_KEY
            self.current_func = /->self.handleRec()
        end
        if mi.state == mi.SEND_KEY mi.state == mi.SEND_DID
            self.current_func = /->self.handleSend()
        end
        if mi.state == mi.CONFIRM
            self.current_func = /->self.handleConfirm()
        end
        if mi.state == mi.COMM
            self.current_func = /->self.handleCOMM()
        end
    end

    def cb(error,op,uuid)
        import string
        # print("BLE Op:",op,"UUID:",uuid)
        if error == 0
            if op == 103
                self.handleNotif()
                return
            else
                self.current_func = self.next_func # fulfil our promise ;)
            end
            return
        end
        if op == 5
            print("Did successfully disconnect.")
        elif error < 3
            print("BLE error, did disconnect!")
        elif error > 2
            print("BLE error, will disconnect!")
            ble.run(5) # disconnect
        end
    end

    def getInfo()
        print("Ask sensor for info ...")
        mi.state = mi.RECV_INFO
        self.then(/->self.wait())
        self.sendData(mi.CMD_GET_INFO,mi.UPNP)
    end
    def sendKey1()
        print("Send our Key ...")
        self.remote_info = self.received_data
        self.send_data = self.ownKey
        self.sendData(mi.CMD_SET_KEY,mi.UPNP)
        self.then(/->self.sendKey2())
    end
    def sendKey2()
        print("... with data.")
        self.sendData(mi.CMD_SEND_DATA,mi.AVDTP)
        self.then(/->self.wait())
    end
    def sendDID()
        if self.did_ct==nil # wait for JS
            return
        end
        self.send_data = self.did_ct
        print("Send shared key to device.")
        self.sendData(mi.CMD_SEND_DID,mi.AVDTP)
        self.then(/->self.wait())
    end
    def confirm()
        print("confirm")
        self.sendData(mi.CMD_AUTH,mi.UPNP)
        self.then(/->self.wait())
    end
    def comm()
        mi.state = mi.COMM
        print("Comm")
        self.then(/->self.wait())
    end

    def recReady()
        print("Receive ready")
        self.then(/->self.wait())
        self.sendData(mi.RCV_RDY,mi.AVDTP)
    end
    def recOK()
        print("Receive okay")
        if(mi.state==mi.SEND_KEY)
            self.then(/->self.sendKey1())
        elif(mi.state==mi.SEND_DID)
            self.call_JS_func("mShKey",self.received_data.tohex()) # call JS function with args
            self.then(/->self.sendDID())
        elif(mi.state==mi.CONFIRM)
            self.then(/->self.confirm())
        elif(mi.state==mi.COMM)
            self.then(/->self.comm())
        end     
        self.sendData(mi.RCV_OK,mi.AVDTP)
    end
 
  # create a method for adding a button to the main menu
  # the button 'BLE scan' redirects to '/mi32_key?'
  def web_add_main_button()
    import webserver
    webserver.content_send(
      "<form id=but_mi32_key style='display: block;' action='mi32_key' method='get'><button>MI32 Key Gen</button></form>")
  end
  
  #######################################################################
  # Display the compatible devices
  #######################################################################
  
  def show_devices()
    import webserver
    import string
    webserver.content_send("<p>Compatible devices:<p><select name='sensors' id='sens'>")
    var num = mi.devices()-1
    for i:0..num
        var name = mi.get_name(i)
        if  mi.supported(name)
            var mac = mi.get_MAC(i)
            var mac_str = mac.tohex()
            webserver.content_send(string.format("<option value=%s>%s - MAC: %s</option>",mac_str,name,mac_str))
        end
    end
    webserver.content_send("</select><br><br>")
    if num>0
        webserver.content_send("<button onclick='pair()'>Generate Key</button><br>")
        webserver.content_send("<br><button onclick='disc()'>Disconnect</button><br>")
    end

  end
  

  #######################################################################
  # Upload style
  #######################################################################

  def upl_css()
    import webserver
    webserver.content_send("<style>.parent{display:flex;flex-flow:row wrap;}.parent > *{flex: 1 100%;}tr:nth-child(even){background-color: #f2f2f230;}.box {margin: 5px;padding: 5px;border-radius: 0.8rem;background-color: rgba(221, 221, 221, 0.2);}@media all and (min-width: 600px){.side{flex:1 auto;}}@media all and (min-width:800px){.main{flex:3 0px;}.side-1{order:1;}.main{order:2;}.side-2{order:3;}.footer{order: 4;}}</style>")
  end

  #######################################################################
  # Upload javascript
  #######################################################################
  
  def upl_js()
    import webserver
    var script_start =  "<script>"
                        "var ownKey,sharedKey,lastCmd,lastLog;"
                        "function update(cmnd){if(!cmnd){cmnd='loop=1'}var xr=new XMLHttpRequest();xr.onreadystatechange=()=>{if(xr.readyState==4&&xr.status==200){"
                        "let r=xr.response;try{let j=JSON.parse(r);"
                        "if('KEY' in j){eb('key').innerHTML='Key: '+j.KEY}"
                        "else if('CMD' in j){console.log(j.CMD);lastCmd=j.CMD;window[j.CMD[0]](j.CMD[1]);}"
                        "}catch{log(r.substring(0,r.length-1));}"
                        "};};xr.open('GET','/mi32_key?'+cmnd,true);xr.send();};setInterval(update,250);"
    var script_1     =  "function save(){update('save=1');}"
                        "function genOwnKey(){if(ownKey==undefined){ownKey=sjcl.ecc.elGamal.generateKeys(256,10);}update('ownKey='+'04'+ownKey.pub.serialize().point);}"
                        "function mkShKey(k){var _pk=new sjcl.ecc.elGamal.publicKey(sjcl.ecc.curves.c256, sjcl.ecc.curves['c256'].fromBits(sjcl.codec.hex.toBits(k.substring(2))));"
                        "var _k = sj_key.sec.dhJavaEc(_pk);sharedKey='';for(var el of _key){sharedKey+=('0000000'+((el)>>>0).toString(16)).substr(-8);}console.log(sharedKey);deriveKey();}"
                        "function log(msg){if(msg[0]=='<'){return;}let n=Number(msg.substring(0,12).replace(/[:,]/g, ''));if(n<=lastLog){return;}lastLog=n;let l=eb('log');l.value+=msg+'\\n';l.scrollTop=l.scrollHeight;}"
                        "function pair(){update('pair='+eb('sens').value);eb('log').value+='Start pairing with: '+eb('sens').value+'\\n';}"
                        "function disc(){update('disc=1')}"
                        "function deriveKey(){"
                        "var derived_key = sjcl.codec.hex.fromBits(sjcl.misc.hkdf(sjcl.codec.hex.toBits(shared_key), 8 * 64, null, 'mible-setup-info', sjcl.hash['sha256']));"
                        "var token = derived_key.substring(0, 24);var bindkey= derived_key.substring(24, 56);console.log(token,bindkey);"
                        "var mi_bind_A = derived_key.substring(56, 88);"
                        "mi_write_did = sjcl.codec.hex.fromBits(sjcl.mode.ccm.encrypt(new sjcl.cipher.aes(sjcl.codec.hex.toBits(mi_bind_A)), sjcl.codec.hex.toBits(device_new_id), sjcl.codec.hex.toBits('101112131415161718191A1B'), sjcl.codec.hex.toBits('6465764944'), 32));"
                        "update('didCT='+mi_write_did);}"
    var script_2     =  "</script>"
                        # var cr=xr.response.replace(/bytes\\(\\'([^']+)\\'\\)/g,'$1');
                        # for(i in s){if(s.substring(s.length-i,s.length)==t.substring(0,i)){console.log(s.substring(0,s.length-1),t.substring(i,t.length))}}
     webserver.content_send(script_start)
     webserver.content_send(script_1)
     webserver.content_send(script_2)
  end

  def upl_js_file()
    import webserver
    # var f = open('core-min.js') # stripped down crypto library already enclosed in <script></script>
    # webserver.content_send(f.read())
    webserver.content_send("<script type='text/javascript' src='https://atc1441.github.io/core.js'></script>")
  end

  #######################################################################
  # handl AJAX
  #######################################################################

  def handleAJAX()
    import string
    import webserver
    var rsp = "{\"OK\":[]}"
    if webserver.has_arg("loop")
        if self.webCmd!=''
            rsp = self.webCmd
            self.webCmd = ''
        elif self.shallSendKey==true
            self.shallSendKey=false
            rsp = string.format("{\"KEY\":\"%s\"}",self.key)
        else
            var line = self.log_reader.get_log(self.log_level)
            if line == nil return rsp end  # no more logs
            # rsp = string.format("{\"LOG\":\"%s\"}",line)
            rsp = line
            self.msg=''
        end
    elif webserver.has_arg("pair")
        var mac = webserver.arg("pair")
        print("Connect requested from WebGUI.")
        self.pair(mac)
    elif webserver.has_arg("ownKey")
        self.ownKey = webserver.arg("ownKey")
        print("Key generated -> ESP:",self.ownKey)
    elif webserver.has_arg("didCT")
        self.did_ct = webserver.arg("didCT")
        print("DID CT -> ESP:",self.did_ct)
    elif webserver.has_arg("save")
        self.saveCfg()
        self.shallSendKey=false
        print("Saving mi32cfg.")
    elif webserver.has_arg("disc")
        ble.run(5)
        print("Will disconnect.")
    else
        return nil
    end
    return rsp
  end

  #######################################################################
  # Display the complete page
  #######################################################################
  def page_mi32_key()
    import webserver
    import string
    import json

    if !webserver.check_privileged_access() return nil end
    
    # AJAX response
    var rsp =self.handleAJAX()
    if rsp != nil
        webserver.content_response(rsp)
        return
    end


    # regular web page
    webserver.content_start("MI32 key generator")       #- title of the web page -#
    webserver.content_send_style()                      #- send standard Tasmota styles -#
    self.upl_css()                                      #- send own CSS -#
    self.upl_js_file()                                  #- send external JS -#
    self.upl_js()                                       #- send own JS -#

    webserver.content_send("<div class='parent'><header class='box'><h2> BLE key generator / MI32</h2><p style='text-align:right;'>... powered by BERRY</p></header>")
    webserver.content_send("<div class='box side side-1'>Using only sensors visible to the MI32 driver.<br>Check your 'mi32cfg' or<br>enable scanning for new sensors<br>with 'mi32option3 0'.")
    self.show_devices()
    webserver.content_send("</div>")
    webserver.content_send(
      "<div class='box side side-2'><p id='token'></p><p id='key'></p><br><button onclick='save()'>Save to mi32cfg</button></div>") #- close .box-# 
    webserver.content_send("<div class='large box main'><h3>Log:</h3><textarea id='log' style='min-width:580px'>Waiting for driver ...\n</textarea>")
    webserver.content_send("</div><br>")

    webserver.content_send("<p></p></div><br>")        #- close .parent div-#

    webserver.content_button(webserver.BUTTON_MANAGEMENT) #- button back to management page -#
    webserver.content_stop()                        #- end of web page -#
  end

  #######################################################################
  # Web Controller, called by POST to `/mi32_key`
  #######################################################################
  def page_mi32_key_ctl()
    import webserver
    import string
    if !webserver.check_privileged_access() return nil end

    try
      #---------------------------------------------------------------------#
      # To do.
      #---------------------------------------------------------------------#
      if webserver.has_arg("mi32_key")
        print("key generator")
        self.page_mi32_key()
      else
        raise "value_error", "Unknown command"
      end
    except .. as e, m
      print(string.format("BRY: Exception> '%s' - %s", e, m))
      #- display error page -#
      webserver.content_start("Parameter error")      #- title of the web page -#
      webserver.content_send_style()                  #- send standard Tasmota styles -#

      webserver.content_send(string.format("<p style='width:340px;'><b>Exception:</b><br>'%s'<br>%s</p>", e, m))

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
    webserver.on("/mi32_key", / -> self.page_mi32_key(), webserver.HTTP_GET)
    #webserver.on("/mi32_key", / -> self.page_mi32_key_ctl(), webserver.HTTP_POST)
  end
end

keyGen.MI32_keyGen_UI = MI32_keyGen_UI


#- create and register driver in Tasmota -#
if tasmota
  var MI32_keyGen_UI = keyGen.MI32_keyGen_UI()
  tasmota.add_driver(MI32_keyGen_UI)
  ## can be removed if put in 'autoexec.bat'
  MI32_keyGen_UI.web_add_handler()
  def pair(cmd, idx, payload, payload_json)
    MI32_keyGen_UI.pair(payload)
    return true
  end
  tasmota.add_cmd('pair', pair) # MAC of the dimmer
end

return keyGen

#- Example

import keyGen

-#
