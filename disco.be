#######################################################################
# Disco
#
# Homeassitant MQTT Discovery for Tasmota BLE Sensors
#######################################################################

import string
import json

class DISCO
    var delete_everything

    def get_sensor_db()
        var props = "["
                "{\"944a\":{\"name\":\"PVVX\",\"mf\":\"Xiaomi\",\"s\":[\"t\",\"h\",\"d\",\"b\"]}},"
                "{\"0a1c\":{\"name\":\"ATC\",\"mf\":\"Xiaomi\",\"s\":[\"t\",\"h\",\"d\",\"b\"]}},"
                "{\"01aa\":{\"name\":\"MJ_HT_V1\",\"mf\":\"Xiaomi\",\"s\":[\"t\",\"h\",\"d\",\"b\"]}},"
                "{\"045b\":{\"name\":\"LYWSD02\",\"mf\":\"Xiaomi\",\"s\":[\"t\",\"h\",\"d\",\"b\"]}},"
                "{\"055b\":{\"name\":\"LYWSD03\",\"mf\":\"Xiaomi\",\"s\":[\"t\",\"h\",\"d\",\"b\"]}},"
                "{\"0387\":{\"name\":\"MHOC401\",\"mf\":\"Xiaomi\",\"s\":[\"t\",\"h\",\"d\",\"b\"]}},"
                "{\"06d3\":{\"name\":\"MHOC303\",\"mf\":\"Xiaomi\",\"s\":[\"t\",\"h\",\"d\",\"b\"]}},"
                "{\"0576\":{\"name\":\"CGD1\",\"mf\":\"Qingping\",\"s\":[\"t\",\"h\",\"d\",\"b\"]}},"
                "{\"0347\":{\"name\":\"CGG1\",\"mf\":\"Qingping\",\"s\":[\"t\",\"h\",\"d\",\"b\"]}},"
                "{\"03dd\":{\"name\":\"NLIGHT\",\"mf\":\"Philips\",\"bs\":[\"m\"]}},"
                "{\"07f6\":{\"name\":\"MJYD2S\",\"mf\":\"Xiaomi\",\"s\":[\"i\",\"b\"],\"bs\":[\"m\"]}},"
                "{\"0153\":{\"name\":\"YLYK01\",\"mf\":\"Yeelight\",\"dt\":[{\"bt\":[6,[0,2]]}]}},"
                "{\"098b\":{\"name\":\"MCCGQ02\",\"mf\":\"Xiaomi\",\"s\":[\"b\"],\"bs\":[\"do\"]}},"
                "{\"0863\":{\"name\":\"SJWS01L\",\"mf\":\"Xiaomi\",\"s\":[\"b\"],\"bs\":[\"l\"],\"dt\":[{\"bt\":[1,[0,2]]}]}},"
                "{\"03b6\":{\"name\":\"YLKG08\",\"mf\":\"Yeelight\",\"dt\":[{\"di\":1},{\"ho\":1},{\"bt\":[1,[0,1]]}]}},"
                "{\"07bf\":{\"name\":\"YLAI003\",\"mf\":\"Yeelight\",\"dt\":[{\"bt\":[1,[0,1,2]]}]}}"
                "]"
        return json.load(props)
    end
    def feat_full(f)
        var feat_full = {'t':'Temperature','h':'Humidity','d':'Temperature','b':'Battery','i':'Illuminance','bt':'Button','ho':'Hold','do':'Door','l':'Leak','m':"Motion",'di':"Dimmer"}
        return feat_full[f]
    end
    def unit_full(u)
        var unit_full = {'t':'°C','h':'%','d':'°C','b':'%','i':'lx'}
        return unit_full[u]
    end
    def btn_code(c)
        var btn_code  = ["short","double","long"]
        return btn_code[c]
    end
    def sens_name(name,mac)
        var mac_end = bytes(string.split(mac,6)[1])
        return string.format("%s-%04x%02x",name,mac_end.get(0,-2),mac_end.get(2,1)) #to lower case
    end
    
    def sens_pub(topic,payload)
        import mqtt
        if self.delete_everything
            mqtt.publish(topic,"",true)
        else
            mqtt.publish(topic,payload,true)
        end
    end
    
    def get_dev(ids,name,mdl,mf,via_d,mac)
        var dev = {}
        dev['ids'] = [ids]
        dev['name'] = name
        dev['mf'] = mf
        dev['mdl'] = mdl
        dev['via_device'] = via_d
        dev["cns"] = [["mac", mac]]
        return dev
    end
    def get_sens(name,feat,dev,unit,is_diag)
        var sens = {}
        sens["obj_id"] = name+"."+feat
        sens["uniq_id"] = name+"."+feat
        sens["name"] = feat + " " + name
        sens["dev_cla"] = feat
        sens["dev"] = dev
        if unit sens["unit_of_meas"] = unit end
        if is_diag sens["ent_cat"] = "diagnostic" end
        sens['stat_t'] = "tele/+/SENSOR"
        return sens
    end
    def handle_sens(pid,mac,hasKey,host_name,topic_name,alias)
        var topic_s = "homeassistant/%s/%s_%s/config"
        var templ_val_s = "{{ value_json['%s']['%s'] | is_defined}}"
        var templ_val_bs = "{%% if '%s' in  value_json -%%}{{ value_json['%s']['%s'] | is_defined}}{%%- endif -%%}"
        var templ_val_dt = "{{ value_json['%s']['%s%u'] | is_defined}}"
        var templ_val_dim= "{%% if '%s' in  value_json -%%}{%%set v = states('number.%s_%s_dimmer')| int(0)-%%}{{ value_json['%s']['%s'] | is_defined + v }}{%%- endif -%%}"

        var p = self.get_sensor_db()
        for t:p
            if t.find(pid)
                print(t[pid]["name"])
                var name = self.sens_name(t[pid]["name"],mac)
                var dev = self.get_dev(mac,name,t[pid]["name"],t[pid]["mf"],"Tasmota BLE",mac)
    
                # diagnostic entries
                var rssi_name = string.format("rssi_%s_%s",host_name,name)
                var topic = string.format(topic_s,"sensor",host_name,name+"_rssi")
                var rssi = self.get_sens(rssi_name,"signal_strength",dev,"db")
                rssi["name"] = "-> " + host_name
                rssi["val_tpl"] = string.format(templ_val_s,name,"RSSI",name,name,"RSSI")
                rssi["ent_cat"] = "diagnostic"
                rssi["ic"] = "mdi:bluetooth"
                rssi['stat_t'] = string.format("tele/%s/SENSOR",topic_name)
                rssi["json_attr_t"] = string.format("tele/%s/STATE",topic_name)
                self.sens_pub(topic,json.dump(rssi))
                if t[pid].find("s")
                    for f:t[pid]["s"]
                        var full_f = self.feat_full(f)
                        topic = string.format(topic_s,"sensor",name,full_f)
                        var unit = self.unit_full(f)
                        var s = self.get_sens(name,full_f,dev,unit)
                        s["val_tpl"] = string.format(templ_val_s,name,full_f)
                        self.sens_pub(topic,json.dump(s))
                    end
                end
                if t[pid].find("bs")
                    for f:t[pid]["bs"]
                        var full_f = self.feat_full(f)
                        topic = string.format(topic_s,"binary_sensor",name,full_f)
                        var s = self.get_sens(name,full_f,dev)
                        if f == "m" # motion
                            s["off_dly"] = 30
                        end 
                        s["val_tpl"] = string.format(templ_val_bs,name,name,full_f)
                        s["pl_on"] = 1
                        s["pl_off"] = 0
                        self.sens_pub(topic,json.dump(s))
                    end
                end
                # next part incomplete
                if t[pid].find("dt")
                    for f:t[pid]["dt"]
                        if f.find("bt")
                            for i:0..f['bt'][0]-1
                                # print("button",i,f)
                                var full_f = self.feat_full('bt')
                                for code:f['bt'][1]
                                    var suffix =  str(i) + "_" + self.btn_code(code)
                                    topic = string.format(topic_s,"device_automation",name,full_f + suffix)
                                    var s = self.get_sens(name,full_f + suffix,dev)
                                    s["val_tpl"] = string.format(templ_val_dt,name,full_f,i)
                                    s["pl"] = str(code+1)
                                    s["type"] = "button_"+ self.btn_code(code) + "_press"
                                    s["stype"] = "button" + str(i)
                                    s["atype"] = "trigger"
                                    s["t"] = s["stat_t"]
                                    self.sens_pub(topic,json.dump(s))
                                end
                            end
                        end
                        if f.find("di")
                            var full_f = self.feat_full('di')
                            topic = string.format(topic_s,"number",name,full_f)
                            var s = self.get_sens(name,full_f,dev)
                            var n = string.split(name,"-")
                            s["val_tpl"] = string.format(templ_val_dim,name,n[0],n[1],name,full_f)
                            s.remove("dev_cla")
                            s["ic"] = "mdi:knob"
                            s["cmd_t"] = "Dummy/Dummy"
                            self.sens_pub(topic,json.dump(s))
                        end
                        if f.find("ho")
                            var full_f = self.feat_full('ho')
                            topic = string.format(topic_s,"sensor",name,full_f)
                            var s = self.get_sens(name,full_f,dev)
                            s["val_tpl"] = string.format(templ_val_s,name,full_f)
                            s.remove("dev_cla")
                            s["ic"] = "mdi:knob"
                            self.sens_pub(topic,json.dump(s))
                        end
                    end
                end
            end
        end
    end

    def create_hub_entity(topic_name)
        var topic_s = "homeassistant/%s/%s_%s/config"
        # a virtual BLE Hub
        var p_dev = self.get_dev("Tasmota BLE","Tasmota BLE","BLE Hub","Tasmota","Tasmota","virtual")
        # the specific ESP
        var topic = string.format(topic_s,"sensor","Tasmota_BLE",topic_name)
        var e = self.get_sens(topic_name,"BLE_Node",p_dev,"dBm")
        var node_top = string.format("tele/%s/STATE",topic_name)
        e['stat_t'] = node_top
        e["dev_cla"] = "signal_strength"
        e["ent_cat"] = "diagnostic"
        e["json_attr_t"] = node_top
        e["val_tpl"] = "{{ value_json['Wifi']['Signal'] | is_defined}}"
        self.sens_pub(topic,json.dump(e))
    end

    def read_sensor_cfg()
        # TODO: add error handling
        var f = open("mi32cfg","r")
        var s = f.read()
        return json.load(s)
    end

    def process()
        var host_name = tasmota.cmd("status 5")['StatusNET']['Hostname'][0..13]
        var topic_name = string.replace(host_name,"-","_")
        self.create_hub_entity(topic_name)
        var j = self.read_sensor_cfg()
        for s:j
            var alias = nil
            if s.find("Alias") alias = s["Alias"] end
            self.handle_sens(s["PID"],s["MAC"],s["key"]!="",host_name,topic_name, alias)
            tasmota.gc()
        end
    end

    def inject()
        self.delete_everything = false
        self.process()
    end

    def delete_all_entities()
        self.delete_everything = true
        self.process()
        print("You may have to restart Homeassitant to finish deletions.")
    end
end

disco = DISCO()
disco.inject()
disco = nil
tasmota.gc()
tasmota.cmd("mi32option1 1")
tasmota.cmd("mi32option2 1")
