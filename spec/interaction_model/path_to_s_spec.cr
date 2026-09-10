require "../spec_helper"

module Matter::InteractionModel
  describe "path interpolation" do
    it "formats a concrete AttributePath" do
      path = AttributePath.new(1_u16, 0x0006_u32, 0x0000_u32)
      "#{path}".should eq("E:1/C:0x6/A:0x0")
    end

    it "formats an AttributePath with a list index" do
      path = AttributePath.new(1_u16, 0x001F_u32, 0x0000_u32, 3_u16)
      "#{path}".should eq("E:1/C:0x1f/A:0x0/[3]")
    end

    it "formats wildcard AttributePath fields" do
      "#{AttributePath.new}".should eq("E:*")
      "#{AttributePath.new(nil, 0x28_u32)}".should eq("E:*/C:0x28")
    end

    it "formats a CommandPath" do
      path = CommandPath.new(1_u16, 0x0006_u32, 0x0001_u32)
      "#{path}".should eq("E:1/C:0x6/Cmd:0x1")
    end

    it "formats an EventPath" do
      path = EventPath.new(nil, 0_u16, 0x0028_u32, 0x0000_u32)
      "#{path}".should eq("N:*/E:0/C:0x28/Evt:0x0")
    end

    it "flags urgent EventPaths" do
      path = EventPath.new(1_u64, 0_u16, 0x0028_u32, 0x0003_u32, is_urgent: true)
      "#{path}".should eq("N:1/E:0/C:0x28/Evt:0x3/(urgent)")
    end

    it "formats a ConcreteAttributePath like its AttributePath" do
      path = ConcreteAttributePath.new(2_u16, 0x0008_u32, 0x0000_u32)
      "#{path}".should eq("#{path.to_path}")
      path.to_s.should eq("E:2/C:0x8/A:0x0")
    end
  end
end
