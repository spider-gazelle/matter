module Matter
  module InteractionModel
    # Interaction Model status codes from Matter spec
    enum StatusCode : UInt8
      # Success
      Success = 0x00

      # General errors
      Failure               = 0x01
      InvalidSubscription   = 0x7D
      UnsupportedAccess     = 0x7E
      UnsupportedEndpoint   = 0x7F
      InvalidAction         = 0x80
      UnsupportedCommand    = 0x81
      Deprecated82          = 0x82
      Deprecated83          = 0x83
      Deprecated84          = 0x84
      InvalidCommand        = 0x85
      UnsupportedAttribute  = 0x86
      ConstraintError       = 0x87
      UnsupportedWrite      = 0x88
      ResourceExhausted     = 0x89
      Deprecated8A          = 0x8A
      NotFound              = 0x8B
      UnreportableAttribute = 0x8C
      InvalidDataType       = 0x8D
      Deprecated8E          = 0x8E
      UnsupportedRead       = 0x8F
      Deprecated90          = 0x90
      Deprecated91          = 0x91
      DataVersionMismatch   = 0x92
      Deprecated93          = 0x93
      Timeout               = 0x94
      Reserved95            = 0x95
      Reserved96            = 0x96
      Reserved97            = 0x97
      Reserved98            = 0x98
      Reserved99            = 0x99
      Reserved9A            = 0x9A
      Reserved9B            = 0x9B
      Busy                  = 0x9C
      Deprecated9D          = 0x9D
      Deprecated9E          = 0x9E
      Deprecated9F          = 0x9F
      DeprecatedA0          = 0xA0

      # Cluster-specific errors (0xC0-0xFF range)
      # These are defined in Matter spec section 8.5.2
      UnsupportedCluster = 0xC3 # Request is for a cluster that doesn't exist on the endpoint
      DeprecatedA1       = 0xA1
      DeprecatedA2       = 0xA2
      DeprecatedA3       = 0xA3
      DeprecatedA4       = 0xA4
      DeprecatedA5       = 0xA5
      DeprecatedA6       = 0xA6
      DeprecatedA7       = 0xA7
      DeprecatedA8       = 0xA8

      # Cluster-specific range 0xC0-0xFF
      # Applications can define cluster-specific error codes in this range

      def success?
        self == Success
      end

      def to_s : String
        case self
        when Success
          "Success"
        when Failure
          "Failure"
        when InvalidSubscription
          "Invalid Subscription"
        when UnsupportedAccess
          "Unsupported Access"
        when UnsupportedEndpoint
          "Unsupported Endpoint"
        when InvalidAction
          "Invalid Action"
        when UnsupportedCommand
          "Unsupported Command"
        when InvalidCommand
          "Invalid Command"
        when UnsupportedAttribute
          "Unsupported Attribute"
        when ConstraintError
          "Constraint Error"
        when UnsupportedWrite
          "Unsupported Write"
        when ResourceExhausted
          "Resource Exhausted"
        when NotFound
          "Not Found"
        when UnreportableAttribute
          "Unreportable Attribute"
        when InvalidDataType
          "Invalid Data Type"
        when UnsupportedRead
          "Unsupported Read"
        when DataVersionMismatch
          "Data Version Mismatch"
        when Timeout
          "Timeout"
        when Busy
          "Busy"
        when UnsupportedCluster
          "Unsupported Cluster"
        else
          "Unknown Status (0x#{value.to_s(16)})"
        end
      end
    end

    # Status response with optional cluster-specific status
    struct Status
      property status : StatusCode
      property cluster_status : UInt8?

      def initialize(@status : StatusCode, @cluster_status : UInt8? = nil)
      end

      def success?
        @status.success?
      end

      def to_s : String
        if cluster_status = @cluster_status
          "#{@status} (cluster: 0x#{cluster_status.to_s(16)})"
        else
          @status.to_s
        end
      end
    end
  end
end
