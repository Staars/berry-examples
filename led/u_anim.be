
class ULANIM
  var cmatrix, clist
  var strip
  var animation, current_animation, delay

  def init()
    self.strip = Leds.matrix(32,8, gpio.pin(gpio.WS2812, 32))
    self.clist = [0,0,0,0,0,0,0,0]
    self.initCtable()
    self.draw()
    self.animation = [ # color, cycles, delay, mode
      [0xeeeeee,8,0,0],
      [0xeeeeee,8,0,1],
      [0x555555,48,2,0],
      [0xff00ff,8,0,0],
      [0xff00ff,8,0,1],
      [0xaa00aa,32,2,0],
      [0xff0000,8,0,1],
      [0xff0000,8,0,0],
      [0xaa0000,32,2,0],
      [0x0000ff,16,0,1],
      [0x0000aa,8,2,2]
    ]
    self.current_animation = [0,0,0,0]
    self.delay = 0
    tasmota.add_driver(self)
  end

  def every_50ms()
    if self.current_animation == nil
      return
    end
    var a = self.current_animation

    if self.delay > 0 #speed/delay
      self.delay -= 1
      return
    end

    var last = self.clist[0]
    for i:range(0,6)
      self.clist[i] = (self.clist[i+1])
    end
    if a[3] != 2
      self.clist[7] = last
    else
      self.clist[7] = 0
    end

    # print(self.clist)
    self.draw()
    self.nextAnimation()
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
      self.colorFromSeed(self.current_animation[0],self.current_animation[3])
      print("## next animation",self.current_animation)
    end
    self.delay = self.current_animation[2]
  end

  def colorFromSeed(color, reverse)
    var r = (((color >> 16) / 8) << 16) & 0xff0000
    var g = ((((color >> 8) & 0xff) / 8) << 8) & 0xff00
    var b = (((color & 0xff) / 8))
    var step = r | g | b

    # print(f"{r:x} {g:x} {b:x}  {step:x}")
    self.clist[0] = color
    for i:range(1,7)
      self.clist[i] = self.clist[i-1] - step
    end
    if reverse
      self.clist.reverse()
    end
    print(self.clist)
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

  def initCtable()
    self.cmatrix = []
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

var u =  ULANIM()
