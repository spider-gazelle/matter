module Matter
  module Cluster
    module Definitions
      module AccountLogin
        # Input to the AccountLogin getSetupPin command
        struct GetSetupPinRequest
          include TLV::Serializable

          # This attribute shall specify the client’s Temporary Account Identifier. The length of this field shall be at
          # least 16 characters to protect the account holder against password guessing attacks.

          @[TLV::Field(tag: 0)]
          property temp_account_identifier : String
        end

        # This message is sent in response to the GetSetupPIN command, and contains the Setup PIN code, or null when the
        # account identified in the request does not match the active account of the running Content App.
        struct GetSetupPinResponse
          include TLV::Serializable

          # This field shall provide the setup PIN code as a text string at least 11 characters in length or null to
          # indicate that the accounts do not match.

          @[TLV::Field(tag: 0)]
          property setup_pin : String?
        end

        # Input to the AccountLogin login command
        struct LoginRequest
          include TLV::Serializable

          # This field shall specify the client’s temporary account identifier.
          @[TLV::Field(tag: 0)]
          property temp_account_identifier : String

          # This field shall provide the setup PIN code as a text string at least 11 characters in length.
          @[TLV::Field(tag: 1)]
          property setup_pin : String?
        end
      end
    end
  end
end
