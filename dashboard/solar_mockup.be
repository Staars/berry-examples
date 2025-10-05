#################################################################################
# Solar Power System Dashboard - Real-time Energy Monitoring
#################################################################################
class SOLAR_DASHBOARD : Driver
  var data_buffers
  var update_index
  var pending_widget
  var current_values
  var time_of_day
  
  static BUFFER_SIZE = 60
  static NUM_METRICS = 12

  def init()
    import MI32
    self.update_index = 0
    self.pending_widget = nil
    self.data_buffers = []
    self.time_of_day = 0  # Simulated time for day/night cycle
    
    # Current instantaneous values
    self.current_values = {
      'solar_power': 0,
      'battery_charge': 0,
      'battery_discharge': 0,
      'grid_import': 0,
      'grid_export': 0,
      'home_consumption': 0,
      'battery_soc': 75,      # State of charge %
      'battery_health': 98,   # Battery health %
      'battery_temp': 25,     # Temperature
      'inverter_efficiency': 0,
      'daily_yield': 0,
      'panel_voltage': 0
    }
    
    # Initialize data buffers
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
    
    var time_ms = tasmota.millis()
    var time_factor = time_ms / 1000.0
    
    # Simulate day/night cycle (0-24 hours in accelerated time)
    self.time_of_day = (time_factor * 0.1) % 24.0
    
    # Solar power generation (0 at night, peak at noon)
    var solar_factor = 0
    if self.time_of_day > 6 && self.time_of_day < 20
      var hour_from_noon = math.abs(13.0 - self.time_of_day)
      solar_factor = math.max(0, 1.0 - (hour_from_noon / 7.0))
      solar_factor = solar_factor * solar_factor  # Parabolic curve
    end
    
    # Add clouds (random dips)
    var cloud = (crypto.random(1)[0] % 100) > 85 ? 0.6 : 1.0
    self.current_values['solar_power'] = int(solar_factor * cloud * 8000 + crypto.random(1)[0] % 200)
    
    # Home consumption: higher in morning and evening
    var consumption_base = 1500
    if self.time_of_day > 6 && self.time_of_day < 9
      consumption_base = 2500  # Morning peak
    elif self.time_of_day > 18 && self.time_of_day < 22
      consumption_base = 3000  # Evening peak
    elif self.time_of_day > 22 || self.time_of_day < 6
      consumption_base = 800   # Night baseline
    end
    self.current_values['home_consumption'] = consumption_base + crypto.random(1)[0] % 300
    
    # Battery charging/discharging logic
    var power_balance = self.current_values['solar_power'] - self.current_values['home_consumption']
    
    if power_balance > 500 && self.current_values['battery_soc'] < 95
      # Charging
      self.current_values['battery_charge'] = int(math.min(power_balance * 0.8, 5000))
      self.current_values['battery_discharge'] = 0
      self.current_values['battery_soc'] = math.min(95, self.current_values['battery_soc'] + 0.02)
    elif power_balance < -200 && self.current_values['battery_soc'] > 20
      # Discharging
      self.current_values['battery_charge'] = 0
      self.current_values['battery_discharge'] = int(math.min(math.abs(power_balance), 4000))
      self.current_values['battery_soc'] = math.max(20, self.current_values['battery_soc'] - 0.03)
    else
      self.current_values['battery_charge'] = 0
      self.current_values['battery_discharge'] = 0
    end
    
    # Grid import/export
    var net_power = power_balance - self.current_values['battery_charge'] + self.current_values['battery_discharge']
    if net_power > 100
      self.current_values['grid_export'] = int(net_power)
      self.current_values['grid_import'] = 0
    elif net_power < -100
      self.current_values['grid_import'] = int(math.abs(net_power))
      self.current_values['grid_export'] = 0
    else
      self.current_values['grid_import'] = 0
      self.current_values['grid_export'] = 0
    end
    
    # Battery health (slowly degrades, then regenerates for demo)
    self.current_values['battery_health'] = 96 + 3 * math.sin(time_factor * 0.03)
    
    # Battery temperature (warmer when charging/discharging)
    var temp_base = 22 + 3 * math.sin(time_factor * 0.05)
    var temp_activity = (self.current_values['battery_charge'] + self.current_values['battery_discharge']) / 500.0
    self.current_values['battery_temp'] = temp_base + temp_activity
    
    # Inverter efficiency
    if self.current_values['solar_power'] > 500
      self.current_values['inverter_efficiency'] = 94 + 3 * math.sin(time_factor * 0.2)
    else
      self.current_values['inverter_efficiency'] = 85 + crypto.random(1)[0] % 5
    end
    
    # Panel voltage
    self.current_values['panel_voltage'] = 380 + solar_factor * 40 + crypto.random(1)[0] % 10
    
    # Daily yield (accumulated)
    self.current_values['daily_yield'] = int((time_factor % 100) * 50 + 2000)
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
      # WIDE: Power Flow Overview (3x1)
      title = "⚡ Power Flow"
      box_class = "box w2 h1"
      
      self.update_buffer(0, self.current_values['solar_power'] / 10)
      self.update_buffer(1, self.current_values['home_consumption'] / 10)
      self.update_buffer(2, self.current_values['battery_charge'] / 10)
      self.update_buffer(3, self.current_values['grid_export'] / 10)
      
      var solar_data = self.buffer_to_csv(self.data_buffers[0])
      var home_data = self.buffer_to_csv(self.data_buffers[1])
      var battery_data = self.buffer_to_csv(self.data_buffers[2])
      
      # Solar (yellow), Home (blue), Battery (green)
      graph_str = format('{L,660,140,(255,200,0):%s|(100,150,255):%s|(0,255,100):%s}', 
                         solar_data, home_data, battery_data)
      
    elif widget_num == 2
      # Battery Status Gauges (1x2 TALL)
      title = "🔋 Battery Status"
      box_class = "box w1 h2"
      
      var soc = self.current_values['battery_soc']
      var health = self.current_values['battery_health']
      
      # State of Charge gauge (red low, yellow mid, green high)
      var soc_gauge = format('{G,320,160,%.1f,0,100,255,50,50,20,255,200,0,50,200,255,0,70,0,255,0,90,%%}', soc)
      
      # Health gauge (green high is good)
      var health_gauge = format('{G,320,160,%.1f,0,100,255,100,0,85,255,200,0,90,200,255,0,95,0,255,100,98,%%}', health)
      
      graph_str = soc_gauge + '<br>' + health_gauge
      
    elif widget_num == 3
      # Solar Production Histogram (1x1)
      title = "☀️ Solar Production"
      self.update_buffer(4, self.current_values['solar_power'] / 10)
      var data = self.buffer_to_csv(self.data_buffers[4])
      
      # Bright yellow-orange gradient
      graph_str = format('{H,320,160,(255,200,0):%s}', data)
      
    elif widget_num == 4
      # WIDE: Grid & Battery Flow (2x1)
      title = "🏠 Energy Balance"
      box_class = "box w2 h1"
      
      self.update_buffer(5, self.current_values['grid_import'] / 10)
      self.update_buffer(6, self.current_values['grid_export'] / 10)
      
      var import_data = self.buffer_to_csv(self.data_buffers[5])
      var export_data = self.buffer_to_csv(self.data_buffers[6])
      
      # Import (red), Export (green)
      graph_str = format('{L,670,140,(255,100,100):%s|(100,255,150):%s}', import_data, export_data)
      
    elif widget_num == 5
      # Battery Temperature Gauge (1x1)
      title = "🌡️ Battery Temp"
      var temp = self.current_values['battery_temp']
      
      # Blue (cold) to yellow to red (hot)
      graph_str = format('{G,320,160,%.1f,0,50,0,150,255,15,100,255,100,20,255,255,0,28,255,150,0,35,°C}', temp)
      
    elif widget_num == 6
      # Home Consumption (1x1)
      title = "🏡 Consumption"
      self.update_buffer(7, self.current_values['home_consumption'] / 10)
      var data = self.buffer_to_csv(self.data_buffers[7])
      
      # Purple-blue histogram
      graph_str = format('{H,320,160,(150,100,255):%s}', data)
    end

    var widget = format('<div class="%s" id="graph%d_widget"><p><strong>%s</strong></p><div>%s</div></div>',
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

solar_dashboard = SOLAR_DASHBOARD()
