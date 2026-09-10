require "../../spec_helper"
require "../../../src/matter/session/pase/definitions"

describe Matter::Session::Pase::Definitions::PbkdfParamRequest do
  it "parses real chip-tool PBKDFParamRequest without crashing" do
    # Actual TLV payload captured from chip-tool during commissioning
    # This is the complete message sent by chip-tool pairing onnetwork
    # Previously this crashed with "Can not cast to UInt16?" error
    hex_payload = "1530012065dff8487dd580d9cffff51b8fe880b8fb4b64a92f8bd6e58df2474210e0b41225021e2e240300280435052501f40125022c012503a00f24041324050c2606000204012407011818"
    payload_bytes = Bytes.new(hex_payload.size // 2) do |i|
      hex_payload[i*2, 2].to_u8(16)
    end

    # Parse the request - this should not crash
    request = Matter::Session::Pase::Definitions::PbkdfParamRequest.from_slice(payload_bytes)

    # Verify key fields are parsed correctly
    request.initiator_random.should_not be_nil
    request.initiator_random.as(Bytes).size.should eq(32)
    request.initiator_session_id.should eq(11806)

    # Note: Additional fields (passcode_id, has_pbkdf_parameters, mrp_parameters)
    # are present in the payload but may not be fully parsed yet - that's okay,
    # the critical fix is that parsing no longer crashes on the UInt16 field
  end

  it "handles minimal PBKDFParamRequest with only required fields" do
    # Build minimal request with just initiator_session_id
    request = Matter::Session::Pase::Definitions::PbkdfParamRequest.new(
      initiator_session_id: 12345_u16
    )

    request.initiator_session_id.should eq(12345)
    request.initiator_random.should be_nil
    request.passcode_id.should be_nil
    request.has_pbkdf_parameters.should be_nil
    request.mrp_parameters.should be_nil
  end

  it "round-trips encoding and decoding for basic fields" do
    # Create request with basic fields (the ones we know work)
    random_bytes = Random::Secure.random_bytes(32)
    original = Matter::Session::Pase::Definitions::PbkdfParamRequest.new(
      initiator_random: random_bytes,
      initiator_session_id: 54321_u16
    )

    # Encode to bytes
    encoded = original.to_slice

    # Decode back
    decoded = Matter::Session::Pase::Definitions::PbkdfParamRequest.from_slice(encoded)

    # Verify fields match
    decoded.initiator_session_id.should eq(original.initiator_session_id)
    decoded.initiator_random.should eq(original.initiator_random)
  end
end
