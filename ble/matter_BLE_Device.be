#------------------------------------------------------------------------------
- Matter BLE - app-specific demo subclass
-
- All generic Matter-over-BLE behavior lives in `matter.Device_BLE`
- (lib/libesp32/berry_matter/src/embedded/Matter_zz_Device_BLE.be) and the
- pure BTP protocol is `matter.BTP`
- (lib/libesp32/berry_matter/src/embedded/Matter_BTP.be).
-
- This file only carries the demo light feedback used while commissioning a
- dev board.
-------------------------------------------------------------------------------#
import matter

class MATTER_BLE : matter.Device_BLE
    var have_light

    def on_ble_init()
        try
            import light
            light.set({'bri': 5, 'hue': 150, 'power': true, 'sat': 255})
            self.have_light = (light.get() != nil)
        except ..
            self.have_light = false
        end
    end

    def heart_beat()
        if self.commissioning.is_commissioning_open() == false  return end
        if self.have_light
            import light
            var l = light.get()
            var hue = (l['hue'] + 1) % 256
            light.set({'bri': l['bri'] == 50 ? 5 : 50, 'hue': hue})
        end
    end

    def on_commissioning_success(ctx)
        if self.have_light
            import light
            light.set({'bri':50,'hue':120})    # green
        end
    end

    # ctx = {'reason': <REASON_*>, 'detail': <str>, 'fabric_count': <int>}
    # base class already rearms BLE commissioning - we just show a hint colour
    def on_commissioning_failure(ctx)
        if self.have_light
            import light
            var hue = 0                       # red default
            if   ctx['reason'] == self.REASON_WIFI_FAILED    hue = 30   # orange
            elif ctx['reason'] == self.REASON_WIFI_TIMEOUT   hue = 45   # yellow-orange
            elif ctx['reason'] == self.REASON_PASE_FAILED    hue = 290  # magenta
            elif ctx['reason'] == self.REASON_WINDOW_TIMEOUT hue = 240  # blue
            end
            light.set({'bri':50,'hue':hue})
        end
    end
end

return MATTER_BLE()


# Example for autoexec.be with demo template for dev board
#-
if tasmota.cmd("template").tostring() != {'NAME':'NodeMCU-S3-12k','GPIO':[1,1,1,1,1,416,417,418,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,0],'FLAG':0,'BASE':1}.tostring()
   tasmota.cmd('backlog template {"NAME":"NodeMCU-S3-12k","GPIO":[1,1,1,1,1,416,417,418,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,0],"FLAG":0,"BASE":1}; module 0;')
end
if tasmota.cmd("SSId1")["SSId1"] == "" && tasmota.cmd("SSId2")["SSId2"] == ""
    if tasmota.cmd("so151")["SetOption151"] == "OFF"
        tasmota.cmd("so151 1")
    end
    # this is the state after first flash or reset 1
    tasmota.cmd("so115 1") # make sure BLE is on
    tasmota.set_timer(5000, /->load("matter_BLE_Device.be")) # let the system do some booting
end
-#
