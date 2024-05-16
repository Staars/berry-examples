#-
 - RTTTL driver in Berry using gpio module
-#
class gpio        # for solidification
  static def pin_mode() end
  static def set_pwm_freq() end 
  static def set_pwm() end
  static OUTPUT
end    

#@ solidify:RTTTL
class RTTTL
  # static song ="HauntedHouse: d=4,o=5,b=108: 2a4, 2e, 2d#, 2b4, 2a4, 2c, 2d, 2a#4, 2e., e, 1f4, 1a4, 1d#, 2e., d, 2c., b4, 1a4, 1p, 2a4, 2e, 2d#, 2b4, 2a4, 2c, 2d, 2a#4, 2e., e, 1f4, 1a4, 1d#, 2e., d, 2c., b4, 1a4"
  static song ="dkong:d=4,o=5,b=160:2c,8d.,d#.,c.,16b,16c6,16b,16c6,16b,16c6,16b,16c6,16b,16c6,16b,16c6,16b,2c6"
  # static song = "TakeOnMe:d=4,o=4,b=160:8f#5,8f#5,8f#5,8d5,8p,8b,8p,8e5,8p,8e5,8p,8e5,8g#5,8g#5,8a5,8b5,8a5,8a5,8a5,8e5,8p,8d5,8p,8f#5,8p,8f#5,8p,8f#5,8e5,8e5,8f#5,8e5,8f#5,8f#5,8f#5,8d5,8p,8b,8p,8e5,8p,8e5,8p,8e5,8g#5,8g#5,8a5,8b5,8a5,8a5,8a5,8e5,8p,8d5,8p,8f#5,8p,8f#5,8p,8f#5,8e5,8e5"
  var name
  var duration, octave, bpm, loop_ticks
  var track, pos, remaining
  var note_val, note_octave, note_left

  def init()
    import string
    import gpio
    import math

    if global.rtttl_pin == nil # never call this twice after boot
      gpio.pin_mode(15,gpio.OUTPUT) # PWM buzzer pin of the Ulanzi clock = 15
      global.rtttl_pin = true
    end
    var parts = string.split(self.song,":")
    self.name = parts[0]
    print("Loading song:",self.name)
    var header = parts[1]
    var pos = string.find(header,"d")
    if pos>-1 self.duration = int(header[pos+2]) end
    pos = string.find(header,"o")
    if pos>-1 self.octave = int(header[pos+2]) end
    pos = string.find(header,"b")
    if pos>-1 self.bpm = int(header[pos+2..]) end # a bit unsafe
    self.track = string.split(parts[2],",")
    var loop_ticks = (self.bpm/60.0)/self.duration/0.05 # still unsure about
    self.loop_ticks = loop_ticks
    if loop_ticks%8 > 0
      self.loop_ticks = (math.ceil(loop_ticks/8))*8
    end
    print("Note duration:",self.duration,"Octave:",self.octave,"BPM:",self.bpm,"->loops per note:",self.loop_ticks)
    self.pos = 0
    self.note_left = 0
    print("Track length:",size(self.track))
    tasmota.add_driver(self)
  end

  def note_to_int(note)
    # from esp32-hal-led.c - but we return no sharp and no flat
    #   C        C#       D        Eb       E        F       F#        G       G#        A       Bb        B
    if
      note == "c" return 0
    elif
      note == "d" return 2
    elif
      note == "e" return 4
    elif
      note == "f" return 5
    elif
      note == "g" return 7
    elif
      note == "a" return 9
    else # note == "b" 
      return 11
    end
  end

  def note_to_freq(note, octave)
    #               C        C#       D        Eb       E        F       F#        G       G#        A       Bb        B  from esp32-hal-led.c
    var freqs = [4186,    4435,    4699,    4978,    5274,    5588,    5920,    6272,    6645,    7040,    7459,    7902]    
    if (octave > 8 || note > 11)
        return 0
    end
    return  freqs[note] / (1 << (8-octave))
  end

  def is_number(char)
    import string
    if string.byte(char) > 0x29 && string.byte(char) < 0x3a
      return true
    end
    return false
  end

  def parse_note(note)
    var pos = 0
    var length = size(note)
    self.note_left = self.loop_ticks / self.duration # default
    self.note_octave = self.octave # default

    while note[pos] == " " pos+= 1 end # skip white space

    if self.is_number(note[pos])
      self.note_left = self.loop_ticks / int(note[pos])
      print("new length:",self.note_left)
      pos += 1
    end
    if self.is_number(note[pos])
      if note[pos] == '6'
        self.note_left = self.loop_ticks / 16 # this can only be the 6 of 16
      else
        self.note_left = self.loop_ticks / 32 # 32 is the fastest we support
      end
      print("new length:",self.note_left)
      pos += 1
    end

    self.note_val = self.note_to_int(note[pos]) # maybe the only value
    pos += 1
    if pos == length return end

    if note[pos] == "#" # sharp?
      self.note_val += 1
      if self.note_val > 11
        print("Invalid RTTTL !!")
        self.note_val = 11
      end
      pos+= 1 
      if pos == length return end
    end

    if note[pos] == "." # punctuated note length
       self.note_left = self.note_left + (self.note_left/2)
       print("punctuated length:",self.note_left)
       pos+= 1
       if pos == length return end
    end

    if self.is_number(note[pos])
      self.note_octave = int(note[pos])
      pos += 1
    end
  end

  def every_50ms()
    import gpio
    if self.note_left > 0
      self.note_left -= 1 # note still active
      return
    else
      self.pos += 1 # next note
    end
    if self.pos > size(self.track) - 1
      print("Song finished!")
      gpio.set_pwm(15,0) # stop
      tasmota.remove_driver(self)
      return
    end
    print("Will parse:", self.track[self.pos])
    self.parse_note(self.track[self.pos])
    print("Note, Octave, Length:",self.note_val,self.note_octave, self.note_left)
    var freq = self.note_to_freq(self.note_val,self.note_octave - 1)
    gpio.set_pwm_freq(15,freq) # play note
    gpio.set_pwm(15,30) # pretty low volume
  end

end
