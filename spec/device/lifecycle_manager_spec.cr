require "../spec_helper"

module Matter
  class FakeResponder
    include MDNS::ResponderInterface

    getter stop_commissioning_calls = 0
    getter stop_operational_calls = 0
    getter advertise_commissioning_calls = 0
    getter advertise_operational_calls = 0

    def stop_commissioning : Nil
      @stop_commissioning_calls += 1
    end

    def advertise_commissioning(info : MDNS::CommissioningInfo, port : Int32 = 5540, ttl : Time::Span = 120.seconds) : Nil
      @advertise_commissioning_calls += 1
    end

    def advertise_operational(info : MDNS::OperationalInfo, port : Int32 = 5540, ttl : Time::Span = 120.seconds) : Nil
      @advertise_operational_calls += 1
    end

    def stop_operational_advertisement : Nil
      @stop_operational_calls += 1
    end
  end

  class FakeSessionManager
    include Protocol::SessionManager

    getter sessions : Hash(UInt16, Session::SecureContext) = {} of UInt16 => Session::SecureContext
    getter deleted : Array(UInt16) = [] of UInt16

    def delete_session(session_id : UInt16) : Bool
      existed = @sessions.delete(session_id)
      @deleted << session_id
      !existed.nil?
    end
  end
end

describe Matter::Device::LifecycleManager do
  it "defers CASE session cleanup on fabric removal" do
    storage = Matter::Storage::MemoryBackend.new
    fabric_table = Matter::FabricTable.new(storage)

    handler = Matter::FakeSessionManager.new
    handler.sessions[22282_u16] = Matter::Session::SecureContext.new(
      session_id: 22282_u16,
      peer_session_id: 40019_u16,
      session_type: Matter::Session::SessionType::Unicast,
      encryption_key: Bytes.new(16, 0_u8),
      decryption_key: Bytes.new(16, 0_u8),
      initiator: false,
      case_session: true,
      fabric_index: 1_u8
    )

    advertiser = Matter::FakeResponder.new
    opcreds = Matter::Cluster::OperationalCredentialsCluster.new(fabric_table)

    Matter::Device::LifecycleManager.new(
      fabric_table: fabric_table,
      message_handler: handler,
      operational_credentials: opcreds,
      responder: advertiser,
      commissioning_info: -> {
        Matter::MDNS::CommissioningInfo.new(
          device_name: "test",
          vendor_id: 0xFFF1_u16,
          product_id: 0x8000_u16,
          discriminator: 3840_u16,
          device_type: 0_u32,
          commissioning_mode: Matter::MDNS::CommissioningMode::Basic
        )
      },
      fabric_session_cleanup_delay: 200.milliseconds
    )

    opcreds.on_fabric_removed.as(Proc(UInt8, Nil)).call(1_u8)

    handler.sessions.has_key?(22282_u16).should be_true
    sleep 50.milliseconds
    handler.sessions.has_key?(22282_u16).should be_true

    sleep 300.milliseconds
    handler.sessions.has_key?(22282_u16).should be_false
    handler.deleted.should contain(22282_u16)

    # Ensure mDNS switches were invoked (fabric table is empty, so commissioning should be advertised)
    advertiser.advertise_commissioning_calls.should be >= 1
  end
end
