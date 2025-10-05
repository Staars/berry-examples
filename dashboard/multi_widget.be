#################################################################################
# Multi Graph Widget Demo - 8 different graph types (No AJAX)
#################################################################################
class MULTI_GRAPH_WIDGET : Driver
  var data_buffers
  var update_index
  var pending_widget
  var gauge_value
  var gauge_dir
  
  static BUFFER_SIZE = 32
  static NUM_BUFFERS = 3

  def init()
    import MI32
    self.update_index = 0
    self.pending_widget = nil
    self.data_buffers = []
    self.gauge_value = 0
    self.gauge_dir = 1   # 1 = increasing, -1 = decreasing
    
    # Initialize multiple data buffers
    for buf_idx: 0..(self.NUM_BUFFERS-1)
      var buffer = []
      for i: 0..(self.BUFFER_SIZE-1)
        buffer.push(0)
      end
      self.data_buffers.push(buffer)
    end
    
    tasmota.add_driver(self)
  end

  def every_100ms()
    # update gauge value each tick
    self.gauge_value += self.gauge_dir * 2   # step size = 2
    if self.gauge_value >= 100
      self.gauge_value = 100
      self.gauge_dir = -1
    elif self.gauge_value <= 0
      self.gauge_value = 0
      self.gauge_dir = 1
    end
    
    self.update_next_widget()
  end

  def update_data(idx)
    import crypto
    var buffer = self.data_buffers[idx]
    buffer.remove(0)
    buffer.push(crypto.random(1)[0])
  end

  def update_next_widget()
    import MI32
    if MI32.widget() == false
        return
    end
    var widget_num = (self.update_index % 8) + 1
    self.pending_widget = self.get_widget_content(widget_num)
    if MI32.widget(self.pending_widget)
      self.update_index += 1
    end
  end

  def get_widget_content(widget_num)
    var graph_str = ""
    var title = ""
    self.update_data(widget_num%3)

    if widget_num == 1
      title = "Line"
      graph_str = self.build_single_series("l", [255,100,100], 0)
    elif widget_num == 2
      title = "Line+Grid"
      graph_str = self.build_single_series("L", [100,255,100], 0)
    elif widget_num == 3
      title = "Histogram"
      graph_str = self.build_single_series("h", [100,100,255], 1)
    elif widget_num == 4
      title = "Hist+Grid"
      graph_str = self.build_single_series("H", [255,255,100], 1)
    elif widget_num == 5
      title = "Multi-Line"
      graph_str = self.build_multi_series("l", [255,100,255], [100,255,255], 0, 2)
    elif widget_num == 6
      title = "Multi+Grid"
      graph_str = self.build_multi_series("L", [255,150,50], [50,150,255], 0, 2)
    elif widget_num == 7
      title = "Gauge"
      graph_str = format('{g,200,140,%.1f,0,100,0,200,0,0,200,160,0,70,200,0,0,90,%%}',self.gauge_value)
    elif widget_num == 8
      title = "Gauge+Value"
      graph_str = format('{G,200,140,%.1f,0,100,0,200,0,0,200,160,0,70,200,0,0,90,%%}',self.gauge_value)
    end

    var widget = format('<div class="box w1 h1" id="graph%d_widget"><h3>%s</h3><div>%s</div></div>',
                      widget_num, title, graph_str)
    return widget
  end

  def build_single_series(graph_type, color, buffer_idx)
    var data_csv = self.buffer_to_csv(self.data_buffers[buffer_idx])
    var color_str = self.color_to_string(color)
    var graph_str = format('{%s,300,120,%s:%s}', graph_type, color_str, data_csv)
    return graph_str
  end

  def build_multi_series(graph_type, color1, color2, buffer1_idx, buffer2_idx)
    var data1_csv = self.buffer_to_csv(self.data_buffers[buffer1_idx])
    var data2_csv = self.buffer_to_csv(self.data_buffers[buffer2_idx])
    var color1_str = self.color_to_string(color1)
    var color2_str = self.color_to_string(color2)
    var graph_str = format('{%s,300,120,%s:%s|%s:%s}', 
                         graph_type, color1_str, data1_csv, color2_str, data2_csv)
    return graph_str
  end

  def buffer_to_csv(buffer)
      var str_values = []
      for val: buffer
          str_values.push(str(val))
      end
      return str_values.concat(",")
  end

  def color_to_string(color_array)
    return format('(%d,%d,%d)', color_array[0], color_array[1], color_array[2])
  end

  def stop()
    tasmota.remove_driver(self)
  end
end

multi_widget = MULTI_GRAPH_WIDGET()
