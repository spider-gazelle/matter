# Request TLV encoders shared by the administrator_commissioning_*_spec.cr files.
require "../spec_helper"
require "../../src/matter/cluster/administrator_commissioning"

# Helper to create TLV-encoded OpenCommissioningWindowRequest
def create_open_commissioning_window_tlv(
  timeout : UInt16,
  verifier : Bytes,
  discriminator : UInt16,
  iterations : UInt32,
  salt : Bytes,
) : TLV::Any
  Matter::Cluster::AdministratorCommissioning::OpenCommissioningWindowRequest.new(
    commissioning_timeout: timeout,
    pake_passcode_verifier: verifier,
    discriminator: discriminator,
    iterations: iterations,
    salt: salt
  ).to_tlv(nil)
end

# Helper to create TLV-encoded OpenBasicCommissioningWindowRequest
def create_open_basic_commissioning_window_tlv(timeout : UInt16) : TLV::Any
  Matter::Cluster::AdministratorCommissioning::OpenBasicCommissioningWindowRequest.new(
    commissioning_timeout: timeout
  ).to_tlv(nil)
end
