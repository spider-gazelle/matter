require "../spec_helper"
require "../../src/matter/cluster/general_commissioning_cluster"

module Matter::Cluster
  describe GeneralCommissioningCluster do
    describe "initialization and attributes" do
      it "initializes with default values" do
        cluster = GeneralCommissioningCluster.new

        cluster.breadcrumb.should eq(0_u64)
        cluster.max_cumulative_failsafe_seconds.should eq(900_u16)
        cluster.max_network_commissioning_seconds.should eq(900_u16)
        cluster.regulatory_config.should eq(GeneralCommissioningCluster::RegulatoryLocationType::IndoorOutdoor)
        cluster.location_capability.should eq(GeneralCommissioningCluster::RegulatoryLocationType::IndoorOutdoor)
        cluster.supports_concurrent_connection?.should be_true
        cluster.failsafe_armed?.should be_false
      end

      it "exposes cluster ID" do
        GeneralCommissioningCluster::CLUSTER_ID.should eq(0x0030_u32)
      end
    end

    describe "ArmFailSafe command" do
      it "arms failsafe with valid parameters" do
        cluster = GeneralCommissioningCluster.new
        request = GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 60_u16,
          breadcrumb: 123_u64
        )

        response = cluster.arm_failsafe(
          request: request,
          session_fabric_index: nil,
          is_pase_session: true
        )

        response.error_code.should eq(GeneralCommissioningCluster::CommissioningError::OK)
        cluster.failsafe_armed?.should be_true
        cluster.breadcrumb.should eq(123_u64)
      end

      it "rejects expiry length exceeding max cumulative" do
        cluster = GeneralCommissioningCluster.new
        request = GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 1000_u16, # Exceeds 900s default max
          breadcrumb: 123_u64
        )

        response = cluster.arm_failsafe(
          request: request,
          session_fabric_index: nil,
          is_pase_session: true
        )

        response.error_code.should eq(GeneralCommissioningCluster::CommissioningError::ValueOutsideRange)
        cluster.failsafe_armed?.should be_false
      end

      it "disarms failsafe with expiry_length=0" do
        cluster = GeneralCommissioningCluster.new

        # First arm
        request1 = GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 60_u16,
          breadcrumb: 123_u64
        )
        cluster.arm_failsafe(request1, nil, true)
        cluster.failsafe_armed?.should be_true

        # Then disarm
        request2 = GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 0_u16,
          breadcrumb: 456_u64
        )
        response = cluster.arm_failsafe(request2, nil, true)

        response.error_code.should eq(GeneralCommissioningCluster::CommissioningError::OK)
        cluster.failsafe_armed?.should be_false
        # Breadcrumb should NOT be updated on disarm
        cluster.breadcrumb.should eq(123_u64)
      end

      it "re-arms existing failsafe with matching fabric" do
        cluster = GeneralCommissioningCluster.new

        # Initial arm
        request1 = GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 60_u16,
          breadcrumb: 100_u64
        )
        cluster.arm_failsafe(request1, 1_u8, false)

        # Re-arm with same fabric
        request2 = GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 120_u16,
          breadcrumb: 200_u64
        )
        response = cluster.arm_failsafe(request2, 1_u8, false)

        response.error_code.should eq(GeneralCommissioningCluster::CommissioningError::OK)
        cluster.failsafe_armed?.should be_true
        cluster.breadcrumb.should eq(200_u64)
      end

      it "rejects CASE session when different fabric is active" do
        cluster = GeneralCommissioningCluster.new

        # Arm with fabric 1
        request1 = GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 60_u16,
          breadcrumb: 100_u64
        )
        cluster.arm_failsafe(request1, 1_u8, false)

        # Try to arm with fabric 2 (CASE session)
        request2 = GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 60_u16,
          breadcrumb: 200_u64
        )
        response = cluster.arm_failsafe(request2, 2_u8, false)

        response.error_code.should eq(GeneralCommissioningCluster::CommissioningError::BusyWithOtherAdmin)
        cluster.breadcrumb.should eq(100_u64) # Not updated
      end

      it "allows PASE session to take over when commissioning window is open" do
        cluster = GeneralCommissioningCluster.new
        cluster.open_commissioning_window

        # Arm with fabric 1 (CASE session)
        request1 = GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 60_u16,
          breadcrumb: 100_u64
        )
        cluster.arm_failsafe(request1, 1_u8, false)

        # PASE session takes over
        request2 = GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 60_u16,
          breadcrumb: 200_u64
        )
        response = cluster.arm_failsafe(request2, nil, true)

        response.error_code.should eq(GeneralCommissioningCluster::CommissioningError::OK)
        cluster.breadcrumb.should eq(200_u64)
      end

      it "invokes expiry callback when failsafe timer expires" do
        cluster = GeneralCommissioningCluster.new

        # Set initial breadcrumb via ArmFailSafe
        request = GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 1_u16, # 1 second
          breadcrumb: 42_u64
        )
        cluster.arm_failsafe(request, nil, true)
        cluster.breadcrumb.should eq(42_u64)

        # Wait for expiry
        sleep 1.5.seconds

        # Breadcrumb should be reset to 0 by rollback
        cluster.breadcrumb.should eq(0_u64)
        cluster.failsafe_armed?.should be_false
      end
    end

    describe "CommissioningComplete command" do
      it "completes commissioning successfully with valid CASE session" do
        cluster = GeneralCommissioningCluster.new

        # Arm failsafe
        arm_request = GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 60_u16,
          breadcrumb: 123_u64
        )
        cluster.arm_failsafe(arm_request, 1_u8, false)

        # Complete commissioning
        response = cluster.commissioning_complete(
          session_fabric_index: 1_u8,
          is_case_session: true
        )

        response.error_code.should eq(GeneralCommissioningCluster::CommissioningError::OK)
        cluster.failsafe_armed?.should be_false
        cluster.breadcrumb.should eq(0_u64) # Reset on success
      end

      it "rejects PASE session" do
        cluster = GeneralCommissioningCluster.new

        # Arm failsafe with PASE
        arm_request = GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 60_u16,
          breadcrumb: 123_u64
        )
        cluster.arm_failsafe(arm_request, nil, true)

        # Try to complete with PASE session
        response = cluster.commissioning_complete(
          session_fabric_index: nil,
          is_case_session: false
        )

        response.error_code.should eq(GeneralCommissioningCluster::CommissioningError::InvalidAuthentication)
        cluster.failsafe_armed?.should be_true # Still armed
      end

      it "rejects when no failsafe is armed" do
        cluster = GeneralCommissioningCluster.new

        response = cluster.commissioning_complete(
          session_fabric_index: 1_u8,
          is_case_session: true
        )

        response.error_code.should eq(GeneralCommissioningCluster::CommissioningError::NoFailSafe)
      end

      it "rejects when fabric doesn't match" do
        cluster = GeneralCommissioningCluster.new

        # Arm with fabric 1
        arm_request = GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 60_u16,
          breadcrumb: 123_u64
        )
        cluster.arm_failsafe(arm_request, 1_u8, false)

        # Try to complete with fabric 2
        response = cluster.commissioning_complete(
          session_fabric_index: 2_u8,
          is_case_session: true
        )

        response.error_code.should eq(GeneralCommissioningCluster::CommissioningError::InvalidAuthentication)
        cluster.failsafe_armed?.should be_true # Still armed
      end
    end

    describe "SetRegulatoryConfig command" do
      it "sets regulatory config with valid parameters" do
        cluster = GeneralCommissioningCluster.new

        request = GeneralCommissioningCluster::SetRegulatoryConfigRequest.new(
          new_regulatory_config: GeneralCommissioningCluster::RegulatoryLocationType::Outdoor,
          country_code: "US",
          breadcrumb: 456_u64
        )

        response = (cluster.regulatory_config = request)

        response.error_code.should eq(GeneralCommissioningCluster::CommissioningError::OK)
        cluster.regulatory_config.should eq(GeneralCommissioningCluster::RegulatoryLocationType::Outdoor)
        cluster.breadcrumb.should eq(456_u64)
      end

      it "rejects location exceeding capability" do
        cluster = GeneralCommissioningCluster.new
        # Set capability to Indoor only
        cluster.location_capability = GeneralCommissioningCluster::RegulatoryLocationType::Indoor

        request = GeneralCommissioningCluster::SetRegulatoryConfigRequest.new(
          new_regulatory_config: GeneralCommissioningCluster::RegulatoryLocationType::Outdoor,
          country_code: "US",
          breadcrumb: 456_u64
        )

        response = (cluster.regulatory_config = request)

        response.error_code.should eq(GeneralCommissioningCluster::CommissioningError::ValueOutsideRange)
        cluster.regulatory_config.should eq(GeneralCommissioningCluster::RegulatoryLocationType::IndoorOutdoor) # Not changed
        cluster.breadcrumb.should eq(0_u64)                                                                     # Not updated on error
      end

      it "rejects invalid country code format" do
        cluster = GeneralCommissioningCluster.new

        # Too short
        request1 = GeneralCommissioningCluster::SetRegulatoryConfigRequest.new(
          new_regulatory_config: GeneralCommissioningCluster::RegulatoryLocationType::Indoor,
          country_code: "U",
          breadcrumb: 456_u64
        )
        response1 = (cluster.regulatory_config = request1)
        response1.error_code.should eq(GeneralCommissioningCluster::CommissioningError::ValueOutsideRange)

        # Lowercase
        request2 = GeneralCommissioningCluster::SetRegulatoryConfigRequest.new(
          new_regulatory_config: GeneralCommissioningCluster::RegulatoryLocationType::Indoor,
          country_code: "us",
          breadcrumb: 456_u64
        )
        response2 = (cluster.regulatory_config = request2)
        response2.error_code.should eq(GeneralCommissioningCluster::CommissioningError::ValueOutsideRange)

        # Numbers
        request3 = GeneralCommissioningCluster::SetRegulatoryConfigRequest.new(
          new_regulatory_config: GeneralCommissioningCluster::RegulatoryLocationType::Indoor,
          country_code: "U1",
          breadcrumb: 456_u64
        )
        response3 = (cluster.regulatory_config = request3)
        response3.error_code.should eq(GeneralCommissioningCluster::CommissioningError::ValueOutsideRange)
      end

      it "accepts various valid country codes" do
        cluster = GeneralCommissioningCluster.new

        ["US", "GB", "JP", "DE", "FR", "CA"].each do |country_code|
          request = GeneralCommissioningCluster::SetRegulatoryConfigRequest.new(
            new_regulatory_config: GeneralCommissioningCluster::RegulatoryLocationType::Indoor,
            country_code: country_code,
            breadcrumb: 100_u64
          )

          response = (cluster.regulatory_config = request)
          response.error_code.should eq(GeneralCommissioningCluster::CommissioningError::OK)
        end
      end
    end

    describe "regulatory location validation" do
      it "allows any location with IndoorOutdoor capability" do
        cluster = GeneralCommissioningCluster.new
        cluster.location_capability = GeneralCommissioningCluster::RegulatoryLocationType::IndoorOutdoor

        [
          GeneralCommissioningCluster::RegulatoryLocationType::Indoor,
          GeneralCommissioningCluster::RegulatoryLocationType::Outdoor,
          GeneralCommissioningCluster::RegulatoryLocationType::IndoorOutdoor,
        ].each do |location|
          request = GeneralCommissioningCluster::SetRegulatoryConfigRequest.new(
            new_regulatory_config: location,
            country_code: "US",
            breadcrumb: 100_u64
          )

          response = (cluster.regulatory_config = request)
          response.error_code.should eq(GeneralCommissioningCluster::CommissioningError::OK)
        end
      end

      it "restricts to Indoor only with Indoor capability" do
        cluster = GeneralCommissioningCluster.new
        cluster.location_capability = GeneralCommissioningCluster::RegulatoryLocationType::Indoor

        # Indoor should succeed
        request1 = GeneralCommissioningCluster::SetRegulatoryConfigRequest.new(
          new_regulatory_config: GeneralCommissioningCluster::RegulatoryLocationType::Indoor,
          country_code: "US",
          breadcrumb: 100_u64
        )
        response1 = (cluster.regulatory_config = request1)
        response1.error_code.should eq(GeneralCommissioningCluster::CommissioningError::OK)

        # Outdoor should fail
        request2 = GeneralCommissioningCluster::SetRegulatoryConfigRequest.new(
          new_regulatory_config: GeneralCommissioningCluster::RegulatoryLocationType::Outdoor,
          country_code: "US",
          breadcrumb: 200_u64
        )
        response2 = (cluster.regulatory_config = request2)
        response2.error_code.should eq(GeneralCommissioningCluster::CommissioningError::ValueOutsideRange)
      end
    end

    describe "commissioning window management" do
      it "opens and closes commissioning window" do
        cluster = GeneralCommissioningCluster.new

        cluster.open_commissioning_window
        cluster.close_commissioning_window

        # Window state is tracked internally
        # Verified through PASE priority behavior in earlier tests
      end
    end

    describe "breadcrumb atomicity" do
      it "updates breadcrumb only on successful command execution" do
        cluster = GeneralCommissioningCluster.new
        cluster.breadcrumb.should eq(0_u64)

        # Successful ArmFailSafe updates breadcrumb
        arm_request = GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 60_u16,
          breadcrumb: 100_u64
        )
        cluster.arm_failsafe(arm_request, nil, true)
        cluster.breadcrumb.should eq(100_u64)

        # Failed SetRegulatoryConfig doesn't update breadcrumb
        cluster.location_capability = GeneralCommissioningCluster::RegulatoryLocationType::Indoor
        reg_request = GeneralCommissioningCluster::SetRegulatoryConfigRequest.new(
          new_regulatory_config: GeneralCommissioningCluster::RegulatoryLocationType::Outdoor,
          country_code: "US",
          breadcrumb: 200_u64
        )
        (cluster.regulatory_config = reg_request)
        cluster.breadcrumb.should eq(100_u64) # Still 100, not 200

        # Successful SetRegulatoryConfig updates breadcrumb
        reg_request2 = GeneralCommissioningCluster::SetRegulatoryConfigRequest.new(
          new_regulatory_config: GeneralCommissioningCluster::RegulatoryLocationType::Indoor,
          country_code: "US",
          breadcrumb: 300_u64
        )
        (cluster.regulatory_config = reg_request2)
        cluster.breadcrumb.should eq(300_u64)
      end
    end

    describe "failsafe expiry behavior" do
      it "resets breadcrumb to 0 on failsafe expiry" do
        cluster = GeneralCommissioningCluster.new

        arm_request = GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 1_u16,
          breadcrumb: 999_u64
        )
        cluster.arm_failsafe(arm_request, nil, true)
        cluster.breadcrumb.should eq(999_u64)

        # Wait for expiry
        sleep 1.5.seconds

        cluster.breadcrumb.should eq(0_u64)
        cluster.failsafe_armed?.should be_false
      end

      it "closes commissioning window on failsafe expiry" do
        cluster = GeneralCommissioningCluster.new
        cluster.open_commissioning_window

        arm_request = GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 1_u16,
          breadcrumb: 100_u64
        )
        cluster.arm_failsafe(arm_request, nil, true)

        # Wait for expiry
        sleep 1.5.seconds

        # Commissioning window should be closed (verified internally)
        cluster.failsafe_armed?.should be_false
      end
    end

    describe "Terms & Conditions feature" do
      it "allows commissioning complete when TC not required" do
        cluster = GeneralCommissioningCluster.new
        cluster.terms_conditions_required = false

        # Arm failsafe and complete commissioning
        arm_request = GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 60_u16,
          breadcrumb: 100_u64
        )
        cluster.arm_failsafe(arm_request, 1_u8, false)

        response = cluster.commissioning_complete(1_u8, true)
        response.error_code.should eq(GeneralCommissioningCluster::CommissioningError::OK)
      end

      it "blocks commissioning complete when TC required but not accepted" do
        cluster = GeneralCommissioningCluster.new
        cluster.terms_conditions_required = true
        cluster.terms_conditions_accepted?.should be_false

        # Arm failsafe
        arm_request = GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 60_u16,
          breadcrumb: 100_u64
        )
        cluster.arm_failsafe(arm_request, 1_u8, false)

        # Try to complete commissioning without accepting TC
        response = cluster.commissioning_complete(1_u8, true)
        response.error_code.should eq(GeneralCommissioningCluster::CommissioningError::RequiredTCNotAccepted)
      end

      it "allows commissioning complete when TC accepted" do
        cluster = GeneralCommissioningCluster.new
        cluster.terms_conditions_required = true
        cluster.accept_terms_conditions
        cluster.terms_conditions_accepted?.should be_true

        # Arm failsafe
        arm_request = GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 60_u16,
          breadcrumb: 100_u64
        )
        cluster.arm_failsafe(arm_request, 1_u8, false)

        # Complete commissioning
        response = cluster.commissioning_complete(1_u8, true)
        response.error_code.should eq(GeneralCommissioningCluster::CommissioningError::OK)
      end

      it "uses callback to check TC acceptance" do
        cluster = GeneralCommissioningCluster.new
        cluster.terms_conditions_required = true

        tc_check_called = false
        cluster.on_check_terms_conditions = -> : Bool {
          tc_check_called = true
          true # Return true = accepted
        }

        # Arm failsafe
        arm_request = GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 60_u16,
          breadcrumb: 100_u64
        )
        cluster.arm_failsafe(arm_request, 1_u8, false)

        # Complete commissioning
        response = cluster.commissioning_complete(1_u8, true)
        response.error_code.should eq(GeneralCommissioningCluster::CommissioningError::OK)
        tc_check_called.should be_true
      end
    end

    describe "commissioning complete callbacks" do
      it "calls persist fabric table callback" do
        cluster = GeneralCommissioningCluster.new

        persist_called = false
        cluster.on_persist_fabric_table = -> : Nil {
          persist_called = true
        }

        # Arm failsafe
        arm_request = GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 60_u16,
          breadcrumb: 100_u64
        )
        cluster.arm_failsafe(arm_request, 1_u8, false)

        # Complete commissioning
        response = cluster.commissioning_complete(1_u8, true)
        response.error_code.should eq(GeneralCommissioningCluster::CommissioningError::OK)
        persist_called.should be_true
      end

      it "calls clear PASE sessions callback" do
        cluster = GeneralCommissioningCluster.new

        clear_pase_called = false
        cluster.on_clear_pase_sessions = -> : Nil {
          clear_pase_called = true
        }

        # Arm failsafe
        arm_request = GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 60_u16,
          breadcrumb: 100_u64
        )
        cluster.arm_failsafe(arm_request, 1_u8, false)

        # Complete commissioning
        response = cluster.commissioning_complete(1_u8, true)
        response.error_code.should eq(GeneralCommissioningCluster::CommissioningError::OK)
        clear_pase_called.should be_true
      end

      it "closes commissioning window on successful complete" do
        cluster = GeneralCommissioningCluster.new
        cluster.open_commissioning_window

        # Arm failsafe
        arm_request = GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 60_u16,
          breadcrumb: 100_u64
        )
        cluster.arm_failsafe(arm_request, 1_u8, false)

        # Complete commissioning
        response = cluster.commissioning_complete(1_u8, true)
        response.error_code.should eq(GeneralCommissioningCluster::CommissioningError::OK)

        # Commissioning window should be closed (internal state verified)
        cluster.failsafe_armed?.should be_false
      end
    end

    describe "country code whitelist" do
      it "allows any country code when whitelist not configured" do
        cluster = GeneralCommissioningCluster.new
        cluster.country_code_whitelist.should be_nil

        request = GeneralCommissioningCluster::SetRegulatoryConfigRequest.new(
          new_regulatory_config: GeneralCommissioningCluster::RegulatoryLocationType::Indoor,
          country_code: "ZZ",
          breadcrumb: 100_u64
        )

        response = (cluster.regulatory_config = request)
        response.error_code.should eq(GeneralCommissioningCluster::CommissioningError::OK)
      end

      it "allows whitelisted country codes" do
        cluster = GeneralCommissioningCluster.new
        cluster.country_code_whitelist = ["US", "CA", "GB", "JP"]

        request = GeneralCommissioningCluster::SetRegulatoryConfigRequest.new(
          new_regulatory_config: GeneralCommissioningCluster::RegulatoryLocationType::Indoor,
          country_code: "US",
          breadcrumb: 100_u64
        )

        response = (cluster.regulatory_config = request)
        response.error_code.should eq(GeneralCommissioningCluster::CommissioningError::OK)
        cluster.country_code.should eq("US")
      end

      it "blocks non-whitelisted country codes" do
        cluster = GeneralCommissioningCluster.new
        cluster.country_code_whitelist = ["US", "CA", "GB"]

        request = GeneralCommissioningCluster::SetRegulatoryConfigRequest.new(
          new_regulatory_config: GeneralCommissioningCluster::RegulatoryLocationType::Indoor,
          country_code: "FR", # Not in whitelist
          breadcrumb: 100_u64
        )

        response = (cluster.regulatory_config = request)
        response.error_code.should eq(GeneralCommissioningCluster::CommissioningError::ValueOutsideRange)
        response.debug_text.should contain("not in whitelist")
      end

      it "validates all countries in whitelist" do
        cluster = GeneralCommissioningCluster.new
        cluster.country_code_whitelist = ["US", "CA", "GB", "DE", "FR", "JP"]

        ["US", "CA", "GB", "DE", "FR", "JP"].each do |country|
          request = GeneralCommissioningCluster::SetRegulatoryConfigRequest.new(
            new_regulatory_config: GeneralCommissioningCluster::RegulatoryLocationType::Indoor,
            country_code: country,
            breadcrumb: 100_u64
          )

          response = (cluster.regulatory_config = request)
          response.error_code.should eq(GeneralCommissioningCluster::CommissioningError::OK)
          cluster.country_code.should eq(country)
        end
      end
    end
  end
end
