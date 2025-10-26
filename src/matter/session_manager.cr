require "log"

module Matter
  # SessionManager manages secure communication sessions
  #
  # Matter uses two types of sessions:
  # - PASE (Password-Authenticated Session Establishment): Used during commissioning
  # - CASE (Certificate-Authenticated Session Establishment): Used for operational communication
  #
  # During failsafe rollback, PASE sessions must be cleared to prevent
  # unauthorized access if commissioning fails.
  #
  # Matter Core Spec §4.13 - Secure Channel Protocol
  class SessionManager
    Log = ::Log.for("matter.session_manager")

    # PASE sessions (indexed by session ID or connection identifier)
    # TODO: Replace with actual PASE session storage when PASE is implemented
    @pase_sessions : Hash(UInt16, PaseSession)

    # CASE sessions (indexed by session ID)
    # TODO: Replace with actual CASE session storage when CASE is implemented
    @case_sessions : Hash(UInt16, CaseSession)

    def initialize
      @pase_sessions = Hash(UInt16, PaseSession).new
      @case_sessions = Hash(UInt16, CaseSession).new
      Log.info { "SessionManager initialized" }
    end

    # Clear all PASE sessions
    #
    # This is called during failsafe rollback to remove all PASE sessions
    # established during commissioning. This ensures that if commissioning
    # fails, the temporary authenticated sessions are removed.
    def clear_pase_sessions : Nil
      count = @pase_sessions.size
      @pase_sessions.clear
      Log.info { "Cleared #{count} PASE session(s)" }
    end

    # Clear all CASE sessions (typically used for device reset)
    def clear_case_sessions : Nil
      count = @case_sessions.size
      @case_sessions.clear
      Log.info { "Cleared #{count} CASE session(s)" }
    end

    # Clear all sessions
    def clear_all_sessions : Nil
      clear_pase_sessions
      clear_case_sessions
      Log.info { "All sessions cleared" }
    end

    # Get count of active PASE sessions
    def pase_session_count : Int32
      @pase_sessions.size
    end

    # Get count of active CASE sessions
    def case_session_count : Int32
      @case_sessions.size
    end

    # Get total session count
    def total_session_count : Int32
      @pase_sessions.size + @case_sessions.size
    end

    # Placeholder classes for session types
    # These will be replaced with actual implementations when PASE/CASE are implemented

    # PASE session (Password-Authenticated Session Establishment)
    class PaseSession
      property session_id : UInt16
      property established_at : Time

      def initialize(@session_id : UInt16, @established_at : Time = Time.utc)
      end
    end

    # CASE session (Certificate-Authenticated Session Establishment)
    class CaseSession
      property session_id : UInt16
      property fabric_index : UInt8
      property peer_node_id : UInt64
      property established_at : Time

      def initialize(
        @session_id : UInt16,
        @fabric_index : UInt8,
        @peer_node_id : UInt64,
        @established_at : Time = Time.utc,
      )
      end
    end
  end
end
