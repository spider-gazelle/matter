require "../spec_helper"
require "../../src/matter/protocol/persistence"

describe Matter::Protocol::Persistence do
  describe ".redact" do
    it "replaces secret values and leaves other keys untouched" do
      json = {
        "1" => {
          "session_id"            => 1,
          "encryption_key"        => "00112233445566778899aabbccddeeff",
          "decryption_key"        => "ffeeddccbbaa99887766554433221100",
          "attestation_challenge" => "0123456789abcdef",
          "peer_node_id"          => "deadbeef",
        },
      }.to_json

      redacted = Matter::Protocol::Persistence.redact(json)

      Matter::Protocol::Persistence::REDACTED_KEYS.each do |key|
        redacted.should contain(%("#{key}":"#{Matter::Protocol::Persistence::REDACTED_VALUE}"))
      end
      redacted.should_not contain("00112233445566778899aabbccddeeff")
      redacted.should_not contain("ffeeddccbbaa99887766554433221100")
      redacted.should_not contain("0123456789abcdef")
      redacted.should contain(%("session_id":1))
      redacted.should contain(%("peer_node_id":"deadbeef"))
    end

    it "handles whitespace around the colon" do
      json = %({ "encryption_key" : "secret" , "other" : "kept" })

      redacted = Matter::Protocol::Persistence.redact(json)

      redacted.should_not contain("secret")
      redacted.should contain(%("encryption_key":"<redacted>"))
      redacted.should contain(%("other" : "kept"))
    end
  end
end
