#-
 - LED driver for Ulanzi clock written in Berry
 - very simple animation in the style of Matrix
-#

class ULANZI_LED
  var strip
  var positions
  var wait

  def init()
    import crypto
    self.strip = Leds.matrix(32,8, gpio.pin(gpio.WS2812, 32))
    self.wait = 0
    self.positions = []
    for i:range(0,31)
      var y = (crypto.random(1)[0]%10) - 3
      if i > 0
        if y == self.positions[i-1]
          y += 3
        end
      end
      self.positions.push(y)
    end
    tasmota.add_driver(self)
  end

  def getPos(x,y,xMax)
    if y & 0x1
       return y * xMax + (xMax - 1 - x) 
    end
    return y * xMax + x
  end

  def every_50ms()
    if self.wait == 0
      self.wait = 4
      return
    end
    self.wait -= 1

    var s = self.strip
    var x = 0
    for y:self.positions
      if y == 9
        self.positions[x] = -3
      else
        var pos = self.getPos(x,y-1,32)
        if pos > 0
          s.set_pixel_color(pos,0)
        end
        var color = (200 << 8)
        pos = self.getPos(x,y,32)
        if pos > 0
          s.set_pixel_color(pos,color)
        end
        y += 1
        color = (150 << 8)
        pos = self.getPos(x,y,32)
        if pos > 0
          s.set_pixel_color(pos,color)
        end
        y += 1
        color = (100 << 8)
        pos = self.getPos(x,y,32)
        if pos > 0
          s.set_pixel_color(pos,color)
        end
        y += 1
        color = (50 << 8)
        pos = self.getPos(x,y,32)
        if pos > 0
          s.set_pixel_color(pos,color)
        end
        self.positions[x] = y - 2
      end
      x += 1
    end
    s.show()
  end
end

return ULANZI_LED()
