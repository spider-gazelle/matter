require "./service_type"

module Matter
  module MDNS
    # Minimal interface used by higher-level device lifecycle components to
    # switch between commissioning and operational advertisements.
    #
    # This avoids coupling lifecycle logic to the concrete `MDNS::Responder`
    # (which binds sockets) and supports test doubles.
    module ResponderInterface
      abstract def stop_commissioning : Nil
      abstract def advertise_commissioning(info : CommissioningInfo, port : Int32 = 5540, ttl : Time::Span = 120.seconds) : Nil

      abstract def advertise_operational(info : OperationalInfo, port : Int32 = 5540, ttl : Time::Span = 120.seconds) : Nil
      abstract def stop_operational_advertisement : Nil
    end
  end
end
