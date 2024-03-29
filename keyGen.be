#######################################################################
# MI bind key generator for ESP32 - ESP32C3 - ESP32S3
#
# Port of https://github.com/dnandha/miauth 
#       & https://github.com/atc1441/atc1441.github.io
#
# use : `import keyGen`
#
# Provides BLE bindings and a Web UI
#
# Many Thanks to dnandha, danielkucera, atc1441
#######################################################################

var keyGen = module('keyGen')

#################################################################################
# mi helper class
#################################################################################
class MI32_Helper
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
        if  name == "LYWSD03" || name == "MHOC401" ||
            name == "MJYD2S" || name == "MCCGQ02" || name == "SJWS01L"
            return true
        end
        return false
    end

    def saveCfg()
        tasmota.cmd("mi32cfg")
    end

end

#################################################################################
# Globals
#################################################################################

var mi = MI32_Helper()

#################################################################################
# MI32_keyGen_UI
#
# WebUI for the bind key generator
#################################################################################
class MI32_keyGen_UI

    var token, rev_MAC, MAC
    var current_func, next_func
    var msg, ownKey, bindKey
    var receive_frames, received_data, send_data, remote_info, remote_key, did_ct
    var buf, webCmd
    var log_reader, log_level
    var chunks, chunkIdx, lastChunk

    def init()
        import BLE
        var cbp = tasmota.gen_cb(/e,o,u->self.cb(e,o,u))
        self.buf = bytes(-64)
        BLE.conn_cb(cbp,self.buf)
        self.current_func = self.wait
        self.ownKey = ""
        self.log_reader = tasmota_log_reader()
        self.log_level = 2
        var line = self.log_reader.get_log(self.log_level)
        while line != nil
            line = self.log_reader.get_log(self.log_level)
        end  # purge log
    end

    def every_50ms()
        self.current_func()
    end

    def cb(error,op,uuid)
        import string
        import BLE
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
            BLE.run(5) # disconnect
        end
    end

    # BLE helper gunctions
    def copyBufToPos(target,pos,source)
        for i:0..size(source)-1
            target[pos+i] = source[i]
        end
    end

    def sendData(data,chr)
        import BLE
        BLE.set_svc(mi.svc)
        BLE.set_chr(chr)
        self.buf[0] = size(data)
        self.copyBufToPos(self.buf,1,data)
        return BLE.run(2,false)
    end

    def subscribe(chr)
        import BLE
        BLE.set_svc(mi.svc)
        BLE.set_chr(chr)
        print("Subscribe to: ",chr)
        return BLE.run(3,true)
    end

    # call Javascript function with args
    def call_JS_func(cmd,args)
        import string
        if args == nil
            args = ""
        end
        self.webCmd = string.format("{\"CMD\":[\"%s\",\"%s\"]}",cmd,args) # will be send by our AJAX handler, if self.webCmd is not empty
        print("Call JS function: "+cmd+"("+args+")")
    end

    # our little promise implementation
    def wait()
        # do nothing
    end

    def then(func)
        # save function pointers for callback, typically expecting a closure
        self.next_func = func
        self.current_func = self.wait
    end

    # helper and handler function, mostly called from notification callbacks
    def sendChunks()
        import string
        if self.chunks>self.chunkIdx
            var from = self.chunkIdx*18
            var to = (self.chunkIdx*18)+17
            if self.lastChunk!=0 && self.chunkIdx == self.chunks-1
                to = self.chunkIdx*18+self.lastChunk
            end
            var chunk = self.send_data[from..to]
            var idx = str(self.chunkIdx+1)
            var packet = bytes('0'+idx+"00")+chunk
            self.sendData(packet,mi.AVDTP)
            self.chunkIdx+=1
            self.then(/->self.sendChunks())
            print(packet)
        else
        print("Packet complete!")
        self.then(/->self.wait())
        end
    end

    def write_parcel(ch, data)
        var chunk_size=18
        var length = size(data)
        self.chunks = length/chunk_size
        self.lastChunk = length-self.chunks*chunk_size
        if self.lastChunk!=0
            self.chunks+=1
        end
        self.chunkIdx = 0
        self.sendChunks()
    end

    def handleConfirm()
        var frm = self.getFrm()
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
        self.current_func = /->self.comm()
    end

    def getFrm()
        var frm = self.buf[1]
        if self.buf[0] > 2
            frm += 0x100*self.buf[2]
        end
        # print("Frame :",frm)
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
        var frm = self.getFrm()
        if frm != 0
            self.current_func = /->self.wait() #???
            print(frm)
            return
        end
        print("Will send data to sensor.")
        if self.buf[1..self.buf[0]] == mi.RCV_RDY
            print("Mi ready to receive key")
            self.write_parcel(mi.AVDTP, self.send_data)
        elif self.buf[1..self.buf[0]] == mi.RCV_TOUT
            print("Mi sent RCV timeout.")
        elif self.buf[1..self.buf[0]] == mi.RCV_ERR
            print("Mi sent some RCV error?")
        elif self.buf[1..self.buf[0]] == mi.RCV_OK
            print("Mi confirmed key receive")
            mi.state+=1
            print("Next state:",mi.state)
            if mi.state==mi.CONFIRM
                # print("Next step confirm ....")
                self.current_func = /->self.confirm()
                return
            end
            self.current_func = /->self.wait()
        else
            print(self.buf[1..self.buf[0]])
        end
    end

    def handleNotif()
        if (mi.state == mi.RECV_INFO || mi.state == mi.RECV_KEY)
            self.current_func = /->self.handleRec()
        elif mi.state == mi.SEND_KEY
            self.send_data = self.ownKey
            print(self.send_data)
            self.current_func = /->self.handleSend()
        elif mi.state == mi.SEND_DID
            self.send_data = self.did_ct
            self.current_func = /->self.handleSend()
        elif mi.state == mi.CONFIRM
            self.current_func = /->self.handleConfirm()
        # elif mi.state == mi.COMM
        #     self.current_func = /->self.handleCOMM()
        end
    end

    # entry point, started from the web UI
    def pair(MAC)
        import BLE
        import string
        self.MAC = MAC
        print("Try to connect to: ",MAC)
        BLE.set_MAC(bytes(MAC),0)
        mi.state = mi.INIT
        self.call_JS_func("genOwnKey")
        self.then(/->self.func1())
        self.subscribe(mi.UPNP)
    end

    # The next functions are some kind of sequence, that get called from 
    # notification callbacks most of the time

    def func1()
        print("Did connect ...")
        self.then(/->self.getInfo())
        self.subscribe(mi.AVDTP)  
    end

    def getInfo()
        print("Ask sensor for dev ID.")
        mi.state = mi.RECV_INFO
        self.then(/->self.wait())
        self.sendData(mi.CMD_GET_INFO,mi.UPNP)
    end
    def sendKey1()
        var ri = self.received_data
        var did = ri[4..size(ri)-1].tohex()
        self.call_JS_func('setDevID',did)
        print("Send our Key ...")
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
        self.call_JS_func('getBindKey')
        self.then(/->self.wait())
    end
    def confirm()
        print("Ask device for confirmation.")
        self.sendData(mi.CMD_AUTH,mi.UPNP)
        self.then(/->self.wait())
    end
    def comm()
        import BLE
        print("Pairing finished!!")
        BLE.run(5)
        self.then(/->self.setKey())
    end
    def setKey()
        if self.bindKey == nil
            return
        else
            var keyMAC = self.bindKey + self.MAC
            tasmota.cmd("mi32key "+keyMAC)
            print("Press SAVE button to update mi32cfg file.")
            self.then(/->self.wait())
        end
    end

    # semi generic response functions 
    def recReady()
        print("Receive ready")
        self.then(/->self.wait())
        self.sendData(mi.RCV_RDY,mi.AVDTP)
    end

    def recOK()
        if(mi.state==mi.SEND_KEY)
            self.then(/->self.sendKey1())
        elif(mi.state==mi.SEND_DID)
            if self.webCmd!=""
                return
            end
            self.call_JS_func("mkShKey",self.received_data.tohex()) # call JS function with args
            self.then(/->self.sendDID())
        end
        print("Receive okay")
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
    import MI32
    webserver.content_send("<p>Compatible devices:<p><select name='sensors' id='sens'>")
    var num = MI32.devices()-1
    for i:0..num
        var name = MI32.get_name(i)
        if  mi.supported(name)
            var mac = MI32.get_MAC(i)
            var mac_str = mac.tohex()
            webserver.content_send(string.format("<option value=%s>%s - MAC: %s</option>",mac_str,name,mac_str))
        end
    end
    webserver.content_send("</select><br><br>")
    if num>0
        webserver.content_send("<button onclick='pair()'>Generate Key</button><br>")
        webserver.content_send("<br><button onclick='disc()'>Disconnect</button><br><p id='key'></p>")
    end

  end
  

  #######################################################################
  # Upload style
  #######################################################################

  def upl_css()
    import webserver
    webserver.content_send("<style>.parent{display:flex;flex-flow:row wrap;}.parent > *{flex: 1 100%;}tr:nth-child(even){background-color: #f2f2f230;}.box {margin: 5px;padding: 10px;border-radius: 0.8rem;background-color: rgba(221, 221, 221, 0.2);}@media all and (min-width: 600px){.side{flex:1 auto;}}@media all and (min-width:800px){.main{flex:3 0px;}.side-1{order:1;}.main{order:2;}.side-2{order:3;}.footer{order: 4;}}</style>")
  end

  #######################################################################
  # Upload javascript
  #######################################################################
