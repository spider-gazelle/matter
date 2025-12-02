require "./spec_helper"
require "../src/matter/session/case/definitions"

# Compatibility tests for CASE TBS_Data2 encoding
# Test vectors generated from matter.js to ensure byte-level compatibility

describe Matter::Session::Case::Definitions::SignedData do
  # Test Case 1: Simple mock data with ICAC
  it "encodes TBS_Data2 matching matter.js (simple with ICAC)" do
    noc = "1530010101".hexbytes
    icac = "15300202".hexbytes
    responder_key = "040102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f40".hexbytes
    initiator_key = "048182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0".hexbytes

    # Expected output from matter.js
    expected = "15300105153001010130020415300202300341040102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f40300441048182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc018".hexbytes

    signed_data = Matter::Session::Case::Definitions::SignedData.new(
      responder_noc: noc,
      responder_icac: icac,
      responder_public_key: responder_key,
      initiator_public_key: initiator_key
    )

    result = signed_data.to_bytes
    result.should eq(expected)
  end

  # Test Case 2: Without ICAC (optional field omitted)
  it "encodes TBS_Data2 matching matter.js (without ICAC)" do
    noc = "1530010101".hexbytes
    responder_key = "040102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f40".hexbytes
    initiator_key = "048182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0".hexbytes

    # Expected output from matter.js (no ICAC field)
    expected = "153001051530010101300341040102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f40300441048182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc018".hexbytes

    signed_data = Matter::Session::Case::Definitions::SignedData.new(
      responder_noc: noc,
      responder_icac: nil,
      responder_public_key: responder_key,
      initiator_public_key: initiator_key
    )

    result = signed_data.to_bytes
    result.should eq(expected)
  end

  # Test Case 3: Real commissioning data from chip-tool
  it "encodes TBS_Data2 matching matter.js (real commissioning data)" do
    # NOC from chip-tool commissioning (241 bytes)
    noc = "1530010101240201370324130218260480228127260580254d3a37062415012411011824070124080130094104cfdad09344f8d2aeb4f9cd327e0963956af6e5b05381bc39cf8cd711734f78affc98c8b0e7fe57654a1c3d18ded60aef11755d07620d5b5a7b5f1740abc0807e370a3501280118240201360304020401183004148beeb83ae887a350d3c5401a94a0210b3e55e73b30051467a11f53c587d2171cde4e0ffcf94a13801ffaad18300b4063779add4ece6edface8d9ad8594361c7b419cb50b481b3729b1e4cb451000708e8d6505750849ce030e99995e92d14c896795d19eb457c497f85fcf87a0cbb718".hexbytes

    # ICAC from chip-tool commissioning (231 bytes)
    icac = "1530010101240201370324140118260480228127260580254d3a37062413021824070124080130094104c39ffaec554cb3f8619adb22f4b1f4d01b72c647c51853f5021fbf47adf746cddd7be196bd1faa8b009275a31aa0fa56be09a31ea7a4a3b90c5a0c1ce9f7d8ea370a350129011824026030041467a11f53c587d2171cde4e0ffcf94a13801ffaad300514aa2e684296a87e5ec65e87eb7f2941a5d04bfcda18300b40eeb4b605ebfdb3d8518274cce8d828b7c9335d5e1a1df3689e1b99908d3366e1eaedc27725d2306162956da53308a4160321a0c429b67a09676a69b4845d6a9218".hexbytes

    # Responder ephemeral key (65 bytes)
    responder_key = "04eb76640dd270ef14b990e3f0428db9fc6ffe37702c2f53fd8ab017af6c5c4a759da43c0a3455b669e67e7aa5a0573904ffc4a60626c8d1f519f58b589c92cd77".hexbytes

    # Initiator ephemeral key from Sigma1 (65 bytes)
    initiator_key = "0415da1642f97e24f19eba3f0d228c9cf737b69513adc7e9ccf9a92a2af18641bedb202124c56af15be36406c91ea6f6de11b79a19ff5df2f91e093fa61719db96".hexbytes

    # Expected output from matter.js (616 bytes)
    expected = "153001f11530010101240201370324130218260480228127260580254d3a37062415012411011824070124080130094104cfdad09344f8d2aeb4f9cd327e0963956af6e5b05381bc39cf8cd711734f78affc98c8b0e7fe57654a1c3d18ded60aef11755d07620d5b5a7b5f1740abc0807e370a3501280118240201360304020401183004148beeb83ae887a350d3c5401a94a0210b3e55e73b30051467a11f53c587d2171cde4e0ffcf94a13801ffaad18300b4063779add4ece6edface8d9ad8594361c7b419cb50b481b3729b1e4cb451000708e8d6505750849ce030e99995e92d14c896795d19eb457c497f85fcf87a0cbb7183002e71530010101240201370324140118260480228127260580254d3a37062413021824070124080130094104c39ffaec554cb3f8619adb22f4b1f4d01b72c647c51853f5021fbf47adf746cddd7be196bd1faa8b009275a31aa0fa56be09a31ea7a4a3b90c5a0c1ce9f7d8ea370a350129011824026030041467a11f53c587d2171cde4e0ffcf94a13801ffaad300514aa2e684296a87e5ec65e87eb7f2941a5d04bfcda18300b40eeb4b605ebfdb3d8518274cce8d828b7c9335d5e1a1df3689e1b99908d3366e1eaedc27725d2306162956da53308a4160321a0c429b67a09676a69b4845d6a921830034104eb76640dd270ef14b990e3f0428db9fc6ffe37702c2f53fd8ab017af6c5c4a759da43c0a3455b669e67e7aa5a0573904ffc4a60626c8d1f519f58b589c92cd773004410415da1642f97e24f19eba3f0d228c9cf737b69513adc7e9ccf9a92a2af18641bedb202124c56af15be36406c91ea6f6de11b79a19ff5df2f91e093fa61719db9618".hexbytes

    noc.size.should eq(241)
    icac.size.should eq(231)
    responder_key.size.should eq(65)
    initiator_key.size.should eq(65)

    signed_data = Matter::Session::Case::Definitions::SignedData.new(
      responder_noc: noc,
      responder_icac: icac,
      responder_public_key: responder_key,
      initiator_public_key: initiator_key
    )

    result = signed_data.to_bytes
    result.size.should eq(616)
    result.should eq(expected)
  end
end
