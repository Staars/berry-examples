class Leds end    # for solidification

class gpio        # for solidification
  static def pin() end 
  static WS2812
end    

#@ solidify:ULANIM
class ULANIM
  var cmatrix, clist
  var strip
  var animation, current_animation, delay

  def init()
    self.strip = Leds.matrix(32,8, gpio.pin(gpio.WS2812, 32))
    self.initCMatrix()
    self.loadAnimation()
    tasmota.add_driver(self)
  end

  def every_50ms()
    if self.current_animation == nil
      return
    end

    if self.delay > 0 #speed/delay
      self.delay -= 1
      return
    end
    self.updateCList()
    self.draw()
    self.nextAnimation()
  end

  def loadAnimation()
    self.animation = [ # color, cycles, delay, mode
      [0x0000ff,8,2,4],
      [0x0000ff,7,2,5],
      [0x00ffff,8,2,4],
      [0x00ffff,7,2,5],
      [0x00ff00,8,0,4],
      [0x00ff00,7,1,5],
      [0xffff00,8,0,4],
      [0xffff00,7,1,5],
      [0xff0000,8,0,4],
      [0xff0000,7,1,5],
      [0xffffff,8,0,4],
      [0xffffff,7,1,5],
      # [0xffffff,16,0,0],
      # [0x919191,32,1,2],
      # [0xff0000,8,0,0],
      # [0x990000,24,1,2],
      # [0xff00ff,8,0,0],
      # [0xaa00aa,24,1,2],
      # [0x00ff00,8,0,0],
      # [0x009900,32,1,2],
      # [0xff0000,8,0,3],
      # [0xaa0000,32,1,0],
      # [0x0000ff,16,0,0],
      # [0x0000aa,8,7,3],
      # [0x0000aa,8,7,3],
      # [0x0000ff,7,0,4],
      # [0x0000ff,7,0,5],
    ]
    self.current_animation = [0,0,0,0]
    self.delay = 0
    self.colorFromSeed()
    self.clist = self.current_animation[4]
  end

  def updateCList()
    var step = self.current_animation[1]
    var mode = self.current_animation[3]
    if mode == 0 || mode == 2
      var last = self.clist[0]
      for i:range(0,6)
        self.clist[i] = self.clist[i+1]
      end
      self.clist[7] = last
    elif mode == 1 || mode == 3
      var first = self.clist[7]
      for i:range(6,0,-1)
        self.clist[i+1] = self.clist[i]
      end
      self.clist[0] = first
    elif mode == 4
      var _clist = self.current_animation[4]
      var c = 7 - self.current_animation[1] % 8
      self.clist = [0,0,0,0,0,0,0,0]
      for i:range(7,7-c,-1)
        self.clist[i] = _clist[i]
      end
    elif mode == 5
      var _clist = self.current_animation[4]
      var c = self.current_animation[1] % 8
      self.clist = [0,0,0,0,0,0,0,0]
      for i:range(0,c)
        self.clist[7-i] = _clist[i]
      end
    end
  end

  def nextAnimation()
    if self.current_animation[1] > 0 # cycles
      self.current_animation[1] -= 1
    else
      if size(self.animation) == 0
        self.current_animation = nil
        return
      end
      self.current_animation = self.animation[0]
      self.animation = self.animation[1..]
      self.colorFromSeed()
      self.clist = self.current_animation[4]
      # print("## next animation",self.current_animation)
    end
    self.delay = self.current_animation[2]
  end

  def colorFromSeed()
    var color = self.current_animation[0]
    var divider = 8
    var mode = self.current_animation[3]
    if mode == 2 || mode == 3
      divider = 9
    end

    var r = (((color >> 16) / divider) << 16) & 0xff0000
    var g = ((((color >> 8) & 0xff) / divider) << 8) & 0xff00
    var b = (((color & 0xff) / divider))
    var step = r | g | b

    # print(f"{r:x} {g:x} {b:x}  {step:x}")
    var clist = [color,0,0,0,0,0,0,0]
    for i:range(1,7)
      clist[i] = clist[i-1] - step
    end
    if mode == 2 || mode == 3
      clist = clist[4..7] + clist[4..7].reverse()
    end
    self.current_animation.push(clist)
    self.clist = clist
    # print(self.clist)
  end

  def draw()
    var setc = /i,c->self.strip.set_pixel_color(i,c)
    var cl = self.clist
    var cm = self.cmatrix
    for i:range(0,255)
      setc(i,cl[cm[i]])
    end
    self.strip.show()
  end

  def initCMatrix()
    var offset = [0]
    self.cmatrix = bytes(-256)
    for y:range(0,7)
      for x:range(0,31)
        for o:offset
          if x >= o && x < (32 - o)
            self.cmatrix[32*y + x] = o
          end
        end
      end
      # print(self.cmatrix[32*y..32*y+31])
      offset.push(offset[-1]+1)
    end
  end

end

# var u =  ULANIM()
