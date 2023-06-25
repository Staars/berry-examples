def t() load("improv.be") end

if tasmota.cmd("SSId1")["SSId1"] == "" && tasmota.cmd("SSId2")["SSId2"] == ""
    tasmota.cmd("so115 1")
    tasmota.set_timer(10000, t)
end
