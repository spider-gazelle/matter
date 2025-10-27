require "../spec_helper"

# Helper to build TLV-encoded Thread operational dataset
def build_thread_dataset(fields : Hash(UInt8, Bytes)) : Bytes
  io = IO::Memory.new
  fields.each do |type, value|
    io.write_byte(type)
    io.write_byte(value.size.to_u8)
    io.write(value)
  end
  io.to_slice
end

describe Matter::Network::WiFiCredentials do
  describe "#initialize" do
    it "identifies open network (0 bytes)" do
      creds = Matter::Network::WiFiCredentials.new(Bytes.new(0))
      creds.security_type.should eq(Matter::Network::WiFiSecurityType::Open)
      creds.is_psk.should be_false
    end

    it "identifies WEP-64 passphrase (5 bytes ASCII)" do
      creds = Matter::Network::WiFiCredentials.new("12345".to_slice)
      creds.security_type.should eq(Matter::Network::WiFiSecurityType::WEP)
      creds.is_psk.should be_false
      creds.passphrase.should eq("12345")
    end

    it "identifies WEP-64 PSK (10 hex chars)" do
      creds = Matter::Network::WiFiCredentials.new("0123456789".to_slice)
      creds.security_type.should eq(Matter::Network::WiFiSecurityType::WEP)
      creds.is_psk.should be_true
      creds.psk_hex.should eq("30313233343536373839")
    end

    it "identifies WEP-128 passphrase (13 bytes ASCII)" do
      creds = Matter::Network::WiFiCredentials.new("1234567890123".to_slice)
      creds.security_type.should eq(Matter::Network::WiFiSecurityType::WEP)
      creds.is_psk.should be_false
      creds.passphrase.should eq("1234567890123")
    end

    it "identifies WEP-128 PSK (26 hex chars)" do
      creds = Matter::Network::WiFiCredentials.new("01234567890123456789012345".to_slice)
      creds.security_type.should eq(Matter::Network::WiFiSecurityType::WEP)
      creds.is_psk.should be_true
    end

    it "identifies WPA2 passphrase (8-63 bytes)" do
      creds = Matter::Network::WiFiCredentials.new("mypassword1234".to_slice)
      creds.security_type.should eq(Matter::Network::WiFiSecurityType::WPA2_Personal)
      creds.is_psk.should be_false
      creds.passphrase.should eq("mypassword1234")
    end

    it "identifies WPA2 PSK (64 hex chars)" do
      psk = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
      creds = Matter::Network::WiFiCredentials.new(psk.to_slice)
      creds.security_type.should eq(Matter::Network::WiFiSecurityType::WPA2_Personal)
      creds.is_psk.should be_true
      creds.psk_hex.size.should eq(128) # Each char becomes 2 hex chars
    end

    it "handles non-hex 64 byte string as passphrase" do
      non_hex = "x" * 64
      creds = Matter::Network::WiFiCredentials.new(non_hex.to_slice)
      creds.security_type.should eq(Matter::Network::WiFiSecurityType::WPA2_Personal)
      creds.is_psk.should be_false
    end

    it "defaults unusual lengths to WPA2 passphrase" do
      creds = Matter::Network::WiFiCredentials.new("ab".to_slice)
      creds.security_type.should eq(Matter::Network::WiFiSecurityType::WPA2_Personal)
      creds.is_psk.should be_false
    end
  end

  describe "#raw" do
    it "returns original bytes" do
      original = "mypassword".to_slice
      creds = Matter::Network::WiFiCredentials.new(original)
      creds.raw.should eq(original)
    end
  end
end

