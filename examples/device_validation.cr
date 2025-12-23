require "option_parser"
require "json"
require "file_utils"
require "colorize"

# Device validation helper that shells out to `chip-tool`.
#
# Intended usage (after pairing with `chip-tool`):
#   crystal run examples/device_validation.cr
#
# Or, with a custom chip-tool path:
#   crystal run examples/device_validation.cr -- --chip-tool /path/to/chip-tool

record ChipResult, args : Array(String), exit_code : Int32, stdout : String, stderr : String do
  def ok? : Bool
    exit_code == 0
  end

  def output : String
    "#{stdout}\n#{stderr}"
  end
end

record CheckResult, name : String, ok : Bool, details : String

def strip_ansi(s : String) : String
  # Remove ANSI color codes commonly emitted by chip-tool.
  s.gsub(/\e\[[0-9;]*m/, "")
end

def run_chip_tool(chip_tool : String, args : Array(String), storage_dir : String? = nil) : ChipResult
  # Many chip-tool builds accept `--storage-directory` as an option that must appear
  # after the required positional arguments (see chip-tool docs).
  final_args = if storage_dir && args.first? != "storage"
                 args + ["--storage-directory", storage_dir]
               else
                 args
               end

  stdout = IO::Memory.new
  stderr = IO::Memory.new
  status = Process.run(chip_tool, final_args, output: stdout, error: stderr)
  ChipResult.new(final_args, status.exit_code, stdout.to_s, stderr.to_s)
end

def extract_bool(output : String, label : String) : Bool?
  text = strip_ansi(output)
  # Example line: "[TOO]   OnOff: TRUE"
  if m = text.match(/#{Regex.escape(label)}:\s*(TRUE|FALSE)\b/i)
    m[1].upcase == "TRUE"
  end
end

def extract_uint_list_from_attribute_list(output : String) : Array(UInt32)?
  text = strip_ansi(output)
  return nil unless text.includes?("AttributeList:")

  values = [] of UInt32
  text.each_line do |line|
    # Example line: "[TOO]     [10]: 65533 (ClusterRevision)"
    if m = line.match(/\[\d+\]:\s*(\d+)\b/)
      values << m[1].to_u32
    end
  end
  values
end

def check_command_ok(name : String, result : ChipResult) : CheckResult
  return CheckResult.new(name, true, "ok") if result.ok?

  text = strip_ansi(result.output)
  summary = text.each_line.select do |line|
    line.includes?("Run command failure") ||
      line.includes?("Secure Pairing Failed") ||
      line.includes?("Failed to verify peer") ||
      line.includes?("Failed to open pairing window") ||
      line.includes?("Error: IM Error") ||
      line.includes?("IM Error") ||
      line.includes?("Incorrect state") ||
      line.includes?("Timeout") ||
      line.includes?("ERROR") ||
      line.includes?("[TOO] Error")
  end.to_a.last? || text.lines.last? || "unknown error"

  CheckResult.new(name, false, "chip-tool exited #{result.exit_code}: #{summary}")
end

def parse_u64(s : String) : UInt64?
  v = s.strip
  return nil if v.empty?
  if v.starts_with?("0x") || v.starts_with?("0X")
    v[2..].to_u64?(16)
  else
    # Support "0000000000000001" (hex) and "1" (decimal).
    if v.size >= 16 && v.each_char.all? { |c| c.in?('0'..'9') || c.in?('a'..'f') || c.in?('A'..'F') }
      v.to_u64?(16)
    else
      v.to_u64?
    end
  end
end

def extract_commissioning_pairing_code(output : String) : String?
  text = strip_ansi(output)

  # Common chip-tool output:
  #   Manual pairing code: [1495-753-5193]
  #   Manual pairing code: 1495-753-5193
  #   Manual pairing code: 34970112332
  if m = text.match(/Manual pairing code:\s*\[?([0-9]{4}-[0-9]{3}-[0-9]{4})\]?/i)
    return m[1]
  end
  if m = text.match(/Manual pairing code:\s*\[?([0-9]{11})\]?/i)
    return m[1]
  end
  if m = text.match(/\b([0-9]{4}-[0-9]{3}-[0-9]{4})\b/)
    return m[1]
  end
  nil
end

record FabricIndexInfo, node_id : UInt64, fabric_index : UInt8

def extract_fabric_indices(output : String) : Array(FabricIndexInfo)
  text = strip_ansi(output)
  results = [] of FabricIndexInfo
  current_node : UInt64? = nil
  current_index : UInt8? = nil

  text.each_line do |line|
    if m = line.match(/\bNodeId:\s*(0x[0-9a-fA-F]+|[0-9a-fA-F]{16}|[0-9]+)\b/i)
      current_node = parse_u64(m[1])
    end

    if m = line.match(/\bFabricIndex:\s*(\d+)\b/i)
      current_index = m[1].to_u8?
    end

    if current_node && current_index
      results << FabricIndexInfo.new(current_node.not_nil!, current_index.not_nil!)
      current_node = nil
      current_index = nil
    end
  end

  results
end

record AclEntryInfo, fabric_index : UInt8, privilege : UInt8, auth_mode : UInt8, subjects : Array(UInt64)

def extract_acl_entries(output : String) : Array(AclEntryInfo)
  text = strip_ansi(output)
  entries = [] of AclEntryInfo

  current_fabric : UInt8? = nil
  current_privilege : UInt8? = nil
  current_auth : UInt8? = nil
  current_subjects = [] of UInt64
  in_subjects = false

  flush = -> do
    if current_fabric && current_privilege && current_auth
      entries << AclEntryInfo.new(current_fabric.not_nil!, current_privilege.not_nil!, current_auth.not_nil!, current_subjects.dup)
    end
    current_fabric = nil
    current_privilege = nil
    current_auth = nil
    current_subjects.clear
    in_subjects = false
  end

  text.each_line do |line|
    if line.match(/\bFabricIndex:\s*\d+\b/i) && current_fabric
      flush.call
    end

    if m = line.match(/\bFabricIndex:\s*(\d+)\b/i)
      current_fabric = m[1].to_u8?
    end

    # Examples:
    #   Privilege: 5
    #   Privilege: Administer (5)
    if m = line.match(/\bPrivilege:\s*(?:[A-Za-z]+\s*\()?(\d+)\)?\b/i)
      current_privilege = m[1].to_u8?
    end

    # Examples:
    #   AuthMode: 2
    #   AuthMode: CASE (2)
    if m = line.match(/\bAuthMode:\s*(?:[A-Za-z]+\s*\()?(\d+)\)?\b/i)
      current_auth = m[1].to_u8?
    end

    if line.match(/\bSubjects\b/i)
      in_subjects = true
      next
    end

    if in_subjects
      # End of list (varies by chip-tool formatting)
      # chip-tool prints subjects as e.g. "[1]: 112233" so we can't treat any "]" as list-end.
      if line.strip.in?("]", "],") || line.match(/\bTargets\b/i)
        in_subjects = false
      end

      subject_text = nil.as(String?)

      # Most common: "[1]: 112233"
      if m = line.match(/\[\d+\]:\s*(0x[0-9a-fA-F]+|[0-9a-fA-F]{16}|[0-9]+)\b/)
        subject_text = m[1]
      else
        # Fall back to the last numeric token on the line (avoids capturing timestamps like "[pid:tid]").
        tokens = line.scan(/\b0x[0-9a-fA-F]+\b|\b[0-9a-fA-F]{16}\b|\b\d+\b/)
        if last = tokens.last?
          subject_text = last[0]
        end
      end

      if subject_text && (subject = parse_u64(subject_text))
        current_subjects << subject
      end
    end
  end

  flush.call
  entries
end

def expected_access_denied?(result : ChipResult) : Bool
  return true unless result.ok?
  text = strip_ansi(result.output).upcase
  return true if text.includes?("UNSUPPORTED_ACCESS")
  return true if text.includes?("ACCESS_DENIED")
  return true if text.includes?("UNSUPPORTED ACCESS")
  false
end

def build_view_only_acl_json(subject : UInt64, endpoint_id : UInt16) : String
  JSON.build do |json|
    json.array do
      json.object do
        json.field "privilege", 1 # View
        json.field "authMode", 2  # CASE
        json.field "subjects" do
          json.array { json.number subject }
        end
        # Allow read-only access to basic attributes useful for controllers + the target cluster.
        json.field "targets" do
          json.array do
            # OnOff (cluster 6) on endpoint X
            json.object do
              json.field "endpoint", endpoint_id
              json.field "cluster", 6
              json.field "deviceType", nil
            end
            # Descriptor (cluster 29) and BasicInformation (cluster 40) on endpoint 0
            json.object do
              json.field "endpoint", 0
              json.field "cluster", 29
              json.field "deviceType", nil
            end
            json.object do
              json.field "endpoint", 0
              json.field "cluster", 40
              json.field "deviceType", nil
            end
          end
        end
      end
    end
  end
end

chip_tool = ENV["CHIP_TOOL"]? || "chip-tool"
node_id = "1"
endpoint_id = "1"
node_id_b = nil.as(String?)
storage_dir_a = nil.as(String?)
storage_dir_b = "tmp/device_validation/chip-tool-b-#{Random::Secure.hex(8)}"
open_window_timeout_s = 300
pairing_code_override = nil.as(String?)

OptionParser.parse do |parser|
  parser.banner = "Usage: device_validation [options] [node_id_a] [endpoint_id] (defaults: 1 1)"
  parser.on("--chip-tool PATH", "Path to chip-tool (default: chip-tool, or env CHIP_TOOL)") { |v| chip_tool = v }
  parser.on("--storage-a DIR", "chip-tool storage directory for Fabric A (passed via --storage-directory)") { |v| storage_dir_a = v }
  parser.on("--storage-b DIR", "chip-tool storage directory for Fabric B (default: tmp/device_validation/chip-tool-b-<random>)") { |v| storage_dir_b = v }
  parser.on("--node-id-b NODEID", "Operational node id to assign the device in Fabric B (default: node_id_a+1)") { |v| node_id_b = v }
  parser.on("--open-window-timeout SECONDS", "Commissioning window timeout seconds (default: 300)") { |v| open_window_timeout_s = v.to_i }
  parser.on("--pairing-code CODE", "Skip opening a commissioning window and use this manual pairing code for Fabric B commissioning") { |v| pairing_code_override = v }
  parser.on("-h", "--help", "Show help") do
    puts parser
    exit 0
  end

  parser.invalid_option do |flag|
    STDERR.puts "Unknown option: #{flag}"
    STDERR.puts parser
    exit 2
  end

  parser.unknown_args do |args|
    node_id = args[0]? || node_id
    endpoint_id = args[1]? || endpoint_id
  end
end

checks = [] of CheckResult

def run_check(
  checks : Array(CheckResult),
  chip_tool : String,
  storage_dir : String?,
  name : String,
  args : Array(String),
  &block : ChipResult -> CheckResult
)
  print name
  result = run_chip_tool(chip_tool, args, storage_dir: storage_dir)
  check = yield result
  checks << check
  if check.ok
    puts " [passed]".colorize(:green)
  else
    puts " [failed]".colorize(:red)
    STDERR.puts "FAIL: #{check.name} - #{check.details}"
    STDERR.puts "--- chip-tool stdout ---"
    STDERR.puts strip_ansi(result.stdout)
    STDERR.puts "--- chip-tool stderr ---"
    STDERR.puts strip_ansi(result.stderr)
  end
end

run_check(checks, chip_tool, storage_dir_a, "basicinformation.vendor-name", ["basicinformation", "read", "vendor-name", node_id, "0"]) do |r|
  check_command_ok("basicinformation.vendor-name", r)
end

run_check(checks, chip_tool, storage_dir_a, "descriptor.parts-list", ["descriptor", "read", "parts-list", node_id, "0"]) do |r|
  next check_command_ok("descriptor.parts-list", r) unless r.ok?
  text = strip_ansi(r.output)
  if text.match(/\bPartsList:\s*\d+\s+entries\b/) && text.match(/\[\d+\]:\s*#{Regex.escape(endpoint_id)}\b/)
    CheckResult.new("descriptor.parts-list", true, "endpoint #{endpoint_id} present")
  else
    CheckResult.new("descriptor.parts-list", false, "endpoint #{endpoint_id} missing from PartsList")
  end
end

initial_on_off = nil.as(Bool?)
run_check(checks, chip_tool, storage_dir_a, "onoff.on-off (read)", ["onoff", "read", "on-off", node_id, endpoint_id]) do |r|
  next check_command_ok("onoff.on-off (read)", r) unless r.ok?
  value = extract_bool(r.output, "OnOff")
  if value.is_a?(Bool)
    initial_on_off = value
    CheckResult.new("onoff.on-off (read)", true, "OnOff=#{value}")
  else
    CheckResult.new("onoff.on-off (read)", false, "could not parse OnOff value")
  end
end

run_check(checks, chip_tool, storage_dir_a, "onoff.attribute-list", ["onoff", "read", "attribute-list", node_id, endpoint_id]) do |r|
  next check_command_ok("onoff.attribute-list", r) unless r.ok?

  list = extract_uint_list_from_attribute_list(r.output)
  unless list
    next CheckResult.new("onoff.attribute-list", false, "could not parse AttributeList")
  end

  duplicates = list.group_by(&.itself).select { |_, v| v.size > 1 }.keys
  unless duplicates.empty?
    next CheckResult.new("onoff.attribute-list", false, "duplicates found: #{duplicates.sort.join(", ")}")
  end

  required = [65528_u32, 65529_u32, 65531_u32, 65532_u32, 65533_u32] # generated/accepted/attribute-list/feature-map/cluster-revision
  missing = required.reject { |id| list.includes?(id) }
  unless missing.empty?
    next CheckResult.new("onoff.attribute-list", false, "missing required global attributes: #{missing.join(", ")}")
  end

  CheckResult.new("onoff.attribute-list", true, "ok (#{list.size} attrs)")
end

run_check(checks, chip_tool, storage_dir_a, "onoff.toggle", ["onoff", "toggle", node_id, endpoint_id]) do |r|
  check_command_ok("onoff.toggle", r)
end

run_check(checks, chip_tool, storage_dir_a, "onoff.on-off (read after toggle)", ["onoff", "read", "on-off", node_id, endpoint_id]) do |r|
  next check_command_ok("onoff.on-off (read after toggle)", r) unless r.ok?
  new_value = extract_bool(r.output, "OnOff")
  if new_value.nil? || initial_on_off.nil?
    next CheckResult.new("onoff.on-off (read after toggle)", false, "invalid state, no value should be nil: initial: #{initial_on_off.inspect}, toggled: #{new_value.inspect}")
  else
    if new_value == initial_on_off
      next CheckResult.new("onoff.on-off (read after toggle)", false, "toggle did not change OnOff (still #{new_value})")
    end
  end
  CheckResult.new("onoff.on-off (read after toggle)", true, "OnOff=#{new_value.inspect}")
end

# -----------------------------------------------------------------------------
# Multi-fabric + commissioning window + ACL validation
# -----------------------------------------------------------------------------

node_id_a_u64 = parse_u64(node_id)
node_id_b ||= begin
  if node_id_a_u64
    (node_id_a_u64 + 1).to_s
  else
    "2"
  end
end

endpoint_u16 = endpoint_id.to_u16? || 1_u16

pairing_code = pairing_code_override
window_discriminator = Random.rand(0..4095).to_s
begin
  Dir.mkdir_p(File.dirname(storage_dir_b))
rescue
end

# Always start Fabric B with a clean chip-tool fabric store so we actually create a second fabric.
b_storage_ready = false
begin
  FileUtils.rm_rf(storage_dir_b)
  Dir.mkdir_p(storage_dir_b)
  b_storage_ready = true
  checks << CheckResult.new("fabric-b.storage.clear-all", true, "cleared #{storage_dir_b}")
rescue ex
  checks << CheckResult.new("fabric-b.storage.clear-all", false, "failed to reset #{storage_dir_b}: #{ex.message}")
end

unless b_storage_ready
  checks << CheckResult.new("commissioning.fabric-b.pairing-code", false, "skipped: Fabric B storage not cleared (storage_dir_b=#{storage_dir_b})")
  checks << CheckResult.new("operationalcredentials.fabrics", false, "skipped: Fabric B storage not cleared")
  checks << CheckResult.new("accesscontrol.acl (discover subjects)", false, "skipped: Fabric B storage not cleared")
  pairing_code = nil
end

if pairing_code.nil? && b_storage_ready
  # Best-effort: close any existing commissioning window so repeated runs don't
  # fail with BUSY.
  begin
    result = run_chip_tool(chip_tool, ["administratorcommissioning", "revoke-commissioning", node_id, "0"], storage_dir: storage_dir_a)
    if result.ok?
      checks << CheckResult.new("commissioning.revoke-window", true, "revoked")
    else
      checks << CheckResult.new("commissioning.revoke-window", true, "skipped (already closed or revoke failed)")
    end
  rescue ex
    checks << CheckResult.new("commissioning.revoke-window", true, "skipped (exception: #{ex.message})")
  end

  # Some chip-tool versions require: node-id option window-timeout iteration discriminator
  # Use option=1 (enhanced window) so chip-tool outputs an ephemeral pairing code.
  run_check(checks, chip_tool, storage_dir_a, "commissioning.open-window", ["pairing", "open-commissioning-window", node_id, "1", open_window_timeout_s.to_s, "1000", window_discriminator]) do |r|
    next check_command_ok("commissioning.open-window", r) unless r.ok?
    code = extract_commissioning_pairing_code(r.output)
    if code
      pairing_code = code
      CheckResult.new("commissioning.open-window", true, "pairing_code=#{code} discriminator=#{window_discriminator}")
    else
      CheckResult.new("commissioning.open-window", false, "could not extract pairing code from chip-tool output")
    end
  end
else
  checks << CheckResult.new("commissioning.open-window", true, "skipped (pairing_code provided)") if pairing_code
end

if pairing_code && b_storage_ready
  run_check(checks, chip_tool, storage_dir_b, "commissioning.fabric-b.pairing-code", ["pairing", "code", node_id_b.not_nil!, pairing_code.not_nil!]) do |r|
    check_command_ok("commissioning.fabric-b.pairing-code", r)
  end

  fabric_index_a = nil.as(UInt8?)
  fabric_index_b = nil.as(UInt8?)

  run_check(checks, chip_tool, storage_dir_a, "operationalcredentials.fabrics", ["operationalcredentials", "read", "fabrics", node_id, "0"]) do |r|
    next check_command_ok("operationalcredentials.fabrics", r) unless r.ok?
    infos = extract_fabric_indices(r.output)
    if node_id_a_u64 && (idx = infos.find { |fi| fi.node_id == node_id_a_u64 })
      fabric_index_a = idx.fabric_index
    end
    if node_id_b_u64 = parse_u64(node_id_b.not_nil!)
      # Node IDs can be reused across fabrics; pick the most recently allocated fabric index.
      matches = infos.select { |fi| fi.node_id == node_id_b_u64 }
      if idx = matches.max_by?(&.fabric_index)
        fabric_index_b = idx.fabric_index
      end
    end

    if fabric_index_a && fabric_index_b
      CheckResult.new("operationalcredentials.fabrics", true, "fabric_a=#{fabric_index_a} fabric_b=#{fabric_index_b}")
    else
      CheckResult.new("operationalcredentials.fabrics", false, "could not determine fabric indices (a=#{fabric_index_a.inspect} b=#{fabric_index_b.inspect})")
    end
  end

  subject_a = nil.as(UInt64?)
  subject_b = nil.as(UInt64?)

  run_check(checks, chip_tool, storage_dir_a, "accesscontrol.acl.fabric-a (discover admin)", ["accesscontrol", "read", "acl", node_id, "0"]) do |r|
    next check_command_ok("accesscontrol.acl.fabric-a (discover admin)", r) unless r.ok?
    entries = extract_acl_entries(r.output)
    entry = entries.find { |e| e.auth_mode == 2_u8 && e.privilege >= 5_u8 && !e.subjects.empty? }
    subject_a = entry.try(&.subjects.first?)
    if subject_a
      CheckResult.new("accesscontrol.acl.fabric-a (discover admin)", true, "subject_a=#{subject_a}")
    else
      CheckResult.new("accesscontrol.acl.fabric-a (discover admin)", false, "no Administer CASE entry found for Fabric A")
    end
  end

  run_check(checks, chip_tool, storage_dir_b, "accesscontrol.acl.fabric-b (discover admin)", ["accesscontrol", "read", "acl", node_id_b.not_nil!, "0"]) do |r|
    next check_command_ok("accesscontrol.acl.fabric-b (discover admin)", r) unless r.ok?
    entries = extract_acl_entries(r.output)
    entry = entries.find { |e| e.auth_mode == 2_u8 && e.privilege >= 5_u8 && !e.subjects.empty? }
    subject_b = entry.try(&.subjects.first?)
    if subject_b
      CheckResult.new("accesscontrol.acl.fabric-b (discover admin)", true, "subject_b=#{subject_b}")
    else
      CheckResult.new("accesscontrol.acl.fabric-b (discover admin)", false, "no Administer CASE entry found for Fabric B")
    end
  end

  if subject_b
    view_only_acl = build_view_only_acl_json(subject_b.not_nil!, endpoint_u16)
    run_check(checks, chip_tool, storage_dir_b, "accesscontrol.write-acl.fabric-b (set view-only)", ["accesscontrol", "write", "acl", view_only_acl, node_id_b.not_nil!, "0"]) do |r|
      check_command_ok("accesscontrol.write-acl.fabric-b (set view-only)", r)
    end

    run_check(checks, chip_tool, storage_dir_b, "fabric-b.basicinformation.vendor-name (view)", ["basicinformation", "read", "vendor-name", node_id_b.not_nil!, "0"]) do |r|
      check_command_ok("fabric-b.basicinformation.vendor-name (view)", r)
    end

    run_check(checks, chip_tool, storage_dir_b, "fabric-b.descriptor.parts-list (view)", ["descriptor", "read", "parts-list", node_id_b.not_nil!, "0"]) do |r|
      check_command_ok("fabric-b.descriptor.parts-list (view)", r)
    end

    run_check(checks, chip_tool, storage_dir_b, "fabric-b.onoff.on-off (view)", ["onoff", "read", "on-off", node_id_b.not_nil!, endpoint_id]) do |r|
      next check_command_ok("fabric-b.onoff.on-off (view)", r) unless r.ok?
      value = extract_bool(r.output, "OnOff")
      if value.nil?
        CheckResult.new("fabric-b.onoff.on-off (view)", false, "could not parse OnOff value")
      else
        CheckResult.new("fabric-b.onoff.on-off (view)", true, "OnOff=#{value}")
      end
    end

    run_check(checks, chip_tool, storage_dir_b, "fabric-b.onoff.on (should be denied)", ["onoff", "on", node_id_b.not_nil!, endpoint_id]) do |r|
      if expected_access_denied?(r)
        CheckResult.new("fabric-b.onoff.on (should be denied)", true, "denied as expected")
      else
        CheckResult.new("fabric-b.onoff.on (should be denied)", false, "expected access denied/unsupported access but command appeared to succeed")
      end
    end

    run_check(checks, chip_tool, storage_dir_b, "fabric-b.accesscontrol.read-acl (should be denied)", ["accesscontrol", "read", "acl", node_id_b.not_nil!, "0"]) do |r|
      if expected_access_denied?(r)
        CheckResult.new("fabric-b.accesscontrol.read-acl (should be denied)", true, "denied as expected")
      else
        CheckResult.new("fabric-b.accesscontrol.read-acl (should be denied)", false, "expected access denied/unsupported access but read appeared to succeed")
      end
    end

    run_check(checks, chip_tool, storage_dir_a, "fabric-a.onoff.toggle (still allowed)", ["onoff", "toggle", node_id, endpoint_id]) do |r|
      check_command_ok("fabric-a.onoff.toggle (still allowed)", r)
    end
  end
end

passed = checks.all?(&.ok)
if passed
  puts "PASS (#{checks.size} checks)"
  exit 0
else
  failed = checks.count { |c| !c.ok }
  puts "FAIL (#{failed}/#{checks.size} checks)"
  if pairing_code
    STDERR.puts "Note: last pairing_code=#{pairing_code} discriminator=#{window_discriminator}"
  end
  exit 1
end
