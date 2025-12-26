require "./spec_helper"
require "../src/matter/session_manager"

describe Matter::SessionManager do
  describe "initialization" do
    it "creates session manager" do
      manager = Matter::SessionManager.new
      manager.pase_session_count.should eq(0)
      manager.case_session_count.should eq(0)
      manager.total_session_count.should eq(0)
    end
  end

  describe "PASE session management" do
    it "creates PASE session" do
      manager = Matter::SessionManager.new
      session = manager.create_pase_session(1_u16)

      session.session_id.should eq(1_u16)
      manager.pase_session_count.should eq(1)
    end

    it "creates PASE session with passcode" do
      manager = Matter::SessionManager.new
      session = Matter::SessionManager::PaseSession.new(2_u16, passcode: 20202021_u32)
      manager.add_pase_session(session)

      session.passcode.should eq(20202021_u32)
      manager.pase_session_count.should eq(1)
    end

    it "retrieves PASE session by ID" do
      manager = Matter::SessionManager.new
      manager.create_pase_session(3_u16)

      retrieved = manager.get_pase_session(3_u16)
      retrieved.should_not be_nil
      retrieved.as(Matter::SessionManager::PaseSession).session_id.should eq(3_u16)
    end

    it "returns nil for non-existent PASE session" do
      manager = Matter::SessionManager.new
      manager.get_pase_session(99_u16).should be_nil
    end

    it "checks if PASE session exists" do
      manager = Matter::SessionManager.new
      manager.create_pase_session(4_u16)

      manager.has_pase_session?(4_u16).should be_true
      manager.has_pase_session?(99_u16).should be_false
    end

    it "removes specific PASE session" do
      manager = Matter::SessionManager.new
      manager.create_pase_session(5_u16)
      manager.pase_session_count.should eq(1)

      removed = manager.remove_pase_session(5_u16)
      removed.should_not be_nil
      removed.as(Matter::SessionManager::PaseSession).session_id.should eq(5_u16)
      manager.pase_session_count.should eq(0)
    end

    it "returns nil when removing non-existent session" do
      manager = Matter::SessionManager.new
      manager.remove_pase_session(99_u16).should be_nil
    end

    it "gets all PASE session IDs" do
      manager = Matter::SessionManager.new
      manager.create_pase_session(1_u16)
      manager.create_pase_session(2_u16)
      manager.create_pase_session(3_u16)

      ids = manager.pase_session_ids
      ids.size.should eq(3)
      ids.should contain(1_u16)
      ids.should contain(2_u16)
      ids.should contain(3_u16)
    end

    it "clears all PASE sessions" do
      manager = Matter::SessionManager.new
      manager.create_pase_session(1_u16)
      manager.create_pase_session(2_u16)
      manager.create_pase_session(3_u16)
      manager.pase_session_count.should eq(3)

      manager.clear_pase_sessions
      manager.pase_session_count.should eq(0)
    end
  end

  describe "CASE session management" do
    it "creates CASE session" do
      manager = Matter::SessionManager.new
      session = manager.create_case_session(
        session_id: 10_u16,
        fabric_index: 1_u8,
        peer_node_id: 0x1234567890ABCDEF_u64
      )

      session.session_id.should eq(10_u16)
      session.fabric_index.should eq(1_u8)
      session.peer_node_id.should eq(0x1234567890ABCDEF_u64)
      session.vendor_id.should eq(0xFFF1_u16) # Default
      manager.case_session_count.should eq(1)
    end

    it "creates CASE session with custom vendor ID" do
      manager = Matter::SessionManager.new
      session = manager.create_case_session(
        session_id: 11_u16,
        fabric_index: 2_u8,
        peer_node_id: 0x1111111111111111_u64,
        vendor_id: 0xABCD_u16
      )

      session.vendor_id.should eq(0xABCD_u16)
    end

    it "retrieves CASE session by ID" do
      manager = Matter::SessionManager.new
      manager.create_case_session(
        session_id: 12_u16,
        fabric_index: 1_u8,
        peer_node_id: 0x2222222222222222_u64
      )

      retrieved = manager.get_case_session(12_u16)
      retrieved.should_not be_nil
      retrieved.as(Matter::SessionManager::CaseSession).session_id.should eq(12_u16)
      retrieved.as(Matter::SessionManager::CaseSession).fabric_index.should eq(1_u8)
    end

    it "returns nil for non-existent CASE session" do
      manager = Matter::SessionManager.new
      manager.get_case_session(99_u16).should be_nil
    end

    it "checks if CASE session exists" do
      manager = Matter::SessionManager.new
      manager.create_case_session(13_u16, 1_u8, 0x3333333333333333_u64)

      manager.has_case_session?(13_u16).should be_true
      manager.has_case_session?(99_u16).should be_false
    end

    it "removes specific CASE session" do
      manager = Matter::SessionManager.new
      manager.create_case_session(14_u16, 1_u8, 0x4444444444444444_u64)
      manager.case_session_count.should eq(1)

      removed = manager.remove_case_session(14_u16)
      removed.should_not be_nil
      removed.as(Matter::SessionManager::CaseSession).session_id.should eq(14_u16)
      manager.case_session_count.should eq(0)
    end

    it "gets all CASE session IDs" do
      manager = Matter::SessionManager.new
      manager.create_case_session(20_u16, 1_u8, 0x1000000000000001_u64)
      manager.create_case_session(21_u16, 2_u8, 0x2000000000000002_u64)
      manager.create_case_session(22_u16, 1_u8, 0x3000000000000003_u64)

      ids = manager.case_session_ids
      ids.size.should eq(3)
      ids.should contain(20_u16)
      ids.should contain(21_u16)
      ids.should contain(22_u16)
    end

    it "gets sessions by fabric index" do
      manager = Matter::SessionManager.new
      manager.create_case_session(30_u16, 1_u8, 0x1000000000000001_u64)
      manager.create_case_session(31_u16, 2_u8, 0x2000000000000002_u64)
      manager.create_case_session(32_u16, 1_u8, 0x3000000000000003_u64)
      manager.create_case_session(33_u16, 3_u8, 0x4000000000000004_u64)

      fabric1_sessions = manager.get_fabric_sessions(1_u8)
      fabric1_sessions.size.should eq(2)
      fabric1_sessions.map(&.session_id).should contain(30_u16)
      fabric1_sessions.map(&.session_id).should contain(32_u16)

      fabric2_sessions = manager.get_fabric_sessions(2_u8)
      fabric2_sessions.size.should eq(1)
      fabric2_sessions[0].session_id.should eq(31_u16)
    end

    it "removes all sessions for a fabric" do
      manager = Matter::SessionManager.new
      manager.create_case_session(40_u16, 1_u8, 0x1000000000000001_u64)
      manager.create_case_session(41_u16, 2_u8, 0x2000000000000002_u64)
      manager.create_case_session(42_u16, 1_u8, 0x3000000000000003_u64)
      manager.case_session_count.should eq(3)

      count = manager.remove_fabric_sessions(1_u8)
      count.should eq(2)
      manager.case_session_count.should eq(1)
      manager.has_case_session?(40_u16).should be_false
      manager.has_case_session?(42_u16).should be_false
      manager.has_case_session?(41_u16).should be_true
    end

    it "returns 0 when removing sessions for non-existent fabric" do
      manager = Matter::SessionManager.new
      manager.create_case_session(50_u16, 1_u8, 0x1000000000000001_u64)

      count = manager.remove_fabric_sessions(99_u8)
      count.should eq(0)
      manager.case_session_count.should eq(1)
    end

    it "clears all CASE sessions" do
      manager = Matter::SessionManager.new
      manager.create_case_session(60_u16, 1_u8, 0x1000000000000001_u64)
      manager.create_case_session(61_u16, 2_u8, 0x2000000000000002_u64)
      manager.create_case_session(62_u16, 3_u8, 0x3000000000000003_u64)
      manager.case_session_count.should eq(3)

      manager.clear_case_sessions
      manager.case_session_count.should eq(0)
    end
  end

  describe "mixed session management" do
    it "tracks total session count" do
      manager = Matter::SessionManager.new
      manager.create_pase_session(1_u16)
      manager.create_pase_session(2_u16)
      manager.create_case_session(10_u16, 1_u8, 0x1000000000000001_u64)
      manager.create_case_session(11_u16, 2_u8, 0x2000000000000002_u64)

      manager.pase_session_count.should eq(2)
      manager.case_session_count.should eq(2)
      manager.total_session_count.should eq(4)
    end

    it "clears all sessions independently" do
      manager = Matter::SessionManager.new
      manager.create_pase_session(1_u16)
      manager.create_case_session(10_u16, 1_u8, 0x1000000000000001_u64)

      manager.clear_pase_sessions
      manager.pase_session_count.should eq(0)
      manager.case_session_count.should eq(1)

      manager.clear_case_sessions
      manager.case_session_count.should eq(0)
    end

    it "clears all sessions at once" do
      manager = Matter::SessionManager.new
      manager.create_pase_session(1_u16)
      manager.create_pase_session(2_u16)
      manager.create_case_session(10_u16, 1_u8, 0x1000000000000001_u64)
      manager.create_case_session(11_u16, 2_u8, 0x2000000000000002_u64)
      manager.total_session_count.should eq(4)

      manager.clear_all_sessions
      manager.total_session_count.should eq(0)
    end
  end

  describe "PASE session behavior" do
    it "tracks established time" do
      session = Matter::SessionManager::PaseSession.new(1_u16)
      session.established_at.should be_close(Time.utc, 1.second)
    end

    it "tracks last activity time" do
      session = Matter::SessionManager::PaseSession.new(1_u16)
      original_time = session.last_activity

      sleep 10.milliseconds
      session.touch

      session.last_activity.should be > original_time
    end

    it "detects expired sessions" do
      past_time = Time.utc - 2.hours
      session = Matter::SessionManager::PaseSession.new(
        1_u16,
        established_at: past_time,
        last_activity: past_time
      )

      session.expired?(timeout: 1.hour).should be_true
      session.expired?(timeout: 3.hours).should be_false
    end

    it "detects non-expired sessions" do
      session = Matter::SessionManager::PaseSession.new(1_u16)
      session.expired?(timeout: 60.minutes).should be_false
    end
  end

  describe "CASE session behavior" do
    it "tracks established time" do
      session = Matter::SessionManager::CaseSession.new(1_u16, 1_u8, 0x1234567890ABCDEF_u64)
      session.established_at.should be_close(Time.utc, 1.second)
    end

    it "tracks last activity time" do
      session = Matter::SessionManager::CaseSession.new(1_u16, 1_u8, 0x1234567890ABCDEF_u64)
      original_time = session.last_activity

      sleep 10.milliseconds
      session.touch

      session.last_activity.should be > original_time
    end

    it "detects expired sessions" do
      past_time = Time.utc - 48.hours
      session = Matter::SessionManager::CaseSession.new(
        1_u16,
        1_u8,
        0x1234567890ABCDEF_u64,
        established_at: past_time,
        last_activity: past_time
      )

      session.expired?(timeout: 24.hours).should be_true
      session.expired?(timeout: 72.hours).should be_false
    end

    it "detects non-expired sessions" do
      session = Matter::SessionManager::CaseSession.new(1_u16, 1_u8, 0x1234567890ABCDEF_u64)
      session.expired?(timeout: 24.hours).should be_false
    end

    it "stores fabric information" do
      session = Matter::SessionManager::CaseSession.new(
        1_u16,
        5_u8,
        0xABCDEF1234567890_u64,
        vendor_id: 0x1234_u16
      )

      session.fabric_index.should eq(5_u8)
      session.vendor_id.should eq(0x1234_u16)
      session.peer_node_id.should eq(0xABCDEF1234567890_u64)
    end
  end

  describe "failsafe integration" do
    it "supports PASE session clearing for failsafe rollback" do
      manager = Matter::SessionManager.new

      # Simulate commissioning with multiple PASE sessions
      manager.create_pase_session(1_u16)
      manager.create_pase_session(2_u16)
      manager.create_case_session(10_u16, 1_u8, 0x1000000000000001_u64)

      manager.pase_session_count.should eq(2)
      manager.case_session_count.should eq(1)

      # Simulate failsafe rollback
      manager.clear_pase_sessions

      # PASE sessions should be cleared, CASE sessions remain
      manager.pase_session_count.should eq(0)
      manager.case_session_count.should eq(1)
    end
  end
end
