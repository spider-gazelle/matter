require "../../spec_helper"
require "../../../src/matter/storage/cli"
require "../../../src/matter/storage/legacy"

module LegacyCliSpec
  FIXTURE = File.join(__DIR__, "..", "..", "fixtures", "legacy_storage.json")

  def self.with_temp_dir(& : String ->) : Nil
    directory = File.join(Dir.tempdir, "matter-legacy-cli-spec-#{Random::Secure.hex(6)}")
    begin
      yield directory
    ensure
      FileUtils.rm_rf(directory)
    end
  end

  # Runs the CLI with the legacy importer's expected "unknown entry" warnings
  # silenced so spec output stays clean.
  def self.run(args : Array(String)) : {Int32, String, String}
    output = IO::Memory.new
    error = IO::Memory.new
    log = Matter::Storage::Legacy::Log
    previous_level = log.level
    log.level = ::Log::Severity::Error
    begin
      status = Matter::Storage::CLI.run(args, output, error)
    ensure
      log.level = previous_level
    end
    {status, output.to_s, error.to_s}
  end
end

describe Matter::Storage::CLI do
  it "migrates a legacy file into a YAML store" do
    LegacyCliSpec.with_temp_dir do |directory|
      target = File.join(directory, "store.yml")
      status, output, error = LegacyCliSpec.run(["migrate", "--from", "legacy:#{LegacyCliSpec::FIXTURE}", "--to", "yaml:#{target}"])

      status.should eq(Matter::Storage::CLI::EXIT_OK)
      error.should be_empty
      output.should contain("fabrics: 2 documents\n")
      output.should contain("sessions: 2 documents\n")
      output.should contain("subscriptions: 2 documents\n")
      output.should contain("clusters: 9 documents\n")
      output.should contain("device: 2 documents\n")
      output.should contain("app: 3 documents\n")
      output.should contain("Copied 20 documents")

      store = Matter::Storage::Migrator.open("yaml:#{target}")
      store.ids(Matter::Storage::Collections::FABRICS).should eq(["1", "2"])
      store.read(Matter::Storage::Collections::FABRICS, "1").as(Matter::Storage::Document)["fabric_id"].should eq(14250677199893128768_u64)
      store.close
    end
  end

  it "inspects a legacy file directly with secrets redacted" do
    status, output, error = LegacyCliSpec.run(["inspect", "legacy:#{LegacyCliSpec::FIXTURE}"])

    status.should eq(Matter::Storage::CLI::EXIT_OK)
    error.should be_empty
    output.should contain("fabrics (2)\n")
    output.should contain("    ipk: <bytes 16>\n")
    output.should contain("    key_sets: <redacted>\n")
    output.should contain("    session_type: \"Unicast\"\n")
    output.should_not contain(Base64.strict_encode(Bytes.new(16) { |i| (0x10 + i).to_u8 }))
  end

  it "reports a missing legacy file" do
    status, _, error = LegacyCliSpec.run(["migrate", "--from", "legacy:/nonexistent/legacy.json", "--to", "memory:"])
    status.should eq(Matter::Storage::CLI::EXIT_FAILURE)
    error.should contain("does not exist")
  end
end
