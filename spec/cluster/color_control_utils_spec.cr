require "../spec_helper"
require "../../src/matter/cluster/color_control_utils"

# Test suite for Color Control conversion utilities
# Migrated from matter.js: packages/node/test/behaviors/color-control/ColorConversionUtilsTest.ts

describe Matter::Cluster::ColorControlUtils do
  describe "HSV to RGB conversions" do
    it "converts red (hue=0, sat=1) to RGB and back" do
      r, g, b = Matter::Cluster::ColorControlUtils.hsv_to_rgb(0.0, 1.0)
      (r * 255).should be_close(255.0, 0.5)
      (g * 255).should be_close(0.0, 0.5)
      (b * 255).should be_close(0.0, 0.5)

      h, s, _ = Matter::Cluster::ColorControlUtils.rgb_to_hsv(r, g, b)
      h.should be_close(0.0, 0.5)
      s.should be_close(1.0, 0.05)
    end

    it "converts green (hue=120, sat=1) to RGB and back" do
      r, g, b = Matter::Cluster::ColorControlUtils.hsv_to_rgb(120.0, 1.0)
      (r * 255).should be_close(0.0, 0.5)
      (g * 255).should be_close(255.0, 0.5)
      (b * 255).should be_close(0.0, 0.5)

      h, s, _ = Matter::Cluster::ColorControlUtils.rgb_to_hsv(r, g, b)
      h.should be_close(120.0, 0.5)
      s.should be_close(1.0, 0.05)
    end

    it "converts blue (hue=240, sat=1) to RGB and back" do
      r, g, b = Matter::Cluster::ColorControlUtils.hsv_to_rgb(240.0, 1.0)
      (r * 255).should be_close(0.0, 0.5)
      (g * 255).should be_close(0.0, 0.5)
      (b * 255).should be_close(255.0, 0.5)

      h, s, _ = Matter::Cluster::ColorControlUtils.rgb_to_hsv(r, g, b)
      h.should be_close(240.0, 0.5)
      s.should be_close(1.0, 0.05)
    end

    it "converts magenta (hue=317, sat=1) to RGB and back" do
      r, g, b = Matter::Cluster::ColorControlUtils.hsv_to_rgb(317.0, 1.0)
      (r * 255).should be_close(255.0, 0.5)
      (g * 255).should be_close(0.0, 0.5)
      (b * 255).should be_close(183.0, 0.5)

      h, s, _ = Matter::Cluster::ColorControlUtils.rgb_to_hsv(r, g, b)
      h.should be_close(317.0, 0.5)
      s.should be_close(1.0, 0.05)
    end

    it "converts cyan (hue=152, sat=1) to RGB and back" do
      r, g, b = Matter::Cluster::ColorControlUtils.hsv_to_rgb(152.0, 1.0)
      (r * 255).should be_close(0.0, 0.5)
      (g * 255).should be_close(255.0, 0.5)
      (b * 255).should be_close(136.0, 0.5)

      h, s, _ = Matter::Cluster::ColorControlUtils.rgb_to_hsv(r, g, b)
      h.should be_close(152.0, 0.5)
      s.should be_close(1.0, 0.05)
    end

    it "converts color with partial saturation (hue=123, sat=0.5)" do
      r, g, b = Matter::Cluster::ColorControlUtils.hsv_to_rgb(123.0, 0.5)
      (r * 255).should be_close(128.0, 0.5)
      (g * 255).should be_close(255.0, 0.5)
      (b * 255).should be_close(134.0, 0.5)

      h, s, _ = Matter::Cluster::ColorControlUtils.rgb_to_hsv(r, g, b)
      h.should be_close(123.0, 0.5)
      s.should be_close(0.5, 0.05)
    end

    it "converts white (sat=0) to RGB and back" do
      r, g, b = Matter::Cluster::ColorControlUtils.hsv_to_rgb(123.0, 0.0)
      (r * 255).should be_close(255.0, 0.5)
      (g * 255).should be_close(255.0, 0.5)
      (b * 255).should be_close(255.0, 0.5)

      h, s, _ = Matter::Cluster::ColorControlUtils.rgb_to_hsv(r, g, b)
      # Hue is 0 when saturation is 0 (undefined, defaults to 0)
      h.should be_close(0.0, 0.0)
      s.should be_close(0.0, 0.05)
    end

    it "converts orange (hue=42, sat=1) to RGB and back" do
      r, g, b = Matter::Cluster::ColorControlUtils.hsv_to_rgb(42.0, 1.0)
      (r * 255).should be_close(255.0, 0.5)
      (g * 255).should be_close(179.0, 0.5)
      (b * 255).should be_close(0.0, 0.5)

      h, s, _ = Matter::Cluster::ColorControlUtils.rgb_to_hsv(r, g, b)
      h.should be_close(42.0, 0.5)
      s.should be_close(1.0, 0.05)
    end
  end

  describe "XY to RGB conversions" do
    it "converts XY(0.5, 0.4) to RGB and back" do
      r, g, b = Matter::Cluster::ColorControlUtils.xy_to_rgb(0.5, 0.4)
      (r * 255).should be_close(255.0, 0.5)
      (g * 255).should be_close(184.0, 0.5)
      (b * 255).should be_close(98.0, 0.5)

      x, y = Matter::Cluster::ColorControlUtils.rgb_to_xy(r, g, b)
      x.should be_close(0.5, 0.01)
      y.should be_close(0.4, 0.01)
    end

    it "converts XY(0.421, 0.381) to RGB and back" do
      r, g, b = Matter::Cluster::ColorControlUtils.xy_to_rgb(0.421, 0.381)
      (r * 255).should be_close(255.0, 0.5)
      (g * 255).should be_close(213.0, 0.5)
      (b * 255).should be_close(159.0, 0.5)

      x, y = Matter::Cluster::ColorControlUtils.rgb_to_xy(r, g, b)
      x.should be_close(0.421, 0.01)
      y.should be_close(0.381, 0.01)
    end

    it "converts XY(0.217, 0.077) to RGB and back" do
      r, g, b = Matter::Cluster::ColorControlUtils.xy_to_rgb(0.217, 0.077)
      (r * 255).should be_close(131.0, 0.5)
      (g * 255).should be_close(0.0, 0.5)
      (b * 255).should be_close(255.0, 0.5)

      x, y = Matter::Cluster::ColorControlUtils.rgb_to_xy(r, g, b)
      x.should be_close(0.217, 0.01)
      y.should be_close(0.077, 0.01)
    end

    it "converts XY(0.5621, 0.4166) to RGB and back" do
      r, g, b = Matter::Cluster::ColorControlUtils.xy_to_rgb(0.5621, 0.4166)
      (r * 255).should be_close(255.0, 0.5)
      (g * 255).should be_close(166.0, 0.5)
      (b * 255).should be_close(0.0, 0.5)

      x, y = Matter::Cluster::ColorControlUtils.rgb_to_xy(r, g, b)
      x.should be_close(0.5621, 0.01)
      y.should be_close(0.4166, 0.01)
    end

    it "converts XY(0.33, 0.33) (white point) to RGB and back" do
      r, g, b = Matter::Cluster::ColorControlUtils.xy_to_rgb(0.33, 0.33)
      (r * 255).should be_close(255.0, 0.5)
      (g * 255).should be_close(249.0, 0.5)
      (b * 255).should be_close(248.0, 0.5)

      x, y = Matter::Cluster::ColorControlUtils.rgb_to_xy(r, g, b)
      x.should be_close(0.33, 0.01)
      y.should be_close(0.33, 0.01)
    end
  end

  describe "Mireds to XY conversions" do
    it "converts 6000K mireds to XY coordinates" do
      mireds_6000k = 1_000_000.0 / 6000.0
      xy = Matter::Cluster::ColorControlUtils.mireds_to_xy(mireds_6000k)
      xy.should_not be_nil

      if xy
        x, y = xy
        # Expected from lookup table for 6000K
        x.should be_close(0.2600, 0.001)
        y.should be_close(0.5557, 0.001)
      end
    end

    it "converts 9000K mireds to XY coordinates" do
      mireds_9000k = 1_000_000.0 / 9000.0
      xy = Matter::Cluster::ColorControlUtils.mireds_to_xy(mireds_9000k)
      xy.should_not be_nil

      if xy
        x, y = xy
        # Expected from lookup table for 9000K
        x.should be_close(0.1834, 0.001)
        y.should be_close(0.5609, 0.001)
      end
    end

    it "returns nil for out-of-range temperatures (< 1000K)" do
      mireds = 1_000_000.0 / 500.0 # 500K
      xy = Matter::Cluster::ColorControlUtils.mireds_to_xy(mireds)
      xy.should be_nil
    end

    it "returns nil for out-of-range temperatures (> 40000K)" do
      mireds = 1_000_000.0 / 50000.0 # 50000K
      xy = Matter::Cluster::ColorControlUtils.mireds_to_xy(mireds)
      xy.should be_nil
    end
  end

  describe "edge cases" do
    it "handles hue wrapping (negative hue)" do
      r1, g1, b1 = Matter::Cluster::ColorControlUtils.hsv_to_rgb(-30.0, 1.0)
      r2, g2, b2 = Matter::Cluster::ColorControlUtils.hsv_to_rgb(330.0, 1.0)

      r1.should be_close(r2, 0.001)
      g1.should be_close(g2, 0.001)
      b1.should be_close(b2, 0.001)
    end

    it "handles hue wrapping (> 360 degrees)" do
      r1, g1, b1 = Matter::Cluster::ColorControlUtils.hsv_to_rgb(420.0, 1.0)
      r2, g2, b2 = Matter::Cluster::ColorControlUtils.hsv_to_rgb(60.0, 1.0)

      r1.should be_close(r2, 0.001)
      g1.should be_close(g2, 0.001)
      b1.should be_close(b2, 0.001)
    end

    it "handles black (value=0)" do
      r, g, b = Matter::Cluster::ColorControlUtils.hsv_to_rgb(120.0, 1.0, 0.0)
      r.should eq(0.0)
      g.should eq(0.0)
      b.should eq(0.0)
    end

    it "handles RGB to XY for black" do
      x, y = Matter::Cluster::ColorControlUtils.rgb_to_xy(0.0, 0.0, 0.0)
      x.should eq(0.0)
      y.should eq(0.0)
    end
  end

  describe "practical color scenarios" do
    it "converts warm white (2700K)" do
      mireds = (1_000_000.0 / 2700.0).to_f64
      xy = Matter::Cluster::ColorControlUtils.mireds_to_xy(mireds)
      xy.should_not be_nil

      if xy
        x, y = xy
        # Warm white should be in the orange-ish region
        x.should be > 0.4
        y.should be > 0.3
      end
    end

    it "converts cool white (6500K)" do
      mireds = (1_000_000.0 / 6500.0).to_f64
      xy = Matter::Cluster::ColorControlUtils.mireds_to_xy(mireds)
      xy.should_not be_nil

      if xy
        x, y = xy
        # Cool white from lookup table (6500K)
        x.should be_close(0.2422, 0.001)
        y.should be_close(0.5584, 0.001)
      end
    end
  end
end
