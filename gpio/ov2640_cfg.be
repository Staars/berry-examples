# OV2640 SCCB Bitbang Driver for Berry/Tasmota

import gpio

class OV2640_SCCB
  var sda_pin
  var scl_pin
  var addr
  
  static ADDR = 0x30
  static BANK_SEL = 0xFF
  static BANK_SENSOR = 0x01
  static BANK_DSP = 0x00
  
  def init(sda, scl)
    self.sda_pin = sda
    self.scl_pin = scl
    self.addr = self.ADDR
    
    gpio.pin_mode(self.sda_pin, gpio.OUTPUT)
    gpio.pin_mode(self.scl_pin, gpio.OUTPUT)
    
    gpio.digital_write(self.sda_pin, gpio.HIGH)
    gpio.digital_write(self.scl_pin, gpio.HIGH)
    
    print("OV2640_SCCB: Initializing bitbang on SDA=", sda, " SCL=", scl)
    self.detect()
  end
  
  def delay()
    var x = 1
  end
  
  def start()
    gpio.digital_write(self.sda_pin, gpio.HIGH)
    gpio.digital_write(self.scl_pin, gpio.HIGH)
    self.delay()
    gpio.digital_write(self.sda_pin, gpio.LOW)
    self.delay()
    gpio.digital_write(self.scl_pin, gpio.LOW)
    self.delay()
  end
  
  def stop()
    gpio.digital_write(self.sda_pin, gpio.LOW)
    gpio.digital_write(self.scl_pin, gpio.LOW)
    self.delay()
    gpio.digital_write(self.scl_pin, gpio.HIGH)
    self.delay()
    gpio.digital_write(self.sda_pin, gpio.HIGH)
    self.delay()
  end
  
  def write_bit(bit)
    gpio.digital_write(self.scl_pin, gpio.LOW)
    if bit
      gpio.digital_write(self.sda_pin, gpio.HIGH)
    else
      gpio.digital_write(self.sda_pin, gpio.LOW)
    end
    self.delay()
    gpio.digital_write(self.scl_pin, gpio.HIGH)
    self.delay()
    gpio.digital_write(self.scl_pin, gpio.LOW)
  end
  
  def read_bit()
    gpio.digital_write(self.scl_pin, gpio.LOW)
    gpio.pin_mode(self.sda_pin, gpio.INPUT)
    self.delay()
    gpio.digital_write(self.scl_pin, gpio.HIGH)
    self.delay()
    var bit = gpio.digital_read(self.sda_pin)
    gpio.digital_write(self.scl_pin, gpio.LOW)
    gpio.pin_mode(self.sda_pin, gpio.OUTPUT)
    return bit
  end
  
  def write_byte(data)
    var i = 7
    while i >= 0
      self.write_bit((data >> i) & 1)
      i -= 1
    end
    var ack = self.read_bit()
    return ack == 0
  end
  
  def read_byte()
    gpio.pin_mode(self.sda_pin, gpio.INPUT)
    var data = 0
    var i = 7
    while i >= 0
      gpio.digital_write(self.scl_pin, gpio.LOW)
      self.delay()
      gpio.digital_write(self.scl_pin, gpio.HIGH)
      self.delay()
      if gpio.digital_read(self.sda_pin)
        data = data | (1 << i)
      end
      i -= 1
    end
    gpio.digital_write(self.scl_pin, gpio.LOW)
    gpio.pin_mode(self.sda_pin, gpio.OUTPUT)
    
    gpio.digital_write(self.sda_pin, gpio.HIGH)
    self.delay()
    gpio.digital_write(self.scl_pin, gpio.HIGH)
    self.delay()
    gpio.digital_write(self.scl_pin, gpio.LOW)
    
    return data
  end
  
  def write_reg(reg, val)
    self.start()
    if !self.write_byte(self.addr << 1)
      self.stop()
      return false
    end
    if !self.write_byte(reg)
      self.stop()
      return false
    end
    if !self.write_byte(val)
      self.stop()
      return false
    end
    self.stop()
    return true
  end
  
  def read_reg(reg)
    self.start()
    if !self.write_byte(self.addr << 1)
      self.stop()
      return nil
    end
    if !self.write_byte(reg)
      self.stop()
      return nil
    end
    self.stop()
    
    tasmota.delay(1)
    
    self.start()
    if !self.write_byte((self.addr << 1) | 1)
      self.stop()
      return nil
    end
    var data = self.read_byte()
    self.stop()
    
    return data
  end
  
  def detect()
    print("OV2640: Detecting camera...")
    
    self.write_reg(self.BANK_SEL, self.BANK_SENSOR)
    tasmota.delay(5)
    
    var id_h = self.read_reg(0x0A)
    var id_l = self.read_reg(0x0B)
    
    if id_h == nil || id_l == nil
      print("OV2640: Failed to read chip ID")
      return false
    end
    
    print(format("OV2640: Read ID: 0x%02X%02X", id_h, id_l))
    
    if id_h == 0x26 && id_l == 0x42
      print("OV2640: Camera detected!")
      return true
    else
      print(format("OV2640: Wrong ID (expected 0x2642)"))
      return false
    end
  end
  
  def reset()
    print("OV2640: WARNING - reset disabled for stability")
    return self
  end
  
  def mirror(enable)
    self.write_reg(self.BANK_SEL, self.BANK_SENSOR)
    var reg04 = self.read_reg(0x04)
    if reg04 != nil
      if enable
        reg04 = reg04 | 0x80  # HFLIP_IMG
        reg04 = reg04 | 0x08  # HREF_EN
      else
        reg04 = reg04 & 0x7F  # Clear HFLIP_IMG
        reg04 = reg04 & 0xF7  # Clear HREF_EN
      end
      self.write_reg(0x04, reg04)
    end
    return self
  end
  
  def flip(enable)
    self.write_reg(self.BANK_SEL, self.BANK_SENSOR)
    var reg04 = self.read_reg(0x04)
    if reg04 != nil
      if enable
        reg04 = reg04 | 0x40  # VFLIP_IMG
        reg04 = reg04 | 0x10  # VREF_EN
      else
        reg04 = reg04 & 0xBF  # Clear VFLIP_IMG
        reg04 = reg04 & 0xEF  # Clear VREF_EN
      end
      self.write_reg(0x04, reg04)
    end
    return self
  end
  
  def mirror_flip(m, f)
    self.write_reg(self.BANK_SEL, self.BANK_SENSOR)
    var reg04 = self.read_reg(0x04)
    if reg04 != nil
      # Clear all flip and reference bits
      reg04 = reg04 & 0x67  # Keep only bits not involved in flip/ref
      if m
        reg04 = reg04 | 0x80  # HFLIP_IMG
        reg04 = reg04 | 0x08  # HREF_EN
      end
      if f
        reg04 = reg04 | 0x40  # VFLIP_IMG
        reg04 = reg04 | 0x10  # VREF_EN
      end
      self.write_reg(0x04, reg04)
    end
    return self
  end
  
  def brightness(level)
    if level < -2 level = -2 end
    if level > 2 level = 2 end
    
    var brightness_regs = [
      [0x7C, 0x00, 0x04, 0x09, 0x00],
      [0x7C, 0x00, 0x04, 0x0B, 0x00],
      [0x7C, 0x00, 0x04, 0x00, 0x00],
      [0x7C, 0x00, 0x04, 0x0D, 0x00],
      [0x7C, 0x00, 0x04, 0x0F, 0x00]
    ]
    
    self.write_reg(self.BANK_SEL, self.BANK_DSP)
    var regs = brightness_regs[level + 2]
    var i = 0
    while i < 5
      self.write_reg(0x7C + i, regs[i])
      i += 1
    end
    return self
  end
  
  def contrast(level)
    if level < -2 level = -2 end
    if level > 2 level = 2 end
    
    var contrast_regs = [
      [0x7C, 0x00, 0x04, 0x1C, 0x00, 0x14, 0x00],
      [0x7C, 0x00, 0x04, 0x1E, 0x00, 0x18, 0x00],
      [0x7C, 0x00, 0x04, 0x20, 0x00, 0x1C, 0x00],
      [0x7C, 0x00, 0x04, 0x22, 0x00, 0x20, 0x00],
      [0x7C, 0x00, 0x04, 0x24, 0x00, 0x24, 0x00]
    ]
    
    self.write_reg(self.BANK_SEL, self.BANK_DSP)
    var regs = contrast_regs[level + 2]
    var i = 0
    while i < 7
      self.write_reg(0x7C + i, regs[i])
      i += 1
    end
    return self
  end
  
  def saturation(level)
    if level < -2 level = -2 end
    if level > 2 level = 2 end
    
    var saturation_regs = [
      [0x7C, 0x00, 0x02, 0x40, 0x40],
      [0x7C, 0x00, 0x02, 0x48, 0x48],
      [0x7C, 0x00, 0x02, 0x58, 0x58],
      [0x7C, 0x00, 0x02, 0x68, 0x68],
      [0x7C, 0x00, 0x02, 0x78, 0x78]
    ]
    
    self.write_reg(self.BANK_SEL, self.BANK_DSP)
    var regs = saturation_regs[level + 2]
    var i = 0
    while i < 5
      self.write_reg(0x7C + i, regs[i])
      i += 1
    end
    return self
  end
  
  def colorbar(enable)
    self.write_reg(self.BANK_SEL, self.BANK_SENSOR)
    var com7 = self.read_reg(0x12)
    if com7 != nil
      if enable
        com7 = com7 | 0x02
      else
        com7 = com7 & 0xFD
      end
      self.write_reg(0x12, com7)
    end
    return self
  end
  
  def info()
    self.write_reg(self.BANK_SEL, self.BANK_SENSOR)
    var reg04 = self.read_reg(0x04)
    
    if reg04 == nil
      print("OV2640: Failed to read register")
      return
    end
    
    var mirror_on = (reg04 & 0x80) != 0
    var flip_on = (reg04 & 0x40) != 0
    
    print(format("OV2640: Mirror=%s Flip=%s", 
                 mirror_on ? "YES" : "no", 
                 flip_on ? "YES" : "no"))
    
    self.write_reg(self.BANK_SEL, self.BANK_DSP)
    var ctrl1 = self.read_reg(0xC0)
    if ctrl1 != nil
      print(format("OV2640: CTRL1=0x%02X", ctrl1))
    end
    
    self.read_window()
  end
  
  def set_reg_bits(bank, reg, offset, mask, value)
    self.write_reg(self.BANK_SEL, bank)
    var current = self.read_reg(reg)
    if current != nil
      var new_val = (current & ~(mask << offset)) | ((value & mask) << offset)
      self.write_reg(reg, new_val)
      return true
    end
    return false
  end
  
  def agc(enable)
    return self.set_reg_bits(self.BANK_SENSOR, 0x13, 2, 1, enable ? 1 : 0)
  end
  
  def aec(enable)
    return self.set_reg_bits(self.BANK_SENSOR, 0x13, 0, 1, enable ? 1 : 0)
  end
  
  def awb(enable)
    return self.set_reg_bits(self.BANK_DSP, 0xC0, 3, 1, enable ? 1 : 0)
  end
  
  def awb_gain(enable)
    return self.set_reg_bits(self.BANK_DSP, 0xC0, 2, 1, enable ? 1 : 0)
  end
  
  def night_mode(enable)
    return self.set_reg_bits(self.BANK_DSP, 0xC1, 6, 1, enable ? 0 : 1)
  end
  
  def exposure(value)
    if value < 0 value = 0 end
    if value > 1200 value = 1200 end
    
    self.write_reg(self.BANK_SEL, self.BANK_SENSOR)
    
    var reg04 = self.read_reg(0x04)
    if reg04 != nil
      reg04 = (reg04 & 0xFC) | (value & 0x03)
      self.write_reg(0x04, reg04)
    end
    
    self.write_reg(0x10, (value >> 2) & 0xFF)
    
    var reg45 = self.read_reg(0x45)
    if reg45 != nil
      reg45 = (reg45 & 0xC0) | ((value >> 10) & 0x3F)
      self.write_reg(0x45, reg45)
    end
    
    return self
  end
  
  def gain(value)
    if value < 0 value = 0 end
    if value > 30 value = 30 end
    
    var agc_gain_tbl = [
      0x00, 0x10, 0x18, 0x30, 0x34, 0x38, 0x3C, 0x70,
      0x72, 0x74, 0x76, 0x78, 0x7A, 0x7C, 0x7E, 0xF0,
      0xF1, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8,
      0xF9, 0xFA, 0xFB, 0xFC, 0xFD, 0xFE, 0xFF
    ]
    
    self.write_reg(self.BANK_SEL, self.BANK_SENSOR)
    self.write_reg(0x00, agc_gain_tbl[value])
    return self
  end
  
  def gain_ceiling(level)
    if level < 0 level = 0 end
    if level > 6 level = 6 end
    
    return self.set_reg_bits(self.BANK_SENSOR, 0x14, 5, 7, level)
  end
  
  def ae_level(level)
    if level < -2 level = -2 end
    if level > 2 level = 2 end
    
    var ae_levels = [
      [0x24, 0x20, 0x1C],
      [0x2C, 0x28, 0x24],
      [0x34, 0x30, 0x2C],
      [0x3C, 0x38, 0x34],
      [0x44, 0x40, 0x3C]
    ]
    
    self.write_reg(self.BANK_SEL, self.BANK_SENSOR)
    var regs = ae_levels[level + 2]
    self.write_reg(0x24, regs[0])
    self.write_reg(0x25, regs[1])
    self.write_reg(0x26, regs[2])
    
    return self
  end
  
  def wb_auto()
    self.set_reg_bits(self.BANK_DSP, 0xC7, 6, 1, 0)
    return self
  end
  
  def wb_sunny()
    self.set_reg_bits(self.BANK_DSP, 0xC7, 6, 1, 1)
    self.write_reg(self.BANK_SEL, self.BANK_DSP)
    self.write_reg(0xCC, 0x5E)
    self.write_reg(0xCD, 0x41)
    self.write_reg(0xCE, 0x54)
    return self
  end
  
  def wb_cloudy()
    self.set_reg_bits(self.BANK_DSP, 0xC7, 6, 1, 1)
    self.write_reg(self.BANK_SEL, self.BANK_DSP)
    self.write_reg(0xCC, 0x65)
    self.write_reg(0xCD, 0x41)
    self.write_reg(0xCE, 0x4F)
    return self
  end
  
  def wb_office()
    self.set_reg_bits(self.BANK_DSP, 0xC7, 6, 1, 1)
    self.write_reg(self.BANK_SEL, self.BANK_DSP)
    self.write_reg(0xCC, 0x52)
    self.write_reg(0xCD, 0x41)
    self.write_reg(0xCE, 0x66)
    return self
  end
  
  def wb_home()
    self.set_reg_bits(self.BANK_DSP, 0xC7, 6, 1, 1)
    self.write_reg(self.BANK_SEL, self.BANK_DSP)
    self.write_reg(0xCC, 0x42)
    self.write_reg(0xCD, 0x3F)
    self.write_reg(0xCE, 0x71)
    return self
  end
  
  def gamma(enable)
    return self.set_reg_bits(self.BANK_DSP, 0xC0, 5, 1, enable ? 1 : 0)
  end
  
  def lenc(enable)
    return self.set_reg_bits(self.BANK_DSP, 0xC0, 1, 1, enable ? 1 : 0)
  end
  
  def bpc(enable)
    return self.set_reg_bits(self.BANK_DSP, 0xC2, 7, 1, enable ? 1 : 0)
  end
  
  def wpc(enable)
    return self.set_reg_bits(self.BANK_DSP, 0xC2, 6, 1, enable ? 1 : 0)
  end
  
  def dcw(enable)
    return self.set_reg_bits(self.BANK_DSP, 0xC1, 5, 1, enable ? 1 : 0)
  end
  
  def quality(q)
    if q < 0 q = 0 end
    if q > 63 q = 63 end
    self.write_reg(self.BANK_SEL, self.BANK_DSP)
    self.write_reg(0x44, q)
    return self
  end
  
  def effect_normal()
    self.write_reg(self.BANK_SEL, self.BANK_DSP)
    self.write_reg(0x7C, 0x00)
    self.write_reg(0x7D, 0x00)
    self.write_reg(0x7C, 0x05)
    self.write_reg(0x7D, 0x80)
    self.write_reg(0x7D, 0x80)
    return self
  end
  
  def effect_negative()
    self.write_reg(self.BANK_SEL, self.BANK_DSP)
    self.write_reg(0x7C, 0x00)
    self.write_reg(0x7D, 0x40)
    self.write_reg(0x7C, 0x05)
    self.write_reg(0x7D, 0x80)
    self.write_reg(0x7D, 0x80)
    return self
  end
  
  def effect_grayscale()
    self.write_reg(self.BANK_SEL, self.BANK_DSP)
    self.write_reg(0x7C, 0x00)
    self.write_reg(0x7D, 0x18)
    self.write_reg(0x7C, 0x05)
    self.write_reg(0x7D, 0x80)
    self.write_reg(0x7D, 0x80)
    return self
  end
  
  def effect_sepia()
    self.write_reg(self.BANK_SEL, self.BANK_DSP)
    self.write_reg(0x7C, 0x00)
    self.write_reg(0x7D, 0x18)
    self.write_reg(0x7C, 0x05)
    self.write_reg(0x7D, 0x40)
    self.write_reg(0x7D, 0xA0)
    return self
  end
  
  def effect_bluish()
    self.write_reg(self.BANK_SEL, self.BANK_DSP)
    self.write_reg(0x7C, 0x00)
    self.write_reg(0x7D, 0x18)
    self.write_reg(0x7C, 0x05)
    self.write_reg(0x7D, 0xA0)
    self.write_reg(0x7D, 0x40)
    return self
  end
  
  def effect_greenish()
    self.write_reg(self.BANK_SEL, self.BANK_DSP)
    self.write_reg(0x7C, 0x00)
    self.write_reg(0x7D, 0x18)
    self.write_reg(0x7C, 0x05)
    self.write_reg(0x7D, 0x40)
    self.write_reg(0x7D, 0x40)
    return self
  end
  
  def effect_reddish()
    self.write_reg(self.BANK_SEL, self.BANK_DSP)
    self.write_reg(0x7C, 0x00)
    self.write_reg(0x7D, 0x18)
    self.write_reg(0x7C, 0x05)
    self.write_reg(0x7D, 0x40)
    self.write_reg(0x7D, 0xC0)
    return self
  end
  
  def read_window()
    self.write_reg(self.BANK_SEL, self.BANK_DSP)
    
    var hsize = self.read_reg(0x51)
    var vsize = self.read_reg(0x52)
    var vhyx = self.read_reg(0x55)
    var test = self.read_reg(0x57)
    
    if hsize == nil || vsize == nil || vhyx == nil
      print("OV2640: Failed to read window registers")
      return nil
    end
    
    var h_full = hsize
    if test != nil && (test & 0x80)
      h_full = h_full | 0x400
    end
    if vhyx & 0x08
      h_full = h_full | 0x800
    end
    
    var v_full = vsize
    if vhyx & 0x80
      v_full = v_full | 0x200
    end
    
    var width = h_full * 4
    var height = v_full * 4
    
    print(format("OV2640: DSP window: %d x %d pixels", width, height))
    
    return {"width": width, "height": height}
  end
  
  def read_zoom()
    self.write_reg(self.BANK_SEL, self.BANK_DSP)
    
    var zmow = self.read_reg(0x5A)
    var zmoh = self.read_reg(0x5B)
    var zmhh = self.read_reg(0x5C)
    
    if zmow == nil || zmoh == nil || zmhh == nil
      print("OV2640: Failed to read zoom registers")
      return nil
    end
    
    var out_w = zmow | ((zmhh & 0x03) << 8)
    var out_h = zmoh | ((zmhh & 0x04) << 6)
    
    var width = out_w * 4
    var height = out_h * 4
    
    print(format("OV2640: Output zoom: %d x %d pixels", width, height))
    print(format("OV2640: Raw: ZMOW=0x%02X ZMOH=0x%02X ZMHH=0x%02X", 
                 zmow, zmoh, zmhh))
    
    return {"width": width, "height": height}
  end
  
  def apply_scaling()
    var zoom = self.read_zoom()
    if zoom == nil
      print("OV2640: Cannot apply scaling")
      return self
    end
    
    self.write_reg(self.BANK_SEL, self.BANK_DSP)
    var ctrl2 = self.read_reg(0x86)
    if ctrl2 != nil
      ctrl2 = ctrl2 | 0x20
      self.write_reg(0x86, ctrl2)
    end
    
    self.write_reg(self.BANK_SEL, self.BANK_SENSOR)
    var com7 = self.read_reg(0x12)
    if com7 != nil
      com7 = com7 | 0x12
      self.write_reg(0x12, com7)
    end
    
    print(format("OV2640: Scaling applied for %dx%d", zoom["width"], zoom["height"]))
    return self
  end
end

print("OV2640_SCCB bitbang driver loaded")
print("Usage: var cfg = OV2640_SCCB(sda_pin, scl_pin)")
print("Example: var cfg = OV2640_SCCB(26, 27)")
