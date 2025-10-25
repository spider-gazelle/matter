require "../spec_helper"
require "../../src/matter/cluster/color_control_cluster"

# Note: Time-based transition tests from matter.js behavioral tests
# (packages/node/test/behaviors/color-control/ColorControlServerTest.ts)
# require transition manager support with gradual color changes over time.
# Current implementation performs instant color changes.
# These tests can be added when transition support is implemented.

describe Matter::Cluster::ColorControlCluster do
  describe "initialization" do
    it "creates cluster with default values" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ColorControlCluster.new(endpoint_id)

      cluster.cluster_id.id.should eq(0x0300_u32)
      cluster.name.should eq("ColorControl")
      cluster.current_hue.should eq(0_u8)
      cluster.current_saturation.should eq(0_u8)
      cluster.current_x.should eq(0_u16)
      cluster.current_y.should eq(0_u16)
      cluster.color_temperature_mireds.should eq(250_u16)
      cluster.color_mode.should eq(Matter::Cluster::Definitions::ColorControl::ColorMode::CurrentHueAndCurrentSaturation)
    end

    it "creates cluster with custom values" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ColorControlCluster.new(
        endpoint_id,
        current_hue: 100_u8,
        current_saturation: 200_u8,
        color_temperature_mireds: 300_u16
      )

      cluster.current_hue.should eq(100_u8)
      cluster.current_saturation.should eq(200_u8)
      cluster.color_temperature_mireds.should eq(300_u16)
    end
  end

  describe "hue commands" do
    it "executes MoveToHue command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ColorControlCluster.new(endpoint_id, current_hue: 0_u8)

      cluster.current_hue.should eq(0_u8)

      # MoveToHue(hue=127, ...)
      result = cluster.invoke_command(
        Matter::Cluster::ColorControlCluster::CMD_MOVE_TO_HUE,
        Bytes[127]
      )

      result.should be_a(Matter::InteractionModel::Status)
      result.as(Matter::InteractionModel::Status).success?.should be_true
      cluster.current_hue.should eq(127_u8)
      cluster.color_mode.should eq(Matter::Cluster::Definitions::ColorControl::ColorMode::CurrentHueAndCurrentSaturation)
    end

    it "executes StepHue Up command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ColorControlCluster.new(endpoint_id, current_hue: 100_u8)

      # StepHue(mode=Up, step_size=20, ...)
      result = cluster.invoke_command(
        Matter::Cluster::ColorControlCluster::CMD_STEP_HUE,
        Bytes[
          Matter::Cluster::Definitions::ColorControl::StepMode::Up.value,
          20,
        ]
      )

      result.as(Matter::InteractionModel::Status).success?.should be_true
      cluster.current_hue.should eq(120_u8)
    end

    it "executes StepHue Down command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ColorControlCluster.new(endpoint_id, current_hue: 100_u8)

      # StepHue(mode=Down, step_size=30, ...)
      result = cluster.invoke_command(
        Matter::Cluster::ColorControlCluster::CMD_STEP_HUE,
        Bytes[
          Matter::Cluster::Definitions::ColorControl::StepMode::Down.value,
          30,
        ]
      )

      result.as(Matter::InteractionModel::Status).success?.should be_true
      cluster.current_hue.should eq(70_u8)
    end

    it "wraps hue around 255" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ColorControlCluster.new(endpoint_id, current_hue: 250_u8)

      # Step up by 10 should wrap to 5
      cluster.invoke_command(
        Matter::Cluster::ColorControlCluster::CMD_STEP_HUE,
        Bytes[
          Matter::Cluster::Definitions::ColorControl::StepMode::Up.value,
          10,
        ]
      )

      cluster.current_hue.should eq(5_u8)
    end
  end

  describe "saturation commands" do
    it "executes MoveToSaturation command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ColorControlCluster.new(endpoint_id, current_saturation: 0_u8)

      # MoveToSaturation(saturation=200, ...)
      result = cluster.invoke_command(
        Matter::Cluster::ColorControlCluster::CMD_MOVE_TO_SATURATION,
        Bytes[200]
      )

      result.as(Matter::InteractionModel::Status).success?.should be_true
      cluster.current_saturation.should eq(200_u8)
    end

    it "executes StepSaturation Up command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ColorControlCluster.new(endpoint_id, current_saturation: 100_u8)

      cluster.invoke_command(
        Matter::Cluster::ColorControlCluster::CMD_STEP_SATURATION,
        Bytes[
          Matter::Cluster::Definitions::ColorControl::StepMode::Up.value,
          50,
        ]
      )

      cluster.current_saturation.should eq(150_u8)
    end

    it "executes StepSaturation Down command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ColorControlCluster.new(endpoint_id, current_saturation: 100_u8)

      cluster.invoke_command(
        Matter::Cluster::ColorControlCluster::CMD_STEP_SATURATION,
        Bytes[
          Matter::Cluster::Definitions::ColorControl::StepMode::Down.value,
          40,
        ]
      )

      cluster.current_saturation.should eq(60_u8)
    end

    it "clamps saturation to max (254)" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ColorControlCluster.new(endpoint_id, current_saturation: 240_u8)

      cluster.invoke_command(
        Matter::Cluster::ColorControlCluster::CMD_STEP_SATURATION,
        Bytes[
          Matter::Cluster::Definitions::ColorControl::StepMode::Up.value,
          50,
        ]
      )

      cluster.current_saturation.should eq(254_u8)
    end

    it "clamps saturation to min (0)" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ColorControlCluster.new(endpoint_id, current_saturation: 10_u8)

      cluster.invoke_command(
        Matter::Cluster::ColorControlCluster::CMD_STEP_SATURATION,
        Bytes[
          Matter::Cluster::Definitions::ColorControl::StepMode::Down.value,
          50,
        ]
      )

      cluster.current_saturation.should eq(0_u8)
    end
  end

  describe "hue and saturation combined" do
    it "executes MoveToHueAndSaturation command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ColorControlCluster.new(endpoint_id)

      # MoveToHueAndSaturation(hue=180, saturation=220, ...)
      result = cluster.invoke_command(
        Matter::Cluster::ColorControlCluster::CMD_MOVE_TO_HUE_AND_SATURATION,
        Bytes[180, 220]
      )

      result.as(Matter::InteractionModel::Status).success?.should be_true
      cluster.current_hue.should eq(180_u8)
      cluster.current_saturation.should eq(220_u8)
      cluster.color_mode.should eq(Matter::Cluster::Definitions::ColorControl::ColorMode::CurrentHueAndCurrentSaturation)
    end
  end

  describe "XY color commands" do
    it "executes MoveToColor command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ColorControlCluster.new(endpoint_id)

      # MoveToColor(x=32768, y=32768, ...)
      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(32768_u16, io)
      IO::ByteFormat::LittleEndian.encode(32768_u16, io)

      result = cluster.invoke_command(
        Matter::Cluster::ColorControlCluster::CMD_MOVE_TO_COLOR,
        io.to_slice
      )

      result.as(Matter::InteractionModel::Status).success?.should be_true
      cluster.current_x.should eq(32768_u16)
      cluster.current_y.should eq(32768_u16)
      cluster.color_mode.should eq(Matter::Cluster::Definitions::ColorControl::ColorMode::CurrentXAndCurrentY)
    end

    it "executes StepColor command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ColorControlCluster.new(
        endpoint_id,
        current_x: 30000_u16,
        current_y: 30000_u16
      )

      # StepColor(step_x=1000, step_y=-500, ...)
      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(1000_i16, io)
      IO::ByteFormat::LittleEndian.encode(-500_i16, io)

      cluster.invoke_command(
        Matter::Cluster::ColorControlCluster::CMD_STEP_COLOR,
        io.to_slice
      )

      cluster.current_x.should eq(31000_u16)
      cluster.current_y.should eq(29500_u16)
    end

    it "clamps XY to valid range" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ColorControlCluster.new(
        endpoint_id,
        current_x: 65000_u16,
        current_y: 1000_u16
      )

      # Try to step beyond max
      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(2000_i16, io)
      IO::ByteFormat::LittleEndian.encode(-2000_i16, io)

      cluster.invoke_command(
        Matter::Cluster::ColorControlCluster::CMD_STEP_COLOR,
        io.to_slice
      )

      cluster.current_x.should eq(65535_u16) # Clamped to max
      cluster.current_y.should eq(0_u16)     # Clamped to min
    end
  end

  describe "color temperature commands" do
    it "executes MoveToColorTemperature command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ColorControlCluster.new(endpoint_id, color_temperature_mireds: 200_u16)

      # MoveToColorTemperature(mireds=300, ...)
      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(300_u16, io)

      result = cluster.invoke_command(
        Matter::Cluster::ColorControlCluster::CMD_MOVE_TO_COLOR_TEMPERATURE,
        io.to_slice
      )

      result.as(Matter::InteractionModel::Status).success?.should be_true
      cluster.color_temperature_mireds.should eq(300_u16)
      cluster.color_mode.should eq(Matter::Cluster::Definitions::ColorControl::ColorMode::ColorTemperatureMireds)
    end

    it "executes StepColorTemperature Up command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ColorControlCluster.new(endpoint_id, color_temperature_mireds: 300_u16)

      # StepColorTemperature(mode=Up, step_size=50, ...)
      io = IO::Memory.new
      io.write_byte(Matter::Cluster::Definitions::ColorControl::StepMode::Up.value)
      IO::ByteFormat::LittleEndian.encode(50_u16, io)

      cluster.invoke_command(
        Matter::Cluster::ColorControlCluster::CMD_STEP_COLOR_TEMPERATURE,
        io.to_slice
      )

      cluster.color_temperature_mireds.should eq(350_u16)
    end

    it "executes StepColorTemperature Down command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ColorControlCluster.new(endpoint_id, color_temperature_mireds: 300_u16)

      # StepColorTemperature(mode=Down, step_size=50, ...)
      io = IO::Memory.new
      io.write_byte(Matter::Cluster::Definitions::ColorControl::StepMode::Down.value)
      IO::ByteFormat::LittleEndian.encode(50_u16, io)

      cluster.invoke_command(
        Matter::Cluster::ColorControlCluster::CMD_STEP_COLOR_TEMPERATURE,
        io.to_slice
      )

      cluster.color_temperature_mireds.should eq(250_u16)
    end

    it "clamps to physical min mireds" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ColorControlCluster.new(
        endpoint_id,
        color_temperature_mireds: 150_u16,
        color_temp_physical_min_mireds: 147_u16
      )

      # Try to go below min
      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(100_u16, io)

      cluster.invoke_command(
        Matter::Cluster::ColorControlCluster::CMD_MOVE_TO_COLOR_TEMPERATURE,
        io.to_slice
      )

      cluster.color_temperature_mireds.should eq(147_u16) # Clamped to min
    end

    it "clamps to physical max mireds" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ColorControlCluster.new(
        endpoint_id,
        color_temperature_mireds: 450_u16,
        color_temp_physical_max_mireds: 500_u16
      )

      # Try to go above max
      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(600_u16, io)

      cluster.invoke_command(
        Matter::Cluster::ColorControlCluster::CMD_MOVE_TO_COLOR_TEMPERATURE,
        io.to_slice
      )

      cluster.color_temperature_mireds.should eq(500_u16) # Clamped to max
    end
  end

  describe "enhanced hue commands" do
    it "executes EnhancedMoveToHue command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ColorControlCluster.new(endpoint_id)

      # EnhancedMoveToHue(enhanced_hue=32768, ...)
      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(32768_u16, io)

      result = cluster.invoke_command(
        Matter::Cluster::ColorControlCluster::CMD_ENHANCED_MOVE_TO_HUE,
        io.to_slice
      )

      result.as(Matter::InteractionModel::Status).success?.should be_true
      cluster.enhanced_current_hue.should eq(32768_u16)
      cluster.current_hue.should eq(128_u8) # High byte
      cluster.enhanced_color_mode.should eq(Matter::Cluster::Definitions::ColorControl::EnhancedColorMode::EnhancedCurrentHueAndCurrentSaturation)
    end

    it "executes EnhancedStepHue Up command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ColorControlCluster.new(endpoint_id, current_hue: 100_u8)

      initial_enhanced_hue = cluster.enhanced_current_hue

      # EnhancedStepHue(mode=Up, step_size=1000, ...)
      io = IO::Memory.new
      io.write_byte(Matter::Cluster::Definitions::ColorControl::StepMode::Up.value)
      IO::ByteFormat::LittleEndian.encode(1000_u16, io)

      cluster.invoke_command(
        Matter::Cluster::ColorControlCluster::CMD_ENHANCED_STEP_HUE,
        io.to_slice
      )

      cluster.enhanced_current_hue.should eq(initial_enhanced_hue + 1000)
    end

    it "wraps enhanced hue around 65536" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ColorControlCluster.new(endpoint_id)

      # Set to near max
      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(65500_u16, io)
      cluster.invoke_command(Matter::Cluster::ColorControlCluster::CMD_ENHANCED_MOVE_TO_HUE, io.to_slice)

      # Step up by 100 should wrap
      io = IO::Memory.new
      io.write_byte(Matter::Cluster::Definitions::ColorControl::StepMode::Up.value)
      IO::ByteFormat::LittleEndian.encode(100_u16, io)
      cluster.invoke_command(Matter::Cluster::ColorControlCluster::CMD_ENHANCED_STEP_HUE, io.to_slice)

      cluster.enhanced_current_hue.should eq(64_u16) # Wrapped
    end

    it "executes EnhancedMoveToHueAndSaturation command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ColorControlCluster.new(endpoint_id)

      # EnhancedMoveToHueAndSaturation(enhanced_hue=40000, saturation=200, ...)
      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(40000_u16, io)
      io.write_byte(200_u8)

      result = cluster.invoke_command(
        Matter::Cluster::ColorControlCluster::CMD_ENHANCED_MOVE_TO_HUE_AND_SATURATION,
        io.to_slice
      )

      result.as(Matter::InteractionModel::Status).success?.should be_true
      cluster.enhanced_current_hue.should eq(40000_u16)
      cluster.current_saturation.should eq(200_u8)
      cluster.current_hue.should eq(156_u8) # 40000 >> 8
    end
  end

  describe "color mode tracking" do
    it "sets color mode to HS when changing hue" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ColorControlCluster.new(
        endpoint_id,
        color_mode: Matter::Cluster::Definitions::ColorControl::ColorMode::ColorTemperatureMireds
      )

      cluster.invoke_command(Matter::Cluster::ColorControlCluster::CMD_MOVE_TO_HUE, Bytes[100])

      cluster.color_mode.should eq(Matter::Cluster::Definitions::ColorControl::ColorMode::CurrentHueAndCurrentSaturation)
    end

    it "sets color mode to XY when changing color" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ColorControlCluster.new(
        endpoint_id,
        color_mode: Matter::Cluster::Definitions::ColorControl::ColorMode::CurrentHueAndCurrentSaturation
      )

      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(30000_u16, io)
      IO::ByteFormat::LittleEndian.encode(30000_u16, io)

      cluster.invoke_command(Matter::Cluster::ColorControlCluster::CMD_MOVE_TO_COLOR, io.to_slice)

      cluster.color_mode.should eq(Matter::Cluster::Definitions::ColorControl::ColorMode::CurrentXAndCurrentY)
    end

    it "sets color mode to CT when changing temperature" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ColorControlCluster.new(
        endpoint_id,
        color_mode: Matter::Cluster::Definitions::ColorControl::ColorMode::CurrentXAndCurrentY
      )

      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(300_u16, io)

      cluster.invoke_command(Matter::Cluster::ColorControlCluster::CMD_MOVE_TO_COLOR_TEMPERATURE, io.to_slice)

      cluster.color_mode.should eq(Matter::Cluster::Definitions::ColorControl::ColorMode::ColorTemperatureMireds)
    end
  end

  describe "callbacks" do
    it "calls callback when color changes" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ColorControlCluster.new(endpoint_id, current_hue: 50_u8)

      callback_called = false
      cluster.on_color_changed do
        callback_called = true
      end

      cluster.invoke_command(Matter::Cluster::ColorControlCluster::CMD_MOVE_TO_HUE, Bytes[100])

      callback_called.should be_true
    end

    it "does not call callback if color doesn't change" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ColorControlCluster.new(endpoint_id, current_hue: 100_u8)

      callback_called = false
      cluster.on_color_changed do
        callback_called = true
      end

      # Move to same hue
      cluster.invoke_command(Matter::Cluster::ColorControlCluster::CMD_MOVE_TO_HUE, Bytes[100])

      callback_called.should be_false
    end
  end

  describe "data versioning" do
    it "increments version when color changes" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ColorControlCluster.new(endpoint_id, current_hue: 50_u8)

      initial_version = cluster.data_version

      cluster.invoke_command(Matter::Cluster::ColorControlCluster::CMD_MOVE_TO_HUE, Bytes[100])

      cluster.data_version.should eq(initial_version + 1)
    end

    it "does not increment version if color unchanged" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ColorControlCluster.new(endpoint_id, current_hue: 100_u8)

      initial_version = cluster.data_version

      # Move to same hue
      cluster.invoke_command(Matter::Cluster::ColorControlCluster::CMD_MOVE_TO_HUE, Bytes[100])

      cluster.data_version.should eq(initial_version) # No increment
    end
  end

  describe "utility methods" do
    it "converts color temperature to Kelvin" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ColorControlCluster.new(endpoint_id, color_temperature_mireds: 250_u16)

      kelvin = cluster.color_temperature_kelvin
      kelvin.should eq(4000_u32) # 1,000,000 / 250
    end

    it "sets color temperature from Kelvin" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ColorControlCluster.new(endpoint_id)

      cluster.set_color_temperature_kelvin(4000_u32)

      cluster.color_temperature_mireds.should eq(250_u16)
    end
  end

  describe "reading attributes" do
    it "reads CurrentHue attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ColorControlCluster.new(endpoint_id, current_hue: 127_u8)

      result = cluster.read_attribute(Matter::Cluster::ColorControlCluster::ATTR_CURRENT_HUE)
      result.should be_a(Bytes)
      result.as(Bytes).should eq(Bytes[127])
    end

    it "reads CurrentSaturation attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ColorControlCluster.new(endpoint_id, current_saturation: 200_u8)

      result = cluster.read_attribute(Matter::Cluster::ColorControlCluster::ATTR_CURRENT_SATURATION)
      result.should be_a(Bytes)
      result.as(Bytes).should eq(Bytes[200])
    end

    it "reads ColorTemperatureMireds attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ColorControlCluster.new(endpoint_id, color_temperature_mireds: 350_u16)

      result = cluster.read_attribute(Matter::Cluster::ColorControlCluster::ATTR_COLOR_TEMPERATURE_MIREDS)
      result.should be_a(Bytes)
      mireds = IO::ByteFormat::LittleEndian.decode(UInt16, result.as(Bytes))
      mireds.should eq(350_u16)
    end

    it "reads ColorMode attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ColorControlCluster.new(endpoint_id)

      result = cluster.read_attribute(Matter::Cluster::ColorControlCluster::ATTR_COLOR_MODE)
      result.should be_a(Bytes)
      result.as(Bytes)[0].should eq(Matter::Cluster::Definitions::ColorControl::ColorMode::CurrentHueAndCurrentSaturation.value)
    end
  end

  describe "practical scenarios" do
    it "creates warm white light (2700K)" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      light = Matter::Cluster::ColorControlCluster.new(endpoint_id)

      # 2700K = 370 mireds
      light.set_color_temperature_kelvin(2700_u32)

      light.color_temperature_mireds.should eq(370_u16)
      light.color_temperature_kelvin.should eq(2702_u32) # Close to 2700
    end

    it "creates cool white light (6500K)" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      light = Matter::Cluster::ColorControlCluster.new(endpoint_id)

      # 6500K = 154 mireds
      light.set_color_temperature_kelvin(6500_u32)

      light.color_temperature_mireds.should eq(153_u16)
      light.color_temperature_kelvin.should be_close(6500_u32, 100_u32)
    end

    it "creates red color (hue=0, sat=254)" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      light = Matter::Cluster::ColorControlCluster.new(endpoint_id)

      light.invoke_command(
        Matter::Cluster::ColorControlCluster::CMD_MOVE_TO_HUE_AND_SATURATION,
        Bytes[0, 254]
      )

      light.current_hue.should eq(0_u8)
      light.current_saturation.should eq(254_u8)
      light.color_mode.should eq(Matter::Cluster::Definitions::ColorControl::ColorMode::CurrentHueAndCurrentSaturation)
    end

    it "creates blue color (hue=170, sat=254)" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      light = Matter::Cluster::ColorControlCluster.new(endpoint_id)

      light.invoke_command(
        Matter::Cluster::ColorControlCluster::CMD_MOVE_TO_HUE_AND_SATURATION,
        Bytes[170, 254]
      )

      light.current_hue.should eq(170_u8)
      light.current_saturation.should eq(254_u8)
    end

    it "gradually transitions through color wheel" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      light = Matter::Cluster::ColorControlCluster.new(endpoint_id, current_hue: 0_u8)

      # Step through hues
      10.times do |i|
        light.invoke_command(
          Matter::Cluster::ColorControlCluster::CMD_STEP_HUE,
          Bytes[
            Matter::Cluster::Definitions::ColorControl::StepMode::Up.value,
            25,
          ]
        )
      end

      light.current_hue.should eq(250_u8) # 0 + (25 * 10)
    end
  end

  describe "error handling" do
    it "returns error for unsupported command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ColorControlCluster.new(endpoint_id)

      result = cluster.invoke_command(0x99_u32, Bytes.new(0))
      result.should be_a(Matter::InteractionModel::Status)
      result.as(Matter::InteractionModel::Status).status.should eq(
        Matter::InteractionModel::StatusCode::UnsupportedCommand
      )
    end

    it "returns error for command with insufficient data" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ColorControlCluster.new(endpoint_id)

      # MoveToColor needs at least 4 bytes
      result = cluster.invoke_command(
        Matter::Cluster::ColorControlCluster::CMD_MOVE_TO_COLOR,
        Bytes[1, 2]
      )

      result.should be_a(Matter::InteractionModel::Status)
      result.as(Matter::InteractionModel::Status).status.should eq(
        Matter::InteractionModel::StatusCode::InvalidCommand
      )
    end
  end
end
