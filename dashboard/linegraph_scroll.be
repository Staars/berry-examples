#################################################################################
# Demo Graph Widget - Using built-in graph with AJAX updates
#################################################################################
class DEMO_GRAPH_WIDGET : Driver
  var initialized
  var data_buffer
  static BUFFER_SIZE = 64

  def init()
    import MI32
    self.initialized = false
    self.data_buffer = []
    # Initialize with some random data
    for i: 0..(self.BUFFER_SIZE-1)
      self.data_buffer.push(0)
    end
    var cbp = tasmota.gen_cb(/->self.widget_cb())
    MI32.widget("", cbp)
    tasmota.add_driver(self)
  end

  def widget_cb()
    import webserver
    import MI32
    if webserver.arg_size() == 0
      log("Demo: pageload", 1)
      self.initialized = false
      return
    end
    if self.initialized == false
      self.send_widget()
      self.initialized = true
      return
    end
    if webserver.has_arg("data")
      self.send_data()
      return
    end
  end

  def update_data()
    import crypto
    # Remove oldest value and add new random value
    self.data_buffer.remove(0)
    self.data_buffer.push(crypto.random(1)[0])
  end

    def send_data()
        import webserver
        self.update_data()
        var current = self.data_buffer[size(self.data_buffer)-1]
        var sum = 0
        var max_val = 0
        for val: self.data_buffer
            sum += val
            if val > max_val
                max_val = val
            end
        end
        var avg = real(sum) / real(size(self.data_buffer))
        var str_values = []
        for val: self.data_buffer
            str_values.push(str(val))
        end
        var csv = str_values.concat(",")

        var graph_str = format("{L,600,255,(0,255,128):%s}", csv)
        var response = format('{"graph":"%s","current":%d,"avg":%.1f,"max":%d}', graph_str, current, avg, max_val)
        webserver.content_response(response)
    end


  def send_widget()
    import MI32
    var widget = '<div class="box w2 h2" id="demo_graph">'
        '<h3>Live Data Stream</h3>'
        '<div class="graph-container">'
          '<div id="graph_area">Initializing...</div>'
          '<div id="current">--</div>'
          '<div>Current</div>'
          '<div id="avg">--</div>'
          '<div>Average</div>'
          '<div id="max">--</div>'
          '<div>Peak</div>'
        '</div>'
        '<script>'
        'if(!window.demoGraphInit){'
        'window.demoGraphInit = true;'
        'window.updateDemoGraph = function(){'
        'fetch("/m32?data=1").then(r=>r.json()).then(data=>{'
        'eb("graph_area").innerHTML = render(data.graph);'
        'eb("current").textContent = data.current;'
        'eb("avg").textContent = data.avg.toFixed(1);'
        'eb("max").textContent = data.max;'
        '});'
        '};'
        'updateDemoGraph();'
        'setInterval(updateDemoGraph, 250);'
        '}'
        '</script>'
    
    return MI32.widget(widget)
  end

  def stop()
    tasmota.remove_driver(self)
  end
end

demo_widget = DEMO_GRAPH_WIDGET()