describe Matter::Network::ThreadCredentials do
  describe "#initialize" do
    it "parses Extended PAN ID (Type 0x02)" do
      xpan = Bytes[0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88]
      dataset = build_thread_dataset({0x02_u8 => xpan})

      creds = Matter::Network::ThreadCredentials.new(dataset)
      creds.extended_pan_id.should eq(xpan)
      creds.network_id.should eq(xpan)
    end

    it "parses Network Name (Type 0x03)" do
      name = "TestThread"
      xpan = Bytes[0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88]
      dataset = build_thread_dataset({
        0x02_u8 => xpan,
        0x03_u8 => name.to_slice,
      })

      creds = Matter::Network::ThreadCredentials.new(dataset)
      creds.network_name.should eq("TestThread")
    end

    it "parses PAN ID (Type 0x01)" do
      xpan = Bytes[0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88]
      pan_id_bytes = Bytes[0x12, 0x34] # Big-endian: 0x1234
      dataset = build_thread_dataset({
        0x02_u8 => xpan,
        0x01_u8 => pan_id_bytes,
      })

      creds = Matter::Network::ThreadCredentials.new(dataset)
      creds.pan_id.should eq(0x1234_u16)
    end

    it "parses Channel (Type 0x00)" do
      xpan = Bytes[0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88]
      channel_bytes = Bytes[0x0F, 0x00, 0x00] # Channel 15
      dataset = build_thread_dataset({
        0x02_u8 => xpan,
        0x00_u8 => channel_bytes,
      })

      creds = Matter::Network::ThreadCredentials.new(dataset)
      creds.channel.should eq(15_u8)
    end

    it "parses Network Key (Type 0x05)" do
      xpan = Bytes[0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88]
      key = Bytes.new(16) { |i| i.to_u8 }
      dataset = build_thread_dataset({
        0x02_u8 => xpan,
        0x05_u8 => key,
      })

      creds = Matter::Network::ThreadCredentials.new(dataset)
      creds.network_key.should eq(key)
    end

    it "parses complete operational dataset" do
      xpan = Bytes[0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88]
      name = "MyThreadNet"
      pan_id_bytes = Bytes[0x56, 0x78]
      channel_bytes = Bytes[0x14, 0x00, 0x00] # Channel 20
      key = Bytes.new(16) { |i| (i * 16).to_u8 }

      dataset = build_thread_dataset({
        0x00_u8 => channel_bytes,
        0x01_u8 => pan_id_bytes,
        0x02_u8 => xpan,
        0x03_u8 => name.to_slice,
        0x05_u8 => key,
      })

      creds = Matter::Network::ThreadCredentials.new(dataset)
      creds.extended_pan_id.should eq(xpan)
      creds.network_name.should eq("MyThreadNet")
      creds.pan_id.should eq(0x5678_u16)
      creds.channel.should eq(20_u8)
      creds.network_key.should eq(key)
    end

    it "handles missing optional fields" do
      xpan = Bytes[0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88]
      dataset = build_thread_dataset({0x02_u8 => xpan})

      creds = Matter::Network::ThreadCredentials.new(dataset)
      creds.extended_pan_id.should eq(xpan)
      creds.network_name.should be_nil
      creds.pan_id.should be_nil
      creds.channel.should be_nil
      creds.network_key.should be_nil
    end

    it "falls back to first 8 bytes when no Extended PAN ID TLV present" do
      # Non-TLV encoded data (legacy format or malformed)
      dataset = Bytes[0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xAA]

      creds = Matter::Network::ThreadCredentials.new(dataset)
      creds.extended_pan_id.should eq(Bytes[0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88])
    end

    it "handles truncated TLV gracefully" do
      # TLV with type and length but missing value bytes
      dataset = Bytes[0x02, 0x08] # Type 0x02, claims 8 bytes but has none

      creds = Matter::Network::ThreadCredentials.new(dataset)
      # Should fall back to using available bytes
      creds.extended_pan_id.should eq(Bytes[0x02, 0x08])
    end
  end

  describe "#raw" do
    it "returns original operational dataset" do
      original = Bytes[0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88]
      creds = Matter::Network::ThreadCredentials.new(original)
      creds.raw.should eq(original)
    end
  end
end

describe Matter::Network::WiFiNetworkInfo do
  describe "#initialize" do
    it "creates info with parsed credentials" do
      ssid = "TestNetwork".to_slice
      password = "mypassword1234".to_slice

      info = Matter::Network::WiFiNetworkInfo.new(ssid, password)

      info.ssid.should eq(ssid)
      info.ssid_string.should eq("TestNetwork")
      info.credentials.security_type.should eq(Matter::Network::WiFiSecurityType::WPA2_Personal)
      info.credentials.is_psk.should be_false
      info.credentials.passphrase.should eq("mypassword1234")
    end

    it "handles open network" do
      ssid = "OpenWiFi".to_slice
      credentials = Bytes.new(0)

      info = Matter::Network::WiFiNetworkInfo.new(ssid, credentials)

      info.ssid_string.should eq("OpenWiFi")
      info.credentials.security_type.should eq(Matter::Network::WiFiSecurityType::Open)
    end
  end
end
