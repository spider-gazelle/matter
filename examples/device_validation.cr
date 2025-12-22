require "option_parser"

# Device validation helper that shells out to `chip-tool`.
#
# Intended usage (after pairing with `chip-tool`):
#   crystal run examples/device_validation.cr -- 1 1
#
# Or, with a custom chip-tool path:
#   crystal run examples/device_validation.cr -- --chip-tool /path/to/chip-tool 1 1

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

def run_chip_tool(chip_tool : String, args : Array(String)) : ChipResult
  stdout = IO::Memory.new
  stderr = IO::Memory.new
  status = Process.run(chip_tool, args, output: stdout, error: stderr)
  ChipResult.new(args, status.exit_code, stdout.to_s, stderr.to_s)
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
  CheckResult.new(name, false, "chip-tool exited #{result.exit_code}: #{strip_ansi(result.output).lines.last? || "unknown error"}")
end

chip_tool = ENV["CHIP_TOOL"]? || "chip-tool"
verbose = false
node_id = "1"
endpoint_id = "1"

OptionParser.parse do |parser|
  parser.banner = "Usage: device_validation [options] <node_id> <endpoint_id>"
  parser.on("--chip-tool PATH", "Path to chip-tool (default: chip-tool, or env CHIP_TOOL)") { |v| chip_tool = v }
  parser.on("-v", "--verbose", "Print chip-tool output for failures") { verbose = true }
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
  name : String,
  args : Array(String),
  verbose : Bool,
  &block : ChipResult -> CheckResult
)
  result = run_chip_tool(chip_tool, args)
  check = yield result
  checks << check
  unless check.ok
    STDERR.puts "FAIL: #{check.name} - #{check.details}"
    if verbose
      STDERR.puts "--- chip-tool stdout ---"
      STDERR.puts strip_ansi(result.stdout)
      STDERR.puts "--- chip-tool stderr ---"
      STDERR.puts strip_ansi(result.stderr)
    end
  end
end

run_check(checks, chip_tool, "basicinformation.vendor-name", ["basicinformation", "read", "vendor-name", node_id, "0"], verbose) do |r|
  check_command_ok("basicinformation.vendor-name", r)
end

run_check(checks, chip_tool, "descriptor.parts-list", ["descriptor", "read", "parts-list", node_id, "0"], verbose) do |r|
  next check_command_ok("descriptor.parts-list", r) unless r.ok?
  text = strip_ansi(r.output)
  if text.match(/\bPartsList:\s*\d+\s+entries\b/) && text.match(/\[\d+\]:\s*#{Regex.escape(endpoint_id)}\b/)
    CheckResult.new("descriptor.parts-list", true, "endpoint #{endpoint_id} present")
  else
    CheckResult.new("descriptor.parts-list", false, "endpoint #{endpoint_id} missing from PartsList")
  end
end

initial_on_off = nil.as(Bool?)
run_check(checks, chip_tool, "onoff.on-off (read)", ["onoff", "read", "on-off", node_id, endpoint_id], verbose) do |r|
  next check_command_ok("onoff.on-off (read)", r) unless r.ok?
  value = extract_bool(r.output, "OnOff")
  if value.is_a?(Bool)
    initial_on_off = value
    CheckResult.new("onoff.on-off (read)", true, "OnOff=#{value}")
  else
    CheckResult.new("onoff.on-off (read)", false, "could not parse OnOff value")
  end
end

run_check(checks, chip_tool, "onoff.attribute-list", ["onoff", "read", "attribute-list", node_id, endpoint_id], verbose) do |r|
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

run_check(checks, chip_tool, "onoff.toggle", ["onoff", "toggle", node_id, endpoint_id], verbose) do |r|
  check_command_ok("onoff.toggle", r)
end

run_check(checks, chip_tool, "onoff.on-off (read after toggle)", ["onoff", "read", "on-off", node_id, endpoint_id], verbose) do |r|
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

passed = checks.all?(&.ok)
if passed
  puts "PASS (#{checks.size} checks)"
  exit 0
else
  failed = checks.count { |c| !c.ok }
  puts "FAIL (#{failed}/#{checks.size} checks)"
  exit 1
end
