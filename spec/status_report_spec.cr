require "./spec_helper"
require "../src/matter/session/pase/definitions"

describe Matter::Session::Pase::Definitions::StatusReport do
  describe "#to_bytes" do
    it "encodes SUCCESS status with correct raw binary format" do
      status_report = Matter::Session::Pase::Definitions::StatusReport.new(
        general_status: 0_u16,
        protocol_id: 0x0000_u16, # Secure Channel
        vendor_id: 0_u16,
        protocol_status: 0_u16
      )

      bytes = status_report.to_bytes

      # Expected raw binary format (little-endian):
      # 2 bytes: generalStatus = 0x0000
      # 4 bytes: vendorProtocolId = 0x00000000 (vendor=0, protocol=0x0000)
      # 2 bytes: protocolStatus = 0x0000
      # Total: 8 bytes

      expected = Bytes[0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]

      bytes.should eq(expected)
      bytes.size.should eq(8)
    end

    it "encodes non-zero status codes correctly" do
      status_report = Matter::Session::Pase::Definitions::StatusReport.new(
        general_status: 0x01_u16, # FAILURE
        protocol_id: 0x0000_u16,  # Secure Channel
        vendor_id: 0_u16,
        protocol_status: 0x02_u16 # Protocol-specific error
      )

      bytes = status_report.to_bytes

      # Expected raw binary:
      # 2 bytes: generalStatus = 0x0001
      # 4 bytes: vendorProtocolId = 0x00000000
      # 2 bytes: protocolStatus = 0x0002

      expected = Bytes[0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00]

      bytes.should eq(expected)
      bytes.size.should eq(8)
    end

    it "correctly combines vendor_id and protocol_id" do
      status_report = Matter::Session::Pase::Definitions::StatusReport.new(
        general_status: 0_u16,
        protocol_id: 0x0000_u16, # Secure Channel protocol
        vendor_id: 0xFFF1_u16,   # Example vendor ID
        protocol_status: 0_u16
      )

      bytes = status_report.to_bytes

      # vendorProtocolId should be: (0xFFF1 << 16) | 0x0000 = 0xFFF10000
      # In little-endian: 00 00 F1 FF
      expected = Bytes[0x00, 0x00, 0x00, 0x00, 0xF1, 0xFF, 0x00, 0x00]

      bytes.should eq(expected)
      bytes.size.should eq(8)
    end

    it "includes optional protocol_data when provided" do
      protocol_data = Bytes[0x12, 0x34, 0x56, 0x78]
      status_report = Matter::Session::Pase::Definitions::StatusReport.new(
        general_status: 0_u16,
        protocol_id: 0x0000_u16,
        vendor_id: 0_u16,
        protocol_status: 0_u16,
        protocol_data: protocol_data
      )

      bytes = status_report.to_bytes

      # 8 bytes (header) + 4 bytes (data) = 12 bytes
      bytes.size.should eq(12)

      # Verify protocol_data is appended
      bytes[-4..].should eq(protocol_data)
    end
  end

  describe "initialization" do
    it "defaults to SUCCESS status for Secure Channel" do
      status_report = Matter::Session::Pase::Definitions::StatusReport.new

      status_report.general_status.should eq(0_u16)
      status_report.protocol_id.should eq(0x0000_u16) # Secure Channel
      status_report.vendor_id.should eq(0_u16)
      status_report.protocol_status.should eq(0_u16)
      status_report.protocol_data.should be_nil
    end

    it "accepts custom values" do
      status_report = Matter::Session::Pase::Definitions::StatusReport.new(
        general_status: 0x01_u16,
        protocol_id: 0x0001_u16, # Interaction Model
        vendor_id: 0xFFF1_u16,
        protocol_status: 0xFF_u16,
        protocol_data: Bytes[0xAB, 0xCD]
      )

      status_report.general_status.should eq(0x01_u16)
      status_report.protocol_id.should eq(0x0001_u16)
      status_report.vendor_id.should eq(0xFFF1_u16)
      status_report.protocol_status.should eq(0xFF_u16)
      status_report.protocol_data.should eq(Bytes[0xAB, 0xCD])
    end
  end

  describe "chip-tool compatibility" do
    it "produces the exact raw binary format expected by chip-tool" do
      # chip-tool/matter.js expect raw binary StatusReport, NOT TLV!
      # For SUCCESS on Secure Channel protocol: all zeros, 8 bytes

      status_report = Matter::Session::Pase::Definitions::StatusReport.new
      bytes = status_report.to_bytes

      # chip-tool expects exactly this format for SUCCESS StatusReport
      expected_hex = "0000000000000000" # 8 bytes of zeros
      bytes.hexstring.should eq(expected_hex)

      # Packet size should be 8 bytes (not 10!)
      bytes.size.should eq(8)
    end
  end
end
