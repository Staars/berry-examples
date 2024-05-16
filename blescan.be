#######################################################################
# BLE Scanner for every ESP32 with BLE
#
# use : `import blescan`
#
# Provides BLE bindings and a Web UI
#######################################################################

var blescan = module('blescan')
#@ solidify:blescan

#################################################################################
# BLE_scan_UI
#
# WebUI for the BLE scanner
#################################################################################
class BLE_scan_UI
 
    var buf
    var scan_timer, scan_result, active_scan
    var update_table, stop_scan


    def init()
        import BLE
        self.buf = bytes(-64)
        self.scan_timer = 0
        self.scan_result = []
        self.stop_scan = false
        self.active_scan = tasmota.cmd("mi32option4")

        var cbp = tasmota.gen_cb(/svc,man -> self.cb(svc,man))
        BLE.adv_cb(cbp,self.buf)
    end

    def cb(svc,man)
        if self.scan_timer > 0
            #self.buf = self.buf_raw.copy()
            self.add_to_result()
        end
    end
        
   def add_to_result()
        var entry = {'SVC_UUID':0,'Name':'','SVC_DATA':0,'CID':0,'RSSI':0}
        entry.insert('MAC',self.buf[0..5])
        entry.insert('Type',self.buf[6])
        var rssi = (255 - self.buf.get(7,1)) * -1
        entry['RSSI'] = rssi
        
        var idx = 0

        if size(self.scan_result) > 0
            for i:0..size(self.scan_result)-1
                if self.buf[0..5] == self.scan_result[i]['MAC']
                    idx = i
                    entry = self.scan_result[i]
                    entry['RSSI'] = rssi
                    self.scan_result.remove(i)
                    break
                end
            end
        end
        
        var len_p = self.buf.get(8,1)
        var i = 9                       #- start of payload -#
        while i < 9+len_p
            var len = self.buf.get(i,1)
            var _type = self.buf.get(i+1,1)
            if _type==2 || _type==3
              entry['SVC_UUID']=self.buf.get(i+2,2)
            end
            if _type==0x16
              entry['SVC_DATA']=self.buf.get(i+2,2)
            end
            if _type==0xff
              entry['CID']=self.buf.get(i+2,2)
            end
            if _type==8 || _type==9
              var _name = self.buf[i+2..(i+len)]# + bytes('00') # null terminate it
              entry['Name']=_name.asstring()
            end
            i+=len+1
        end
        print(entry)
        self.scan_result.insert(idx,entry)
        self.update_table=true
    end
    

  # create a method for adding a button to the main menu
  # the button 'BLE scan' redirects to '/ble_scan?'
  def web_add_button()
    import webserver
    webserver.content_send(
      "<form id=but_ble_scan style='display: block;' action='ble_scan' method='get'><button>BLE scan</button></form>")
  end
  
  #######################################################################
  # Display the result table as response
  #######################################################################

  def get_body()
    var body = "{\"body\":["
    for i:0..size(self.scan_result)-1
        var entry = self.scan_result[i]
        var msg_e = format("[\"%s\",\"%i\",\"%04x\",\"%04x\",\"%04x\",\"%s\",%i]",
        entry['MAC'].tohex(),entry['Type'],entry['SVC_DATA'],entry['CID'],entry['SVC_UUID'],entry['Name'],entry['RSSI'])
        body += msg_e
        if i<size(self.scan_result)-1
          body +=","
        end
    end
    body += "]}"
    return body
  end
  
  def show_table()
    import webserver
    var response = "<div style='height:331px;overflow:auto;'><table style='width:640px;'>"
    response += "<tr style='position:sticky;top: 0;background:black;'><th>MAC</th><th>Type</th><th>SVC_D</th><th>CID</th><th>SVC_U</th><th>Name</th><th>RSSI</th></tr>"
    response += "<tbody id='tb'></tbody></table></div>"
    webserver.content_send(response)
    #self.update_table=false
  end
  
  #######################################################################
  # Upload javascript
  #######################################################################
  
  def upl_js()
    import webserver
    var script_start = "<script>var igCC,igCV,igRC,igRV,igTC,igTV,fiSUC,fiSUV,fiSDC,fiSDV,tab;function update(cmnd){if(!cmnd){cmnd='loop=1'}var xr=new XMLHttpRequest();xr.onreadystatechange=()=>{if(xr.readyState==4&&xr.status==200){"
                       "const r=JSON.parse(xr.response);if('body' in r){tab=r;updTable();}else{beat();}"
                       "};};xr.open('GET','/ble_scan?'+cmnd,true);xr.send();};setInterval(update,500);"
    var script_1     = "function clearR(){update('clear=1');eb('tb').innerHTML='';}"
                       "function actSc(evt){update('act='+evt.checked);}"
                       "function ignCC(evt){igCC=evt.checked;updTable()}"
                       "function ignCV(evt){igCV=evt.value;updTable()}"
                       "function ignRC(evt){igRC=evt.checked;updTable()}"
                       "function ignRV(evt){igRV=Number(evt.value);updTable()}"
                       "function ignTC(evt){igTC=evt.checked;updTable()}"
                       "function ignTV(evt){igTV=Number(evt.value);updTable()}"
                       "function filSUC(evt){fiSUC=evt.checked;updTable()}"
                       "function filSUV(evt){fiSUV=evt.value;updTable()}"
                       "function filSDC(evt){fiSDC=evt.checked;updTable()}"
                       "function filSDV(evt){fiSDV=evt.value;updTable()}"
    var script_2     = "function beat(){const effect = new KeyframeEffect(eb('hbeat'),[{opacity: 0},{opacity: 1}],{duration: 2000,fill: 'forwards'}"
                        ");const anim = new Animation(effect, document.timeline);anim.play()}"
                        "function updTable(){var body='',sd=0;for(entry of tab['body']){if((igTC==true && igTV==entry[1])||(igCC==true && igCV.includes(entry[3]))||(igRC==true && igRV>entry[6])){continue;}"
                        "if((fiSDC==true && fiSDV!=entry[2])||(fiSUC==true && fiSUV!=entry[4])){continue;}"
                        "var row='<tr>';for(el of entry){row+='<td>'+el+'</td>'}row+='</tr>';body+=row;sd+=1;}eb('tb').innerHTML=body;eb('log').innerHTML='Showing '+sd+'/'+tab.body.length+' devices'}"
                        "</script>"            

     webserver.content_send(script_start)
     webserver.content_send(script_1)
     webserver.content_send(script_2)
  end

  #######################################################################
  # Display the complete page
  #######################################################################
  def page_ble_scan()
    import webserver
    import json

    if !webserver.check_privileged_access() return nil end
    
    # AJAX response
    if webserver.has_arg("loop")
      if self.stop_scan == false
        self.scan_timer = 1
      end
      if(self.update_table==true)
        webserver.content_response(self.get_body())
        self.update_table = false
        return
      end
      webserver.content_response("{\"OK\":[]}")
      return
    elif webserver.has_arg("clear")
      self.scan_result = [];
      webserver.content_response("{\"OK\":[]}")
      return
    elif webserver.has_arg("act")
      if webserver.arg("act")=="true"
        tasmota.cmd("mi32option4 1")
      else
        tasmota.cmd("mi32option4 0")
      end  
      webserver.content_response("{\"OK\":[]}")
      return
    end

    # regular web page
    webserver.content_start("BLE scan")       #- title of the web page -#
    webserver.content_send_style()            #- send standard Tasmota styles -#

    webserver.content_send("<style>.parent{display:flex;flex-flow:row wrap;}.parent > *{flex: 1 100%;}tr:nth-child(even){background-color: #f2f2f230;}.box {margin: 5px;padding: 5px;border-radius: 0.8rem;background-color: rgba(221, 221, 221, 0.2);}@media all and (min-width: 600px){.side{flex:1 auto;}}@media all and (min-width:800px){.main{flex:3 0px;}.side-1{order:1;}.main{order:2;}.side-2{order:3;}.footer{order: 4;}}</style>")

    self.upl_js()                             #- send own JS -#

    webserver.content_send("<div class='parent'><header class='box'><h2> BLE Scanner / MI32</h2><p style='text-align:right;'>... powered by BERRY</p></header>")
    webserver.content_send("<div class='box side side-1'><p id='hbeat'>Scanning ...</p>")
    webserver.content_send("<input type='checkbox' onclick='actSc(this)'>Active scanning</input><p id='log'></p><br><input type='checkbox' onclick='ignCC(this)'>Ignore CID (in HEX): <input type='text' onchange='ignCV(this)' style='width:auto;' size='12'><br>")
    webserver.content_send("<input type='checkbox' onclick='ignRC(this)'>Ignore RSSI (weaker than): <input type='number' onchange='ignRV(this)' style='width:auto;'  min='-99' max='0'><br>")
    webserver.content_send("<input type='checkbox' onclick='ignTC(this)'>Ignore (Address) Type: <input type='number' onchange='ignTV(this)' style='width:auto;'  min='0' max='4'><br>")
    webserver.content_send("<input type='checkbox' onclick='filSUC(this)'>Filter Service UUID: <input type='text' onchange='filSUV(this)' style='width:auto;'  size='12'><br>")
    webserver.content_send("<input type='checkbox' onclick='filSDC(this)'>Filter  Service Data: <input type='text' onchange='filSDV(this)' style='width:auto;'  size='12'><br>")
    webserver.content_send("</div>")
    webserver.content_send(
      "<div class='box side side-2'><br><button onclick='clearR()'>Clear results</button></div>") #- close .box-# 
    
    webserver.content_send("<div class='large box main'><p></p>")
    self.show_table()
    webserver.content_send("</div><br>")

    webserver.content_send("<p></p></div><br>")        #- close .parent div-#

    webserver.content_button(webserver.BUTTON_MANAGEMENT) #- button back to management page -#
    webserver.content_stop()                        #- end of web page -#
    self.update_table = true
  end

  #######################################################################
  # Web Controller, called by POST to `/ble_scan`
  #######################################################################
  def page_ble_scan_ctl()
    import webserver
    if !webserver.check_privileged_access() return nil end

    try
      #---------------------------------------------------------------------#
      # To do.
      #---------------------------------------------------------------------#
      if webserver.has_arg("scan")
        print("scan")
        self.scan_timer = 5
        self.page_ble_scan()
        self.update_table = true
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
    webserver.on("/ble_scan", / -> self.page_ble_scan(), webserver.HTTP_GET)
    webserver.on("/ble_scan", / -> self.page_ble_scan_ctl(), webserver.HTTP_POST)
  end
  
  def every_second()
    if self.scan_timer > 0
        if self.scan_timer == 1
            self.page_ble_scan()
        end
        self.scan_timer -= 1
    end
  end
end

blescan.BLE_scan_UI = BLE_scan_UI


#- create and register driver in Tasmota -#
if tasmota
  var ble_scan_ui = blescan.BLE_scan_UI()
  tasmota.add_driver(ble_scan_ui)
  ## can be removed if put in 'autoexec.bat'
    ble_scan_ui.web_add_handler()
end

return blescan

#- Example

import blescan

-#
