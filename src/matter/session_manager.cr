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

    # PASE sessions (indexed by session ID)
    @pase_sessions : Hash(UInt16, PaseSession)

    # CASE sessions (indexed by session ID)
    @case_sessions : Hash(UInt16, CaseSession)

    def initialize
      @pase_sessions = Hash(UInt16, PaseSession).new
      @case_sessions = Hash(UInt16, CaseSession).new
      Log.info { "SessionManager initialized" }
    end

    # ========================================================================
    # PASE Session Management
    # ========================================================================

    # Create a new PASE session
    def create_pase_session(session_id : UInt16) : PaseSession
      session = PaseSession.new(session_id)
      @pase_sessions[session_id] = session
      Log.info { "Created PASE session: id=#{session_id}" }
      session
    end

    # Add an existing PASE session
    def add_pase_session(session : PaseSession) : Nil
      @pase_sessions[session.session_id] = session
      Log.info { "Added PASE session: id=#{session.session_id}" }
    end

    # Get a PASE session by ID
    def get_pase_session(session_id : UInt16) : PaseSession?
      @pase_sessions[session_id]?
    end

    # Remove a specific PASE session
    def remove_pase_session(session_id : UInt16) : PaseSession?
      session = @pase_sessions.delete(session_id)
      Log.info { "Removed PASE session: id=#{session_id}" } if session
      session
    end

    # Check if a PASE session exists
    def has_pase_session?(session_id : UInt16) : Bool
      @pase_sessions.has_key?(session_id)
    end

    # Get all PASE session IDs
    def pase_session_ids : Array(UInt16)
      @pase_sessions.keys
    end

    # ========================================================================
    # CASE Session Management
    # ========================================================================

    # Create a new CASE session
    def create_case_session(
      session_id : UInt16,
      fabric_index : UInt8,
      peer_node_id : UInt64,
      vendor_id : UInt16 = 0xFFF1_u16,
    ) : CaseSession
      session = CaseSession.new(session_id, fabric_index, peer_node_id, vendor_id)
      @case_sessions[session_id] = session
      Log.info { "Created CASE session: id=#{session_id}, fabric=#{fabric_index}, vendor=#{vendor_id}, peer=#{peer_node_id}" }
      session
    end

    # Add an existing CASE session
    def add_case_session(session : CaseSession) : Nil
      @case_sessions[session.session_id] = session
      Log.info { "Added CASE session: id=#{session.session_id}, fabric=#{session.fabric_index}" }
    end

    # Get a CASE session by ID
    def get_case_session(session_id : UInt16) : CaseSession?
      @case_sessions[session_id]?
    end

    # Remove a specific CASE session
    def remove_case_session(session_id : UInt16) : CaseSession?
      session = @case_sessions.delete(session_id)
      Log.info { "Removed CASE session: id=#{session_id}" } if session
      session
    end

    # Check if a CASE session exists
    def has_case_session?(session_id : UInt16) : Bool
      @case_sessions.has_key?(session_id)
    end

    # Get all CASE session IDs
    def case_session_ids : Array(UInt16)
      @case_sessions.keys
    end

    # Get all CASE sessions for a specific fabric
    def get_fabric_sessions(fabric_index : UInt8) : Array(CaseSession)
      @case_sessions.values.select { |s| s.fabric_index == fabric_index }
    end

    # Remove all CASE sessions for a specific fabric
    def remove_fabric_sessions(fabric_index : UInt8) : Int32
      initial_count = @case_sessions.size
      @case_sessions.reject! { |_, session| session.fabric_index == fabric_index }
      removed_count = initial_count - @case_sessions.size
      Log.info { "Removed #{removed_count} CASE session(s) for fabric #{fabric_index}" } if removed_count > 0
      removed_count
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

    # ========================================================================
    # Session Classes
    # ========================================================================

    # PASE session (Password-Authenticated Session Establishment)
    #
    # PASE sessions are established during commissioning using a passcode.
    # They are temporary and should be cleared during failsafe rollback.
    class PaseSession
      property session_id : UInt16
      property passcode : UInt32? # Optional: PIN/passcode used
      property established_at : Time
      property last_activity : Time

      def initialize(
        @session_id : UInt16,
        @passcode : UInt32? = nil,
        @established_at : Time = Time.utc,
        @last_activity : Time = Time.utc,
      )
      end

      # Check if session is expired (default: 60 minutes)
      def expired?(timeout : Time::Span = 60.minutes) : Bool
        Time.utc - @last_activity > timeout
      end

      # Update last activity timestamp
      def touch : Nil
        @last_activity = Time.utc
      end
    end

    # CASE session (Certificate-Authenticated Session Establishment)
    #
    # CASE sessions are established using certificates for operational communication.
    # They persist until explicitly removed or device reset.
    class CaseSession
      property session_id : UInt16
      property fabric_index : UInt8
      property vendor_id : UInt16    # Vendor ID from fabric
      property peer_node_id : UInt64 # Node ID of peer device
      property established_at : Time
      property last_activity : Time

      def initialize(
        @session_id : UInt16,
        @fabric_index : UInt8,
        @peer_node_id : UInt64,
        @vendor_id : UInt16 = 0xFFF1_u16, # Default test vendor ID
        @established_at : Time = Time.utc,
        @last_activity : Time = Time.utc,
      )
      end

      # Check if session is expired (default: 24 hours)
      def expired?(timeout : Time::Span = 24.hours) : Bool
        Time.utc - @last_activity > timeout
      end

      # Update last activity timestamp
      def touch : Nil
        @last_activity = Time.utc
      end
    end
  end
end
