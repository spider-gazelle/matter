require "option_parser"

# A small "smoke test" validator that shells out to `chip-tool` and checks for
# missing/duplicate Descriptor and Root Node requirements.
#
# Usage:
#   crystal run examples/device_validation.cr -- --node 1
#   crystal run examples/device_validation.cr -- --chip-tool ~/connectedhomeip/out/debug/chip-tool --node 1234
#
# Notes:
# - This intentionally does not try to be a full spec compliance suite.
# - It focuses on low-hanging fruit: missing clusters and duplicate list entries.
module DeviceValidation
  class ChipTool
    getter path : String

    def initialize(@path : String)
    end

    def run(args : Array(String)) : String
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      status = Process.run(@path, args, output: stdout_io, error: stderr_io)
      output = String.build do |io|
        io << stdout_io.to_s
        stderr_str = stderr_io.to_s
        io << '\n' unless io.empty? || stderr_str.empty?
        io << stderr_str
      end
      unless status.success?
        raise "chip-tool failed (#{status.exit_code}) running: #{@path} #{args.join(" ")}\n#{output}"
      end
      output
    end
  end

  enum Severity
    Warn
    Fail
  end

  struct Issue
    getter severity : Severity
    getter message : String

    def initialize(@severity : Severity, @message : String)
    end
  end

  # Very small parser for typical chip-tool "Data = [ ... ]" outputs.
  module ChipToolParse
    ANSI_ESCAPE = /\e\[[0-9;]*m/

    def self.strip_ansi(text : String) : String
      text.gsub(ANSI_ESCAPE, "")
    end

    def self.extract_data_block(text : String) : String?
      cleaned = strip_ansi(text)
      idx = cleaned.index("Data =")
      return nil unless idx

      rest = cleaned[idx..-1]
      open_idx = rest.index('[')
      close_idx = rest.index(']')
      return nil unless open_idx && close_idx && close_idx > open_idx

      rest[(open_idx + 1)...close_idx]
    end

    def self.parse_u32_list(text : String) : Array(UInt32)
      cleaned = strip_ansi(text)

      # Primary: parse the stable `[TOO]` formatted list:
      #   [TOO]   ServerList: 13 entries
      #   [TOO]     [1]: 29 (Descriptor)
      values = [] of UInt32
      cleaned.each_line do |line|
        next unless line.includes?("[TOO]")
        if m = line.match(/\[\d+\]:\s*(\d+)/)
          values << m[1].to_u32
        end
      end
      return values unless values.empty?

      # Fallback: parse DMG "Data = [ ... ]" block, if present.
      block = extract_data_block(cleaned) || ""
      block.scan(/0x[0-9a-fA-F]+/) { |m| values << m[0].to_u32(16) }
      block.scan(/(\d+)\s*\(unsigned\)/) { |m| values << m[1].to_u32 } if values.empty?
      block.scan(/\b\d+\b/) { |m| values << m[0].to_u32 } if values.empty?
      values
    end

    # Parses `Descriptor::DeviceTypeList` output and extracts the `deviceType` values.
    # chip-tool usually prints something like:
    #   Data = [
    #     0: {
    #       DeviceType: 22
    #       Revision: 1
    #     },
    #   ]
    def self.parse_device_types(text : String) : Array(UInt32)
      types = [] of UInt32

      # Accept a couple of common spellings/casings
      strip_ansi(text).scan(/(?:DeviceType|deviceType)\s*:\s*(0x[0-9a-fA-F]+|\d+)/) do |m|
        raw = m[1]
        types << (raw.starts_with?("0x") ? raw.to_u32(16) : raw.to_u32)
      end

      types.uniq!
      types
    end
  end

  module Checks
    DESCRIPTOR_CLUSTER_ID = 0x001D_u32
    ROOT_NODE_DEVICE_TYPE = 0x0016_u32

    ROOT_REQUIRED_CLUSTERS = [
      0x001D_u32, # Descriptor
      0x001F_u32, # Access Control
      0x0028_u32, # Basic Information
      0x0030_u32, # General Commissioning
      0x0031_u32, # Network Commissioning
      0x0033_u32, # General Diagnostics
      0x003C_u32, # Administrator Commissioning
      0x003E_u32, # Operational Credentials
      0x003F_u32, # Group Key Management
    ]

    ROOT_RECOMMENDED_CLUSTERS = [
      0x0046_u32, # ICD Management (queried by iOS controllers)
    ]
  end

  class Validator
    def initialize(@chip : ChipTool, @node_id : UInt64)
    end

    def run : Array(Issue)
      issues = [] of Issue

      endpoints = discover_endpoints(issues)
      endpoints.each do |endpoint_id|
        server_list = read_server_list(endpoint_id, issues)
        next if server_list.empty?

        if server_list.size != server_list.uniq.size
          issues << Issue.new(Severity::Fail, "Endpoint #{endpoint_id}: duplicate entries in Descriptor::ServerList")
        end

        unless server_list.includes?(Checks::DESCRIPTOR_CLUSTER_ID)
          issues << Issue.new(Severity::Fail, "Endpoint #{endpoint_id}: missing Descriptor cluster (0x001D) in ServerList")
        end

        device_types = read_device_type_list(endpoint_id, issues)
        if device_types.empty?
          issues << Issue.new(Severity::Fail, "Endpoint #{endpoint_id}: empty Descriptor::DeviceTypeList")
        elsif device_types.size != device_types.uniq.size
          issues << Issue.new(Severity::Fail, "Endpoint #{endpoint_id}: duplicate entries in Descriptor::DeviceTypeList")
        end

        if endpoint_id == 0_u16
          check_root_endpoint(server_list, issues)
        end
      end

      issues
    end

    private def discover_endpoints(issues : Array(Issue)) : Array(UInt16)
      # Root endpoint always exists
      endpoints = [0_u16]

      begin
        chip_output = @chip.run(["descriptor", "read", "parts-list", @node_id.to_s, "0"])
        parts = ChipToolParse.parse_u32_list(chip_output).map(&.to_u16)
        if parts.size != parts.uniq.size
          issues << Issue.new(Severity::Fail, "Descriptor::PartsList contains duplicate endpoint IDs")
        end
        parts.each { |ep| endpoints << ep unless endpoints.includes?(ep) }
      rescue ex
        issues << Issue.new(Severity::Warn, "Failed reading Descriptor::PartsList (endpoint discovery): #{ex.message}")
      end

      endpoints.sort!
      endpoints
    end

    private def read_server_list(endpoint_id : UInt16, issues : Array(Issue)) : Array(UInt32)
      chip_output = @chip.run(["descriptor", "read", "server-list", @node_id.to_s, endpoint_id.to_s])
      ChipToolParse.parse_u32_list(chip_output)
    rescue ex
      issues << Issue.new(Severity::Fail, "Endpoint #{endpoint_id}: failed reading Descriptor::ServerList: #{ex.message}")
      [] of UInt32
    end

    private def read_device_type_list(endpoint_id : UInt16, issues : Array(Issue)) : Array(UInt32)
      chip_output = @chip.run(["descriptor", "read", "device-type-list", @node_id.to_s, endpoint_id.to_s])
      ChipToolParse.parse_device_types(chip_output)
    rescue ex
      issues << Issue.new(Severity::Fail, "Endpoint #{endpoint_id}: failed reading Descriptor::DeviceTypeList: #{ex.message}")
      [] of UInt32
    end

    private def check_root_endpoint(server_list : Array(UInt32), issues : Array(Issue)) : Nil
      Checks::ROOT_REQUIRED_CLUSTERS.each do |cluster_id|
        unless server_list.includes?(cluster_id)
          issues << Issue.new(Severity::Fail, "Endpoint 0: missing required cluster 0x#{cluster_id.to_s(16)} in ServerList")
        end
      end

      Checks::ROOT_RECOMMENDED_CLUSTERS.each do |cluster_id|
        unless server_list.includes?(cluster_id)
          issues << Issue.new(Severity::Warn, "Endpoint 0: missing recommended cluster 0x#{cluster_id.to_s(16)} in ServerList")
        end
      end

      # Root node device type must exist on endpoint 0.
      device_types = read_device_type_list(0_u16, issues)
      unless device_types.includes?(Checks::ROOT_NODE_DEVICE_TYPE)
        issues << Issue.new(Severity::Fail, "Endpoint 0: Descriptor::DeviceTypeList missing Root Node device type (0x0016)")
      end
    end
  end
end

chip_tool_path = "chip-tool"
node_id = 1_u64

OptionParser.parse do |parser|
  parser.banner = "Usage: device_validation [options]"

  parser.on("--chip-tool PATH", "Path to chip-tool (default: chip-tool)") { |v| chip_tool_path = v }
  parser.on("--node NODE_ID", "Node ID to validate (default: 1)") { |v| node_id = v.to_u64 }
  parser.on("-h", "--help", "Show help") do
    puts parser
    exit 0
  end
end

begin
  chip = DeviceValidation::ChipTool.new(chip_tool_path)
  validator = DeviceValidation::Validator.new(chip, node_id)
  issues = validator.run

  failures = issues.select { |i| i.severity.fail? }
  warnings = issues.select { |i| i.severity.warn? }

  if failures.empty?
    puts "PASS"
  else
    puts "FAIL"
  end

  unless failures.empty?
    puts "\nFailures:"
    failures.each { |i| puts "- #{i.message}" }
  end

  unless warnings.empty?
    puts "\nWarnings:"
    warnings.each { |i| puts "- #{i.message}" }
  end
rescue ex
  STDERR.puts "FAIL"
  STDERR.puts ex.message
  exit 2
end
