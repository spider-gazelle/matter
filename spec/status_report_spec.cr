require "./spec_helper"
require "../src/matter/session/pase/definitions"

describe Matter::Session::Pase::Definitions::StatusReport do
  describe "#to_bytes" do
    it "encodes SUCCESS status with correct TLV format" do
      status_report = Matter::Session::Pase::Definitions::StatusReport.new(
        general_status: 0_u16,
        protocol_status: 0_u16
      )

      bytes = status_report.to_bytes

      # Expected TLV encoding for StatusReport with SUCCESS (0, 0):
      # 15              = Anonymous structure
      # 25 00 00 00     = UInt16, context tag 0, value 0x0000 (general_status)
      # 25 01 00 00     = UInt16, context tag 1, value 0x0000 (protocol_status)
      # 18              = End of structure
      # Total: 10 bytes

      expected = Bytes[0x15, 0x25, 0x00, 0x00, 0x00, 0x25, 0x01, 0x00, 0x00, 0x18]

      bytes.should eq(expected)
      bytes.size.should eq(10)
    end

    it "encodes non-zero status codes correctly" do
      status_report = Matter::Session::Pase::Definitions::StatusReport.new(
        general_status: 0x01_u16, # FAILURE
        protocol_status: 0x02_u16 # Protocol-specific error
      )

      bytes = status_report.to_bytes

      # Expected TLV encoding:
      # 15              = Anonymous structure
      # 25 00 01 00     = UInt16, context tag 0, value 0x0001
      # 25 01 02 00     = UInt16, context tag 1, value 0x0002
      # 18              = End of structure

      expected = Bytes[0x15, 0x25, 0x00, 0x01, 0x00, 0x25, 0x01, 0x02, 0x00, 0x18]

      bytes.should eq(expected)
      bytes.size.should eq(10)
    end

    it "uses 2-byte encoding even for small values" do
      status_report = Matter::Session::Pase::Definitions::StatusReport.new(
        general_status: 0_u16,
        protocol_status: 0_u16
      )

      bytes = status_report.to_bytes
      hex = bytes.hexstring

      # Should NOT be: 1524000024010018 (8 bytes, using UInt8)
      # Should BE:     15250000002501000018 (10 bytes, using UInt16)

      hex.should_not eq("1524000024010018") # Wrong: UInt8 encoding
      hex.should eq("15250000002501000018") # Correct: UInt16 encoding
    end

    it "has correct TLV structure tags" do
      status_report = Matter::Session::Pase::Definitions::StatusReport.new(
        general_status: 0_u16,
        protocol_status: 0_u16
      )

      bytes = status_report.to_bytes

      # Bytes: 15 25 00 00 00 25 01 00 00 18
      # Index:  0  1  2  3  4  5  6  7  8  9

      # Verify structure markers
      bytes[0].should eq(0x15)  # Anonymous structure start
      bytes[-1].should eq(0x18) # End of structure

      # Verify field tags use UInt16 encoding (0x25)
      bytes[1].should eq(0x25) # general_status uses UInt16
      bytes[5].should eq(0x25) # protocol_status uses UInt16

      # Verify context tags
      bytes[2].should eq(0x00) # general_status tag = 0
      bytes[6].should eq(0x01) # protocol_status tag = 1
    end
  end

  describe "initialization" do
    it "defaults to SUCCESS status" do
      status_report = Matter::Session::Pase::Definitions::StatusReport.new

      status_report.general_status.should eq(0_u16)
      status_report.protocol_status.should eq(0_u16)
    end

    it "accepts custom status codes" do
      status_report = Matter::Session::Pase::Definitions::StatusReport.new(
        general_status: 0x01_u16,
        protocol_status: 0xFF_u16
      )

      status_report.general_status.should eq(0x01_u16)
      status_report.protocol_status.should eq(0xFF_u16)
    end
  end

  describe "chip-tool compatibility" do
    it "produces the exact format expected by chip-tool" do
      # This is the critical test - chip-tool rejected our previous
      # encoding because we used UInt8 (0x24) instead of UInt16 (0x25)

      status_report = Matter::Session::Pase::Definitions::StatusReport.new
      bytes = status_report.to_bytes

      # chip-tool expects exactly this format for SUCCESS StatusReport
      expected_hex = "15250000002501000018"
      bytes.hexstring.should eq(expected_hex)

      # Packet size should be 10 bytes (not 8)
      bytes.size.should eq(10)
    end
  end
end
