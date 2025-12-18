require "../session/context"

module Matter
  module Protocol
    # Minimal interface for lifecycle code that needs to enumerate and delete
    # sessions (and their subscriptions) without depending on the full
    # `Protocol::MessageHandler` implementation.
    module SessionManager
      abstract def sessions : Hash(UInt16, Session::SecureContext)
      abstract def delete_session(session_id : UInt16) : Bool
    end
  end
end
