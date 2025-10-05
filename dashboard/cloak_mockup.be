#################################################################################
# Keycloak-Style Metrics Dashboard - Flashy Edition
#################################################################################
class KEYCLOAK_DASHBOARD : Driver
  var data_buffers
  var update_index
  var pending_widget
  var current_values
  
  static BUFFER_SIZE = 60  # Longer buffers for wide graphs
  static NUM_METRICS = 10

  def init()
    import MI32
    self.update_index = 0
    self.pending_widget = nil
    self.data_buffers = []
    
    # Current instantaneous values for gauges
    self.current_values = {
      'login_rate': 0,
      'error_rate': 0,
      'active_sessions': 0,
      'db_connections': 0,
      'response_time': 0,
      'cpu_usage': 0,
      'memory_usage': 0,
      'thread_count': 0,
      'cache_hit_rate': 0,
      'network_throughput': 0
    }
    
    # Initialize data buffers for time series
    for idx: 0..(self.NUM_METRICS-1)
      var buffer = []
      for i: 0..(self.BUFFER_SIZE-1)
        buffer.push(0)
      end
      self.data_buffers.push(buffer)
    end
    
    tasmota.add_driver(self)
  end

  def every_100ms()
    self.update_metrics()
    self.update_next_widget()
  end

  def update_metrics()
    import crypto
    import math
    
    # Simulate realistic metric patterns
    var time_factor = tasmota.millis() / 1000.0
    
    # Login rate: varies between 0-80 logins/sec with dramatic spikes
    var spike = (crypto.random(1)[0] % 100) > 92
    self.current_values['login_rate'] = spike ? (60 + crypto.random(1)[0] % 20) : math.abs(30 + 25 * math.sin(time_factor * 0.4))
    
    # Error rate: low baseline with occasional danger spikes
    var error_spike = (crypto.random(1)[0] % 100) > 94
    self.current_values['error_rate'] = error_spike ? (15 + crypto.random(1)[0] % 15) : (1 + crypto.random(1)[0] % 4)
    
    # Active sessions: dramatic waves between 100-400
    self.current_values['active_sessions'] = 250 + 150 * math.sin(time_factor * 0.2) + crypto.random(1)[0] % 30
    
    # DB connections: varies around capacity
    self.current_values['db_connections'] = 18 + 8 * math.sin(time_factor * 0.6) + crypto.random(1)[0] % 4
    
    # Response time: varies 50-400ms with spikes
    var latency_spike = (crypto.random(1)[0] % 100) > 90
    self.current_values['response_time'] = latency_spike ? (300 + crypto.random(1)[0] % 100) : (120 + 80 * math.sin(time_factor * 0.7))
    
    # CPU usage: dynamic 20-85%
    self.current_values['cpu_usage'] = 55 + 30 * math.sin(time_factor * 0.35) + crypto.random(1)[0] % 10
    
    # Memory usage: slowly climbing pattern
    self.current_values['memory_usage'] = 50 + 25 * math.sin(time_factor * 0.12) + (time_factor % 20)
    
    # Thread count: active threads 30-70
    self.current_values['thread_count'] = 50 + 20 * math.sin(time_factor * 0.5)
    
    # Cache hit rate: 75-99%
    self.current_values['cache_hit_rate'] = 87 + 10 * math.sin(time_factor * 0.25)
    
    # Network throughput: 0-100 MB/s
    self.current_values['network_throughput'] = math.abs(50 + 40 * math.sin(time_factor * 0.45) + crypto.random(1)[0] % 15)
  end

  def update_buffer(idx, value)
    var buffer = self.data_buffers[idx]
    buffer.remove(0)
    buffer.push(int(value))
  end

  def update_next_widget()
    import MI32
    if MI32.widget() == false
      return
    end
    
    var widget_num = (self.update_index % 6) + 1
    self.pending_widget = self.get_widget_content(widget_num)
    
    if MI32.widget(self.pending_widget)
      self.update_index += 1
    end
  end

  def get_widget_content(widget_num)
    var graph_str = ""
    var title = ""
    var box_class = "box w1 h1"
    
    if widget_num == 1
      # WIDE: Authentication Flow - 3 lines over time (3x1 box)
      title = "🔐 Authentication Flow"
      box_class = "box w3 h1"
      self.update_buffer(0, self.current_values['login_rate'])
      self.update_buffer(1, self.current_values['error_rate'])
      self.update_buffer(2, self.current_values['active_sessions'] / 5)  # Scale down for visibility
      
      var data1 = self.buffer_to_csv(self.data_buffers[0])
      var data2 = self.buffer_to_csv(self.data_buffers[1])
      var data3 = self.buffer_to_csv(self.data_buffers[2])
      
      # Logins (cyan), Errors (red), Sessions/5 (yellow)
      graph_str = format('{L,1000,180,(0,200,255):%s|(255,50,50):%s|(255,200,0):%s}', 
                         data1, data2, data3)
      
    elif widget_num == 2
      # TALL: System Health Gauges (1x2 box)
      title = "⚡ System Health"
      box_class = "box w1 h2"
      
      var cpu = self.current_values['cpu_usage']
      var mem = self.current_values['memory_usage']
      var cache = self.current_values['cache_hit_rate']
      
      # CPU Gauge (top)
      var cpu_gauge = format('{G,200,200,%.1f,0,100,0,255,150,0,100,255,50,50,255,180,0,70,200,100,0,85,%%}', cpu)
      
      # Memory Gauge (bottom)  
      var mem_gauge = format('{G,200,200,%.1f,0,100,0,200,255,0,50,255,200,40,255,100,200,65,255,0,150,80,%%}', mem)
      
      graph_str = cpu_gauge + '<br>' + mem_gauge
      
    elif widget_num == 3
      # Response Time Histogram with dramatic colors (1x1)
      title = "⚡ Response Time"
      self.update_buffer(3, self.current_values['response_time'])
      var data = self.buffer_to_csv(self.data_buffers[3])
      # Purple to pink gradient
      graph_str = format('{H,320,140,(200,50,255):%s}', data)
      
    elif widget_num == 4
      # WIDE: Network & DB Combined (2x1 box)
      title = "🌐 Infrastructure"
      box_class = "box w2 h1"
      
      self.update_buffer(4, self.current_values['network_throughput'])
      self.update_buffer(5, self.current_values['db_connections'] * 3)  # Scale up
      
      var net_data = self.buffer_to_csv(self.data_buffers[4])
      var db_data = self.buffer_to_csv(self.data_buffers[5])
      
      # Network (bright green), DB (orange)
      graph_str = format('{L,670,140,(0,255,100):%s|(255,150,0):%s}', net_data, db_data)
      
    elif widget_num == 5
      # Cache Hit Rate - Big Gauge (1x1)
      title = "💾 Cache Hit Rate"
      var cache = self.current_values['cache_hit_rate']
      
      # Green to yellow gradient (high is good)
      graph_str = format('{G,320,140,%.1f,0,100,255,200,0,60,255,255,0,75,100,255,100,85,0,255,0,95,%%}', cache)
      
    elif widget_num == 6
      # Active Sessions - Dramatic histogram (1x1)
      title = "👥 Active Sessions"
      self.update_buffer(6, self.current_values['active_sessions'])
      var data = self.buffer_to_csv(self.data_buffers[6])
      
      # Bright cyan histogram
      graph_str = format('{H,320,140,(0,255,255):%s}', data)
    end

    var widget = format('<div class="%s" id="graph%d_widget"><p>%s</p><div>%s</div></div>',
                      box_class, widget_num, title, graph_str)
    return widget
  end

  def buffer_to_csv(buffer)
    var str_values = []
    for val: buffer
      str_values.push(str(val))
    end
    return str_values.concat(",")
  end

  def stop()
    tasmota.remove_driver(self)
  end
end

keycloak_dashboard = KEYCLOAK_DASHBOARD()
