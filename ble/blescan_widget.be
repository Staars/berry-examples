
#################################################################################
# MI32 Widget for the BLE scanner
#################################################################################
class SCAN_WIDGET : Driver

  var buf
  var scan_timer, scan_result, active_scan
  var update_table, stop_scan
  var init_step, ble_down

  def init()
      import BLE
      import MI32
      self.buf = bytes(-64)
      self.scan_timer = 0
      self.scan_result = []
      self.stop_scan = false
      self.active_scan = tasmota.cmd("mi32option4")
      self.init_step = 0
      self.ble_down = true

      var cbp = tasmota.gen_cb(/->self.widget_cb())
      MI32.widget("",cbp)
      tasmota.add_driver(self)
  end

  def stop()
      import BLE
      BLE.adv_cb(nil)
      tasmota.remove_driver(self)
  end

  def cb(svc,man)
      if self.scan_timer > 0
          if self.init_step > 3
              self.add_to_result()
          end
      end
  end

  def widget_cb()
      import webserver
      import MI32
      if webserver.arg_size() == 0
          log("M32: pageload",1)
          self.init_step = 0
          return
      end
      if self.init_step == 0
        if self.upl_js() == true
          self.init_step = 1
        end
        return
      elif self.init_step == 1
        if self.init_widget() == true
          self.init_step = 2
        end
        return
      elif self.init_step == 2
        if self.init_table() == true
          self.init_step = 3
        end
        return
      elif self.init_step == 3
        if webserver.has_arg("init") == true
          if self.ble_down == true
            import BLE
            log("M32: web UI did init",2)
            var cbp = tasmota.gen_cb(/svc,man -> self.cb(svc,man))
            BLE.adv_cb(cbp,self.buf)
            self.ble_down = false
          end
          webserver.content_response('{\"OK\":[]}')
          self.init_step = 4
        end
        return
      end

      if webserver.has_arg("loop")
        if self.stop_scan == false
            self.scan_timer = 1
        end
        if self.update_table==true
            self.get_body()
            self.update_table = false
            return
        end
      elif webserver.has_arg("clear")
        log("M32: clear",2)
        self.scan_result = [];
      elif webserver.has_arg("act")
        if webserver.arg("act")=="true"
            tasmota.cmd("mi32option4 1")
        else
            tasmota.cmd("mi32option4 0")
        end
      end
      if webserver.has_arg("wi") == false
          webserver.content_response('{\"OK\":[]}')
      end
      return
  end

 def add_to_result()
      var entry = {'SVC_UUID':0,'Name':'','SVC_DATA':0,'CID':0,'RSSI':0}
      entry.insert('MAC',self.buf[0..5])
      entry.insert('Type',self.buf[6])
      var rssi = (255 - self.buf.get(7,1)) * -1
      entry['RSSI'] = rssi

      var idx = 0
      var match = false

      if size(self.scan_result) > 0
          for i:0..size(self.scan_result)-1
              if self.buf[0..5] == self.scan_result[i]['MAC']
                  idx = i
                  match = true
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
      log(entry,4)
      if match == true
        self.scan_result.insert(idx,entry)
      else
        self.scan_result.push(entry)
      end
      self.update_table=true
  end

#######################################################################
# Display the result table as AJAX response
#######################################################################

def get_body()
  import webserver
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
  webserver.content_response(body)
end

#######################################################################
# Init table widget, poulate it later
#######################################################################

def init_table()
  import MI32
  var table = "<div class='box big' id='table' ><div style='height:auto;overflow:auto;'><table style='width:100%;'>"
              "<tr style='position:sticky;top: 0;background:black;'><th>MAC</th><th>Type</th><th>SVC_D</th><th>CID</th><th>SVC_U</th><th>Name</th><th>RSSI</th></tr>"
              '<tbody id="tb">'
              '<button id="launch_btn" onclick="(function(){var s=document.createElement(&quot;script&quot;);s.text=eb(&quot;sc_script&quot;).innerHTML;document.head.appendChild(s).parentNode.removeChild(s);})();">'
              'start</button></tbody></table></div></div>'
  return MI32.widget(table)
end


#######################################################################
# Upload javascript as invisible widget, must be activated manually
#######################################################################

def upl_js()
  import MI32
  var script =    "<script id='sc_script'>var igCC,igCV,igRC,igRV,igTC,igTV,fiSUC,fiSUV,fiSDC,fiSDV,tab;"
                  "function upd_ble_scan(cmnd){"
                    "fetch('/m32?'+cmnd).then(r=>r.json())"
                    ".then(r=>{if('body' in r){tab=r;updTable();beat('hbeat');}})"
                    ".catch(err=>{console.log(err);});"
                  "};"
                  "function beat(el){eb(el).animate([{r:'11',opacity:'1'},{r:'0',opacity:'0'}],{duration:1000,iterations:1})};"
                  "upd_ble_scan('init=1');setInterval(upd_ble_scan,1000,'loop=1');eb('launch_btn').remove();"
                  "function clearR(){upd_ble_scan('clear=1');eb('tb').innerHTML='';}"
                  "function actSc(evt){upd_ble_scan('act='+evt.checked);}"
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
                  "function updTable(){var body='',sd=0;for(entry of tab['body']){if((igTC==true && igTV==entry[1])||(igCC==true && igCV.includes(entry[3]))||(igRC==true && igRV>entry[6])){continue;}"
                  "if((fiSDC==true && fiSDV!=entry[2])||(fiSUC==true && fiSUV!=entry[4])){continue;}"
                  "var row='<tr>';for(el of entry){row+='<td>'+el+'</td>'}row+='</tr>';body+=row;sd+=1;}eb('tb').innerHTML=body;eb('log').innerHTML='Showing '+sd+'/'+tab.body.length+' devices'}"
                  "</script>"

   log("M32: upload JS")
   return MI32.widget(script)
end

#######################################################################
# Display the complete page
#######################################################################

  def init_widget()
    import MI32
    var  w ='<div class="box tall" id="scan1">'
            '<h2 style="margin-top:0em;">BLE scanner</h2>'
            "<svg height='24' width='24' style='float:inline-end;'>"
            "<circle id='hbeat' cx='11' cy='11' r='11' fill='#90ee90' opacity='0'></svg>"
            "<input type='checkbox' onclick='actSc(this)'>Active scanning</input><p id='log'></p><br>"
            "<div style='display:inline-grid;grid-template-columns: 0.1fr 4fr 1fr;'>"
            "<input type='checkbox' onclick='ignCC(this)'>Ignore CID (in HEX): <input type='text' onchange='ignCV(this)' style='width:auto;' size='8'>"
            "<input type='checkbox' onclick='ignRC(this)'>Ignore weaker RSSI: <input type='number' onchange='ignRV(this)' style='width:auto;'  min='-99' max='0'>"
            "<input type='checkbox' onclick='ignTC(this)'>Ignore (Address) Type: <input type='number' onchange='ignTV(this)' style='width:auto;'  min='0' max='4'>"
            "<input type='checkbox' onclick='filSUC(this)'>Filter Service UUID: <input type='text' onchange='filSUV(this)' style='width:auto;'  size='8'>"
            "<input type='checkbox' onclick='filSDC(this)'>Filter  Service Data: <input type='text' onchange='filSDV(this)' style='width:auto;'  size='8'>"
            "</div>"
            "<br><button onclick='clearR()'>Clear results</button>"
            "</div>"

    log("M32: Init Widget")
    return MI32.widget(w)
  end

end

sw = SCAN_WIDGET()
