#################################################################################
# Air Conditioner Controller Dashboard - Simple Version
#################################################################################
class AC_CONTROLLER : Driver
  var temp_inside_buffer
  var temp_outside_buffer
  var update_index
  var pending_widget
  var current_temp_inside
  var current_temp_outside
  var target_temp
  var operation_mode
  var time_counter
  
  static BUFFER_SIZE = 96  # 24 hours * 4 measurements per hour (every 15 min)

  def init()
    import MI32
    self.update_index = 0
    self.pending_widget = nil
    self.time_counter = 0
    
    # Initialize temperature values
    self.current_temp_inside = 23.0
    self.current_temp_outside = 28.0
    self.target_temp = 22.0
    self.operation_mode = "cooling"
    
    # Initialize temperature buffers
    self.temp_inside_buffer = []
    self.temp_outside_buffer = []
    
    self.init_temperature_history()
    
    tasmota.add_driver(self)
  end

  def init_temperature_history()
    import math
    import crypto
    
    for i: 0..(self.BUFFER_SIZE-1)
      var hour_of_day = (i * 15.0) / 60.0
      
      var outside_temp = 30.0
      if hour_of_day >= 6.0 && hour_of_day <= 18.0
        var hours_from_peak = math.abs(14.0 - hour_of_day)
        outside_temp = 25.0 + 15.0 * math.max(0, 1.0 - (hours_from_peak / 8.0))
      else
        outside_temp = 22.0 + 3.0 * math.sin(hour_of_day * 0.26)
      end
      
      outside_temp += (crypto.random(1)[0] % 20 - 10) / 10.0
      if outside_temp < 20.0
        outside_temp = 20.0
      end
      if outside_temp > 40.0
        outside_temp = 40.0
      end
      
      var inside_temp = 22.0
      if hour_of_day >= 10.0 && hour_of_day <= 16.0
        inside_temp = 22.0 + 2.0 * math.sin((hour_of_day - 10.0) * 0.5)
      else
        inside_temp = 21.0 + math.sin(hour_of_day * 0.3)
      end
      
      inside_temp += (crypto.random(1)[0] % 10 - 5) / 20.0
      if inside_temp < 20.0
        inside_temp = 20.0
      end
      if inside_temp > 25.0
        inside_temp = 25.0
      end
      
      self.temp_inside_buffer.push(int(inside_temp * 10))
      self.temp_outside_buffer.push(int(outside_temp * 10))
    end
  end

  def every_second()
    self.time_counter += 1
    
    if self.time_counter % 15 == 0
      self.measure_temperatures()
    end
    
    self.update_ac_operation()
    self.update_next_widget()
  end

  def measure_temperatures()
    import crypto
    import math
    
    var time_of_day = (self.time_counter / 60.0) % 24.0
    
    var outside_base = 30.0
    if time_of_day >= 6 && time_of_day <= 18
      var hours_from_peak = math.abs(14.0 - time_of_day)
      outside_base = 25.0 + 15.0 * math.max(0, 1.0 - (hours_from_peak / 8.0))
    else
      outside_base = 22.0 + 3.0 * math.sin(time_of_day * 0.26)
    end
    
    self.current_temp_outside = outside_base + (crypto.random(1)[0] % 40 - 20) / 10.0
    if self.current_temp_outside < 20.0
      self.current_temp_outside = 20.0
    end
    if self.current_temp_outside > 40.0
      self.current_temp_outside = 40.0
    end
    
    var temp_drift = (self.current_temp_outside - self.current_temp_inside) * 0.03
    
    if self.operation_mode == "cooling"
      if self.current_temp_inside > self.target_temp
        self.current_temp_inside -= 0.2
      else
        self.current_temp_inside += temp_drift * 0.3
      end
    elif self.operation_mode == "heating"
      if self.current_temp_inside < self.target_temp
        self.current_temp_inside += 0.2
      else
        self.current_temp_inside += temp_drift * 0.3
      end
    else
      self.current_temp_inside += temp_drift * 0.5
    end
    
    self.current_temp_inside += (crypto.random(1)[0] % 10 - 5) / 20.0
    if self.current_temp_inside < 20.0
      self.current_temp_inside = 20.0
    end
    if self.current_temp_inside > 25.0
      self.current_temp_inside = 25.0
    end
    
    self.temp_inside_buffer.remove(0)
    self.temp_inside_buffer.push(int(self.current_temp_inside * 10))
    
    self.temp_outside_buffer.remove(0)
    self.temp_outside_buffer.push(int(self.current_temp_outside * 10))
  end

  def update_ac_operation()
    import crypto
    import math
    
    var temp_diff = self.current_temp_inside - self.target_temp
    
    if temp_diff > 1.5
      self.operation_mode = "cooling"
    elif temp_diff < -1.5
      self.operation_mode = "heating"
    elif math.abs(temp_diff) < 0.5
      var rand = crypto.random(1)[0] % 100
      if rand > 95
        self.operation_mode = "venting"
      elif rand > 90
        self.operation_mode = "drying"
      else
        self.operation_mode = "off"
      end
    end
    
    if crypto.random(1)[0] % 500 == 0
      self.target_temp = 20.0 + (crypto.random(1)[0] % 5)
    end
  end

  def update_next_widget()
    import MI32
    if MI32.widget() == false
      return
    end
    
    var widget_num = (self.update_index % 3) + 1
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
      # Temperature History (2x1)
      title = format('🌡️ Temperature (24h) <span style="float:right;"><span style="color:rgb(255,150,50);">■</span>%.1f°C <span style="color:rgb(50,200,255);">■</span>%.1f°C</span>',
                     self.current_temp_inside, self.current_temp_outside)
      box_class = "box w2 h1"
      
      var inside_data = self.buffer_to_csv_decimal(self.temp_inside_buffer)
      var outside_data = self.buffer_to_csv_decimal(self.temp_outside_buffer)
      
      # Generate time labels for 96 data points (24 hours, 15-min intervals)
      # Show labels every 4 hours: 00:00, 04:00, 08:00, 12:00, 16:00, 20:00, 24:00
      var time_labels = "00:00,04:00,08:00,12:00,16:00,20:00,24:00"
      
      graph_str = format('{L,670,140,(255,150,50):%s|(50,200,255):%s|xl:%s}', 
                         inside_data, outside_data, time_labels)
      
    elif widget_num == 2
      # Target Temperature Gauge (1x1)
      title = "🎯 Target Temperature"
      
      var inside = self.current_temp_inside
      var target = self.target_temp
      
      var stop1 = int(inside - 5)
      var stop2 = int(inside - 2)
      var stop3 = int(inside + 2)
      var stop4 = int(inside + 5)
      
      graph_str = format('{G,320,140,%.1f,%d,%d,100,150,255,%d,100,255,150,%d,255,200,100,%d,255,100,50,%d,°C}',
                         target, int(inside - 8), int(inside + 8), stop1, stop2, stop3, stop4)
      
    elif widget_num == 3
      # Operation Mode (1x1)
      title = "⚙️ Operation Mode"
      
      var mode_text = ""
      var mode_color = ""
      
      if self.operation_mode == "cooling"
        mode_text = "COOLING"
        mode_color = "(100,150,255)"
      elif self.operation_mode == "heating"
        mode_text = "HEATING"
        mode_color = "(255,150,50)"
      elif self.operation_mode == "venting"
        mode_text = "VENTING"
        mode_color = "(100,255,150)"
      elif self.operation_mode == "drying"
        mode_text = "DRYING"
        mode_color = "(255,200,100)"
      else
        mode_text = "OFF"
        mode_color = "(150,150,150)"
      end
      
      var mode_values = []
      for i: 0..29
        mode_values.push("100")
      end
      var mode_csv = mode_values.concat(",")
      
      graph_str = format('{h,320,100,%s:%s}<br><div style="text-align:center;font-size:1.5em;font-weight:bold;margin-top:10px;">%s</div>',
                         mode_color, mode_csv, mode_text)
      
      graph_str = graph_str + format('<div style="text-align:center;margin-top:10px;">Inside: %.1f°C | Outside: %.1f°C</div>',
                                     self.current_temp_inside, self.current_temp_outside)
    end

    var widget = format('<div class="%s" id="graph%d_widget"><p><strong>%s</strong></p><div>%s</div></div>',
                      box_class, widget_num, title, graph_str)
    return widget
  end

  def buffer_to_csv_decimal(buffer)
    var str_values = []
    for val: buffer
      str_values.push(str(val / 10))
    end
    return str_values.concat(",")
  end

  def stop()
    tasmota.remove_driver(self)
  end
end

ac_controller = AC_CONTROLLER()