#   substring(0,r.length-1));
  def upl_js()
    import webserver
    var script       =  "<script>"
                        "var ownKey,sharedKey,token,bindKey,devID,lastLog;"
                        "function update(cmnd){if(!cmnd){cmnd='loop=1'}var xr=new XMLHttpRequest();xr.onreadystatechange=()=>{if(xr.readyState==4&&xr.status==200){"
                        "let r=xr.response;try{let j=JSON.parse(r);"
                        "if('KEY' in j){eb('key').innerHTML='Key: '+j.KEY}"
                        "else if('CMD' in j){console.log(j.CMD);window[j.CMD[0]](j.CMD[1]);}"
                        "}catch{log(r.replace(/[^\\x20-\\x7E]/g,'\\n'));}"
                        "};};xr.open('GET','/mi32_key?'+cmnd,true);xr.send();};setInterval(update,250);"
                        "function save(){update('save=1');}"
                        "function genOwnKey(){if(ownKey==undefined){ownKey=sjcl.ecc.elGamal.generateKeys(256,10);}update('ownKey='+ownKey.pub.serialize().point);}"
                        "function mkShKey(k){console.log('Got public device key:',k);var _pk=new sjcl.ecc.elGamal.publicKey(sjcl.ecc.curves.c256, sjcl.ecc.curves['c256'].fromBits(sjcl.codec.hex.toBits(k)));"
                        "var _k = ownKey.sec.dhJavaEc(_pk);sharedKey='';for(var el of _k){sharedKey+=('0000000'+((el)>>>0).toString(16)).substr(-8);}console.log(sharedKey);deriveKey();}"
                        "function log(msg){if(msg[0]=='<'){return;}let n=Number(msg.substring(0,12).replace(/[:,]/g, ''));if(n<=lastLog){return;}lastLog=n;let l=eb('log');l.value+=msg;l.scrollTop=l.scrollHeight;}"
                        "function pair(){update('pair='+eb('sens').value);eb('log').value+='Start pairing with: '+eb('sens').value+'\\n';}"
                        "function disc(){update('disc=1')}"
                        "function setDevID(i){devID=i;}"
                        "function getBindKey(){update('bkey='+bindKey);}"
                        "function deriveKey(){"
                        "var derived_key = sjcl.codec.hex.fromBits(sjcl.misc.hkdf(sjcl.codec.hex.toBits(sharedKey), 8 * 64, null, 'mible-setup-info', sjcl.hash['sha256']));"
                        "token=derived_key.substring(0, 24);var bindkey= derived_key.substring(24, 56);console.log(token,bindkey);"
                        "bindKey=derived_key.substring(24,56).toUpperCase();eb('key').innerHTML='KEY: '+bindKey;"
                        "var _keyA=derived_key.substring(56,88);"
                        "mi_write_did = sjcl.codec.hex.fromBits(sjcl.mode.ccm.encrypt(new sjcl.cipher.aes(sjcl.codec.hex.toBits(_keyA)), sjcl.codec.hex.toBits(devID), sjcl.codec.hex.toBits('101112131415161718191A1B'), sjcl.codec.hex.toBits('6465764944'), 32));"
                        "update('didCT='+mi_write_did);}"
                        "</script>"

                        # var cr=xr.response.replace(/bytes\\(\\'([^']+)\\'\\)/g,'$1');
                        # for(i in s){if(s.substring(s.length-i,s.length)==t.substring(0,i)){console.log(s.substring(0,s.length-1),t.substring(i,t.length))}}
     
    webserver.content_send(script)
  end

  def upl_js_file()
    import webserver

    try
        var f = open('sjcl_min.html',"r") # stripped down crypto library already enclosed in <script></script>
        # var f = open(kg_wd + 'sjcl_min.html',"r") # stripped down crypto library already enclosed in <script></script>
        webserver.content_send(f.read())
    except .. as e, m
        print("sjcl_min.html not in FS, fallback to external JS library from https://Staars.github.io/sjcl_min.js'")
        webserver.content_send("<script type='text/javascript' src='https://Staars.github.io/sjcl_min.js'></script>")
    end
  end

  #######################################################################
  # handl AJAX
  #######################################################################

  def handleAJAX()
    import string
    import webserver
    import BLE
    var rsp = "{\"OK\":[]}"
    if webserver.has_arg("loop")
        if self.webCmd!=''
            rsp = self.webCmd
            self.webCmd = ''
        else
            var line = self.log_reader.get_log(self.log_level)
            if line != nil
                rsp = line
            end
            while line != nil
                line = self.log_reader.get_log(self.log_level)
                if line != nil rsp+=line end
            end
        end
    elif webserver.has_arg("pair")
        var mac = webserver.arg("pair")
        print("Connect requested from WebGUI.")
        self.pair(mac)
    elif webserver.has_arg("ownKey")
        self.ownKey = bytes(webserver.arg("ownKey"))
        print("Public key generated -> ESP:",self.ownKey)
    elif webserver.has_arg("didCT")
        self.did_ct = bytes(webserver.arg("didCT"))
        print("DID CT -> ESP:",self.did_ct)
    elif webserver.has_arg("bkey")
        self.bindKey = webserver.arg("bkey")
        print("Bind Key -> ESP:",self.bindKey)
    elif webserver.has_arg("save")
        mi.saveCfg()
        print("Saving mi32cfg.")
    elif webserver.has_arg("disc")
        BLE.run(5)
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
      "<div class='box side side-2'><p id='token'></p><br><button onclick='save()'>Save to mi32cfg</button></div>") #- close .box-# 
    webserver.content_send("<div class='large box main'><h3>Log:</h3><textarea id='log' style='min-width:580px' wrap='off'>Waiting for driver ...\n</textarea>")
    webserver.content_send("</div><br>")

    webserver.content_send("<p></p><br><p></p></div><br>")        #- close .parent div-#

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
  end
end

keyGen.MI32_keyGen_UI = MI32_keyGen_UI


#- create and register driver in Tasmota -#
if tasmota
  var mi32_keyGen_UI = keyGen.MI32_keyGen_UI()
  tasmota.add_driver(mi32_keyGen_UI)
  ## can be removed if put in 'autoexec.bat'
  mi32_keyGen_UI.web_add_handler()
  def pair(cmd, idx, payload, payload_json)
    mi32_keyGen_UI.pair(payload)
    return true
  end
  tasmota.add_cmd('pair', pair) # MAC of the sensor
end

return keyGen

#- Example

import keyGen

-#
