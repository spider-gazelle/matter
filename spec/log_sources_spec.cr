require "./spec_helper"

# Every `Log = ::Log.for("...")` source in `src/` mirrors the file tree so a log
# line can be traced straight back to the file that emitted it:
#
#   src/matter/<dir>/<file>.cr          -> matter.<dir>.<file>
#   src/matter/<dir>/<file>_cluster.cr  -> matter.<dir>.<file>
#   src/matter/<dir>/<dir>.cr           -> matter.<dir>   (namespace file)
#   src/matter/<dir>.cr                 -> matter.<dir>   (namespace aggregator)
#
# Files that do not define `Log` fall back to the nearest namespace logger.
describe "log sources" do
  source_root = File.expand_path("../src", __DIR__)
  source_pattern = /::Log\.for\("(?<source>[^"]+)"\)/
  cluster_suffix = "_cluster"
  extension = ".cr"

  # Sources that intentionally extend the path-derived name.
  allowlist = {
    "matter/session/case/case.cr" => ["matter.session.case.initiator", "matter.session.case.responder"],
  }

  expected_source = ->(relative_path : String) do
    segments = relative_path.rchop(extension).split('/')
    segments[-1] = segments[-1].rchop(cluster_suffix)
    segments.pop if segments.size > 1 && segments[-1] == segments[-2]
    segments.join('.')
  end

  files = Dir.glob(File.join(source_root, "**", "*#{extension}")).sort
  files_with_sources = files.select { |file| File.read(file).matches?(source_pattern) }

  it "finds log sources to check" do
    files_with_sources.should_not be_empty
  end

  files_with_sources.each do |file|
    relative_path = Path[file].relative_to(source_root).to_s
    sources = File.read(file).scan(source_pattern).map(&.["source"])
    allowed = allowlist[relative_path]? || [expected_source.call(relative_path)]

    it "#{relative_path} logs as #{allowed.join(" / ")}" do
      sources.should eq(allowed)
    end
  end

  it "does not reuse a source across files" do
    all_sources = files_with_sources.flat_map { |file| File.read(file).scan(source_pattern).map(&.["source"]) }
    all_sources.tally.select { |_, count| count > 1 }.keys.should be_empty
  end
end
