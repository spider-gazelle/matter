# Request TLV encoders shared by the general_commissioning_*_spec.cr files.
require "../spec_helper"
require "../../src/matter/cluster/general_commissioning"

# Helper functions for TLV encoding command data
def create_arm_failsafe_request_tlv(expiry_length : UInt16, breadcrumb : UInt64) : TLV::Any
  request = Matter::Cluster::GeneralCommissioning::ArmFailSafeRequest.new(
    expiry_length_seconds: expiry_length,
    breadcrumb: breadcrumb
  )
  request.to_tlv(nil)
end

def create_set_regulatory_config_request_tlv(regulatory_config : UInt8, country_code : String, breadcrumb : UInt64) : TLV::Any
  request = Matter::Cluster::GeneralCommissioning::SetRegulatoryConfigRequest.new(
    new_regulatory_config: Matter::Cluster::GeneralCommissioning::RegulatoryLocationType.new(regulatory_config),
    country_code: country_code,
    breadcrumb: breadcrumb
  )
  request.to_tlv(nil)
end
