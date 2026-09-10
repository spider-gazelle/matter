require "math"

module Matter::Cluster::ColorControlUtils
  # Converts HSV (Hue, Saturation, Value) to RGB
  # Hue: 0-360 degrees
  # Saturation: 0.0-1.0
  # Value: 0.0-1.0 (defaults to 1.0 for full brightness)
  # Returns: [r, g, b] where each component is 0.0-1.0
  def self.hsv_to_rgb(hue : Float64, saturation : Float64, value : Float64 = 1.0) : Tuple(Float64, Float64, Float64)
    return {value, value, value} if saturation == 0.0

    # Normalize hue to 0-360 range
    h = hue % 360.0
    h = h + 360.0 if h < 0

    # Calculate RGB based on hue sector
    h_sector = h / 60.0
    sector = h_sector.floor.to_i
    f = h_sector - sector

    p = value * (1.0 - saturation)
    q = value * (1.0 - saturation * f)
    t = value * (1.0 - saturation * (1.0 - f))

    case sector % 6
    when 0 then {value, t, p}
    when 1 then {q, value, p}
    when 2 then {p, value, t}
    when 3 then {p, q, value}
    when 4 then {t, p, value}
    else        {value, p, q}
    end
  end

  # Converts RGB to HSV (Hue, Saturation, Value)
  # R, G, B: 0.0-1.0
  # Returns: [hue (0-360), saturation (0.0-1.0), value (0.0-1.0)]
  def self.rgb_to_hsv(r : Float64, g : Float64, b : Float64) : Tuple(Float64, Float64, Float64)
    max = [r, g, b].max
    min = [r, g, b].min
    delta = max - min

    # Value
    v = max

    # Saturation
    s = max == 0.0 ? 0.0 : delta / max

    # Hue
    h = if delta == 0.0
          0.0
        elsif max == r
          60.0 * (((g - b) / delta) % 6.0)
        elsif max == g
          60.0 * (((b - r) / delta) + 2.0)
        else # max == b
          60.0 * (((r - g) / delta) + 4.0)
        end

    h = h + 360.0 if h < 0.0

    {h, s, v}
  end

  # Converts XY (CIE 1931 color space) to RGB
  # X, Y: 0.0-1.0 (normalized coordinates)
  # Brightness: 0.0-254.0 (defaults to 254.0 for maximum brightness)
  # Returns: [r, g, b] where each component is 0.0-1.0
  def self.xy_to_rgb(x : Float64, y : Float64, brightness : Float64 = 254.0) : Tuple(Float64, Float64, Float64)
    # From: https://github.com/usolved/cie-rgb-converter/blob/master/cie_rgb_converter.js

    # use maximum brightness
    y_adj = y == 0.0 ? 0.00000000001 : y
    z = 1.0 - x - y
    big_y = (brightness / 254.0).round(2)
    big_x = (big_y / y_adj) * x
    big_z = (big_y / y_adj) * z

    # Convert to RGB using Wide RGB D65 conversion
    rgb = [
      big_x * 1.656492 - big_y * 0.354851 - big_z * 0.255038,
      -big_x * 0.707196 + big_y * 1.655397 + big_z * 0.036152,
      big_x * 0.051713 - big_y * 0.121364 + big_z * 1.01153,
    ]

    # Apply reverse gamma correction
    rgb = rgb.map do |component|
      component <= 0.0031308 ? 12.92 * component : (1.0 + 0.055) * (component ** (1.0 / 2.4)) - 0.055
    end

    # Bring all negative components to zero
    rgb = rgb.map { |component| [component, 0.0].max }

    # If one component is greater than 1, weight components by that value
    max = rgb.max
    if max > 1.0
      rgb = rgb.map { |component| component / max }
    end

    # This fixes situation when due to computational errors value get slightly below 0, or NaN in case of zero-division
    rgb = rgb.map { |component| !component.finite? || component < 0.0 ? 0.0 : component }

    {rgb[0], rgb[1], rgb[2]}
  end

  # Converts RGB to XY (CIE 1931 color space)
  # R, G, B: 0.0-1.0
  # Returns: [x, y] where each coordinate is 0.0-1.0
  def self.rgb_to_xy(r : Float64, g : Float64, b : Float64) : Tuple(Float64, Float64)
    # From: https://github.com/usolved/cie-rgb-converter/blob/master/cie_rgb_converter.js
    # Apply gamma correction to the RGB values
    r = r > 0.04045 ? ((r + 0.055) / (1.0 + 0.055)) ** 2.4 : r / 12.92
    g = g > 0.04045 ? ((g + 0.055) / (1.0 + 0.055)) ** 2.4 : g / 12.92
    b = b > 0.04045 ? ((b + 0.055) / (1.0 + 0.055)) ** 2.4 : b / 12.92

    # RGB values to XYZ using the Wide RGB D65 conversion formula
    big_x = r * 0.664511 + g * 0.154324 + b * 0.162028
    big_y = r * 0.283881 + g * 0.668433 + b * 0.047685
    big_z = r * 0.000088 + g * 0.07231 + b * 0.986039
    sum = big_x + big_y + big_z

    ret_x = sum == 0.0 ? 0.0 : big_x / sum
    ret_y = sum == 0.0 ? 0.0 : big_y / sum

    {ret_x, ret_y}
  end

  # Converts color temperature (in Mireds) to XY coordinates
  # Uses a simplified lookup table with linear interpolation
  # mireds: Color temperature in Mireds (1,000,000 / Kelvin)
  # Returns: [x, y] or nil if out of range
  def self.mireds_to_xy(mireds : Float64) : Tuple(Float64, Float64)?
    kelvin = (1_000_000.0 / mireds).round.to_i

    # Valid range: 1000K - 40000K
    return if kelvin < 1000 || kelvin > 40000

    # Find exact match in lookup table
    xy = KELVIN_TO_XY_LOOKUP[kelvin]?
    return xy if xy

    # Find nearest lower and upper entries for interpolation
    sorted_keys = KELVIN_TO_XY_LOOKUP.keys.sort!
    lower_kelvin = sorted_keys.select { |k| k <= kelvin }.max?
    upper_kelvin = sorted_keys.select { |k| k >= kelvin }.min?

    return unless lower_kelvin && upper_kelvin

    lower = KELVIN_TO_XY_LOOKUP[lower_kelvin]
    upper = KELVIN_TO_XY_LOOKUP[upper_kelvin]

    # If they're the same (at boundary), return that value
    return lower if lower_kelvin == upper_kelvin

    # Linear interpolation
    ratio = (kelvin - lower_kelvin).to_f64 / (upper_kelvin - lower_kelvin).to_f64
    x = lower[0] + (upper[0] - lower[0]) * ratio
    y = lower[1] + (upper[1] - lower[1]) * ratio

    {x, y}
  end

  # Converts XY coordinates to color temperature (in Mireds)
  # Uses McCamy's approximation
  # x, y: CIE 1931 coordinates (0.0-1.0)
  # Returns: Color temperature in Mireds
  def self.xy_to_mireds(x : Float64, y : Float64) : Float64
    # Calculate CCT using McCamy's formula (slightly different coefficients than standard)
    n = (x - 0.332) / (0.1858 - y)
    kelvin = (437.0 * (n ** 3.0) + 3601.0 * (n ** 2.0) + 6861.0 * n + 5517.0).abs

    # Convert to Mireds
    (1_000_000.0 / kelvin).round.to_f64
  end

  # Simplified Kelvin to XY lookup table (every 100K from 1000K to 40000K)
  # From: https://github.com/Koenkk/zigbee-herdsman-converters/blob/master/src/lib/kelvinToXy.ts
  KELVIN_TO_XY_LOOKUP = {
     1000 => {0.6528, 0.3444},
     1100 => {0.6388, 0.3562},
     1200 => {0.6250, 0.3675},
     1300 => {0.6116, 0.3779},
     1400 => {0.5985, 0.3878},
     1500 => {0.5857, 0.3972},
     1600 => {0.5732, 0.4062},
     1700 => {0.5611, 0.4147},
     1800 => {0.5494, 0.4228},
     1900 => {0.5381, 0.4305},
     2000 => {0.5271, 0.4378},
     2100 => {0.5164, 0.4448},
     2200 => {0.5061, 0.4514},
     2300 => {0.4961, 0.4577},
     2400 => {0.4864, 0.4637},
     2500 => {0.4770, 0.4694},
     2600 => {0.4678, 0.4749},
     2700 => {0.4590, 0.4800},
     2800 => {0.4503, 0.4849},
     2900 => {0.4420, 0.4895},
     3000 => {0.4338, 0.4939},
     3100 => {0.4259, 0.4981},
     3200 => {0.4182, 0.5020},
     3300 => {0.4107, 0.5057},
     3400 => {0.4034, 0.5092},
     3500 => {0.3962, 0.5126},
     3600 => {0.3893, 0.5157},
     3700 => {0.3825, 0.5187},
     3800 => {0.3759, 0.5215},
     3900 => {0.3694, 0.5242},
     4000 => {0.3631, 0.5267},
     4100 => {0.3569, 0.5291},
     4200 => {0.3509, 0.5313},
     4300 => {0.3450, 0.5335},
     4400 => {0.3392, 0.5355},
     4500 => {0.3335, 0.5374},
     4600 => {0.3280, 0.5392},
     4700 => {0.3225, 0.5409},
     4800 => {0.3172, 0.5425},
     4900 => {0.3119, 0.5440},
     5000 => {0.3068, 0.5454},
     5100 => {0.3017, 0.5468},
     5200 => {0.2968, 0.5480},
     5300 => {0.2919, 0.5492},
     5400 => {0.2871, 0.5503},
     5500 => {0.2824, 0.5514},
     5600 => {0.2778, 0.5523},
     5700 => {0.2732, 0.5533},
     5800 => {0.2688, 0.5541},
     5900 => {0.2644, 0.5549},
     6000 => {0.2600, 0.5557},
     6500 => {0.2422, 0.5584},
     7000 => {0.2268, 0.5601},
     7500 => {0.2135, 0.5610},
     8000 => {0.2021, 0.5614},
     8500 => {0.1922, 0.5613},
     9000 => {0.1834, 0.5609},
     9500 => {0.1756, 0.5603},
    10000 => {0.1686, 0.5594},
    15000 => {0.1249, 0.5456},
    20000 => {0.1033, 0.5329},
    25000 => {0.0899, 0.5230},
    30000 => {0.0807, 0.5156},
    35000 => {0.0740, 0.5099},
    40000 => {0.0687, 0.5054},
  }
end
