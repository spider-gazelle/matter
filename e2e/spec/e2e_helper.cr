require "spec"
require "socket"
require "../../src/matter"

# Helpers for the chip-tool driven end-to-end specs.
#
# The specs run inside the `tests` container of docker-compose.yml. Every
# example device runs in its own container (hostname = compose service name)
# and mirrors its console output to `#{E2E::LOG_DIR}/<example>.log`, from which
# the pairing code is read.
#
# Environment:
#   CHIP_TOOL         chip-tool binary (default: chip-tool)
#   E2E_LOG_DIR       directory holding the device logs (default: /e2e/logs)
#   E2E_STORAGE_DIR   root for per-device chip-tool storage directories
#   E2E_PAIRING       "code" (mDNS discovery, default) or "address"
#                     (`pairing already-discovered` using the device's IPv6 address)
#   E2E_HOST_SUFFIX   appended to device hostnames (unused inside compose)
module E2E
  CHIP_TOOL    = ENV["CHIP_TOOL"]? || "chip-tool"
  LOG_DIR      = ENV["E2E_LOG_DIR"]? || "/e2e/logs"
  STORAGE_ROOT = ENV["E2E_STORAGE_DIR"]? || "/tmp/e2e/chip-tool"
  PAIRING      = ENV["E2E_PAIRING"]? || "code"
  HOST_SUFFIX  = ENV["E2E_HOST_SUFFIX"]? || ""
  DEVICE_PORT  = 5540

  PAIRING_CODE_TIMEOUT = (ENV["E2E_PAIRING_CODE_TIMEOUT"]? || "90").to_i.seconds
  COMMAND_TIMEOUT      = (ENV["E2E_COMMAND_TIMEOUT"]? || "180").to_i.seconds

  ANSI_RE = /\e\[[0-9;]*[A-Za-z]/

  def self.strip_ansi(text : String) : String
    text.gsub(ANSI_RE, "")
  end

  # Outcome of a single chip-tool invocation.
  class Result
    getter args : Array(String)
    getter exit_code : Int32
    # Combined stdout + stderr with ANSI colour codes removed.
    getter output : String

    def initialize(@args, @exit_code, @output)
    end

    def command : String
      "chip-tool #{args.join(" ")}"
    end

    # chip-tool exits non-zero on failure in recent versions, but older builds
    # only log `Run command failure`, so check both.
    def success? : Bool
      exit_code == 0 && !output.includes?("Run command failure")
    end

    # Interaction model status reported by the device, e.g. "SUCCESS" or
    # "CONSTRAINT_ERROR" (last one printed).
    def im_status : String?
      status = nil
      output.scan(/(?:status = |General error: )0x[0-9A-Fa-f]+ \(([A-Z_]+)\)/) { |match| status = match[1] }
      status
    end

    # First value printed for an attribute, e.g. `[TOO]   OnOff: TRUE` => "TRUE".
    def value(name : String) : String?
      values(name).first?
    end

    # Every value printed for `name` (list entries repeat the field name).
    def values(name : String) : Array(String)
      found = [] of String
      output.each_line do |line|
        next unless line.includes?("[TOO]") || line.includes?("CHIP:TOO")
        if m = line.match(/\b#{Regex.escape(name)}:\s*(.*?)\s*,?\s*$/)
          found << m[1]
        end
      end
      found
    end

    def bool(name : String) : Bool?
      case value(name).try(&.upcase)
      when "TRUE"  then true
      when "FALSE" then false
      end
    end

    # Leading integer of a value, e.g. `DeviceType: 256 (On/Off Light)` => 256
    def int(name : String) : Int64?
      value(name).try(&.split(/\s+/).first.to_i64?)
    end

    def ints(name : String) : Array(Int64)
      values(name).compact_map(&.split(/\s+/).first.to_i64?)
    end

    # `[TOO]   PartsList: 2 entries` followed by `[TOO]     [1]: 1` lines
    # (chip-tool may annotate entries, e.g. `[1]: 65533 (ClusterRevision)`).
    def int_list(name : String) : Array(Int64)
      entries = [] of Int64
      in_list = false
      output.each_line do |line|
        if line.matches?(/\b#{Regex.escape(name)}:\s*\d+ entries/)
          in_list = true
          next
        end
        next unless in_list
        if m = line.match(/\[\d+\]:\s*(-?\d+)\b/)
          entries << m[1].to_i64
        elsif !line.includes?("[TOO]") && !line.includes?("CHIP:TOO")
          break
        end
      end
      entries
    end

    def to_s(io : IO) : Nil
      io << "$ " << command << " (exit " << exit_code << ")\n" << output
    end

    def tail(lines : Int32 = 40) : String
      output.lines.last(lines).join("\n")
    end
  end

  # Runs chip-tool, killing it if it exceeds `timeout` (a device that never
  # answers would otherwise stall the whole suite).
  def self.run(args : Array(String), storage_dir : String? = nil, timeout : Time::Span = COMMAND_TIMEOUT) : Result
    final_args = storage_dir ? args + ["--storage-directory", storage_dir] : args
    output = IO::Memory.new
    process = Process.new(CHIP_TOOL, final_args, output: output, error: output)

    done = Channel(Process::Status).new(1)
    spawn { done.send(process.wait) }

    status = select
    when result = done.receive
      result
    when timeout(timeout)
      process.terminate rescue nil
      sleep 1.second
      process.signal(Signal::KILL) rescue nil
      output << "\n[e2e] chip-tool killed after #{timeout.total_seconds.to_i}s timeout\n"
      done.receive
    end

    Result.new(final_args, status.exit_code, strip_ansi(output.to_s))
  end

  class CommissioningError < Exception
  end

  # One example device container. Instances are shared across specs so each
  # device is only commissioned once per run.
  class Device
    getter name : String
    getter host : String
    getter node_id : UInt64
    getter storage_dir : String

    @@devices = {} of String => Device
    @commissioned = false
    @commissioning_error : Exception?

    def self.[](name : String) : Device
      @@devices[name] ||= new(name)
    end

    def initialize(@name : String, @node_id : UInt64 = 1_u64)
      @host = name.sub(/^matter_/, "").tr("_", "-") + HOST_SUFFIX
      @storage_dir = File.join(STORAGE_ROOT, name)
      Dir.mkdir_p(@storage_dir)
    end

    def node : String
      node_id.to_s
    end

    def log_path : String
      File.join(LOG_DIR, "#{name}.log")
    end

    def log : String
      File.exists?(log_path) ? File.read(log_path) : ""
    end

    # Manual pairing code printed by the example on startup, e.g. "3497-011-2332".
    def pairing_code : String
      deadline = Time.instant + PAIRING_CODE_TIMEOUT
      loop do
        if m = log.match(/chip-tool pairing code 1 (\d{4}-\d{3}-\d{4}|\d{11})/)
          return m[1]
        end
        if Time.instant > deadline
          raise CommissioningError.new("#{name}: no pairing code found in #{log_path} after #{PAIRING_CODE_TIMEOUT.total_seconds.to_i}s\n#{log.lines.last(30).join("\n")}")
        end
        sleep 0.5.seconds
      end
    end

    # The device container's address (chip-tool only speaks IPv6).
    def address(family : Socket::Family = Socket::Family::INET6) : String
      Socket::Addrinfo.udp(host, DEVICE_PORT, family: family).first.ip_address.address
    end

    def commissioned? : Bool
      @commissioned
    end

    # Commissions the device once; subsequent calls are no-ops. A failure is
    # remembered so later specs fail fast instead of timing out again.
    def commission! : Nil
      return if @commissioned
      if error = @commissioning_error
        raise error
      end

      code = pairing_code
      args = case PAIRING
             when "address"
               _discriminator, pin = Matter::SetupPayload.parse_manual_code(code)
               ["pairing", "already-discovered", node, pin.to_s, address, DEVICE_PORT.to_s]
             else
               ["pairing", "code", node, code]
             end

      result = E2E.run(args, storage_dir)
      unless result.success? && result.output.includes?("Device commissioning completed with success")
        error = CommissioningError.new("#{name}: commissioning failed\n#{result}")
        @commissioning_error = error
        raise error
      end
      @commissioned = true
    rescue ex : CommissioningError
      @commissioning_error ||= ex
      raise ex
    end

    # Runs an arbitrary chip-tool command against the (commissioned) device.
    def chip(args : Array(String), timeout : Time::Span = COMMAND_TIMEOUT) : Result
      commission!
      E2E.run(args, storage_dir, timeout: timeout)
    end

    def chip(*args : String, timeout : Time::Span = COMMAND_TIMEOUT) : Result
      chip(args.to_a, timeout: timeout)
    end

    def read(cluster : String, attribute : String, endpoint : Int = 1) : Result
      chip([cluster, "read", attribute, node, endpoint.to_s])
    end

    def write(cluster : String, attribute : String, value : String | Int, endpoint : Int = 1, options : Array(String) = [] of String) : Result
      chip([cluster, "write", attribute, value.to_s, node, endpoint.to_s] + options)
    end

    # `invoke("onoff", "toggle")` or `invoke("levelcontrol", "move-to-level", ["128", "0", "0", "0"])`
    def invoke(cluster : String, command : String, args : Array(String) = [] of String, endpoint : Int = 1, options : Array(String) = [] of String) : Result
      chip([cluster, command] + args + [node, endpoint.to_s] + options)
    end
  end
end

# `value.should be_in(1..10)`
struct BeInExpectation(T)
  def initialize(@range : T)
  end

  def match(actual) : Bool
    @range.includes?(actual)
  end

  def failure_message(actual) : String
    "Expected: #{actual.inspect} to be in #{@range.inspect}"
  end

  def negative_failure_message(actual) : String
    "Expected: #{actual.inspect} not to be in #{@range.inspect}"
  end
end

def be_in(range)
  BeInExpectation.new(range)
end

# Fails the current spec with the full chip-tool transcript unless the command succeeded.
def expect_success(result : E2E::Result, file = __FILE__, line = __LINE__) : E2E::Result
  unless result.success?
    fail("#{result.command} failed (exit #{result.exit_code}, status #{result.im_status || "?"})\n#{result.tail}", file, line)
  end
  result
end

# Fails unless the command was rejected by the device with the given IM status.
def expect_failure(result : E2E::Result, status : String, file = __FILE__, line = __LINE__) : E2E::Result
  if result.success? || result.im_status != status
    fail("expected #{result.command} to fail with #{status}, got exit #{result.exit_code} status #{result.im_status || "?"}\n#{result.tail}", file, line)
  end
  result
end

# Reads an attribute and returns the printed value, failing with the transcript when absent.
def read_value(device : E2E::Device, cluster : String, attribute : String, name : String, endpoint : Int = 1, file = __FILE__, line = __LINE__) : String
  result = expect_success(device.read(cluster, attribute, endpoint), file, line)
  result.value(name) || fail("#{result.command}: no `#{name}:` value in output\n#{result.tail}", file, line)
end

def read_int(device : E2E::Device, cluster : String, attribute : String, name : String, endpoint : Int = 1, file = __FILE__, line = __LINE__) : Int64
  value = read_value(device, cluster, attribute, name, endpoint, file, line)
  value.split(/\s+/).first.to_i64? || fail("#{cluster} #{attribute}: `#{value}` is not an integer", file, line)
end

def read_bool(device : E2E::Device, cluster : String, attribute : String, name : String, endpoint : Int = 1, file = __FILE__, line = __LINE__) : Bool
  case read_value(device, cluster, attribute, name, endpoint, file, line).upcase
  when "TRUE"  then true
  when "FALSE" then false
  else              fail("#{cluster} #{attribute}: expected TRUE/FALSE", file, line)
  end
end
