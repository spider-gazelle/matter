require "../spec_helper"
require "../../src/matter/storage/json_file_backend"

describe Matter::Storage::JsonFileBackend do
  it "persists values across restarts" do
    path = File.tempname("matter-storage")
    File.delete(path) if File.exists?(path)

    begin
      storage = Matter::Storage::JsonFileBackend.new(path)
      storage.start
      storage.set(["context"], "key", "value")
      storage.set(["context"], "count", 42)
      storage.stop

      storage2 = Matter::Storage::JsonFileBackend.new(path)
      storage2.start
      storage2.get(["context"], "key").should eq("value")
      storage2.get(["context"], "count").should eq(42_i64)
      storage2.stop
    ensure
      File.delete(path) if File.exists?(path)
    end
  end

  it "persists byte slices" do
    path = File.tempname("matter-storage-bytes")
    File.delete(path) if File.exists?(path)

    begin
      bytes = Bytes[1, 2, 3, 4, 5]
      storage = Matter::Storage::JsonFileBackend.new(path)
      storage.start
      storage.set(["context"], "data", bytes)
      storage.stop

      storage2 = Matter::Storage::JsonFileBackend.new(path)
      storage2.start
      storage2.get(["context"], "data").should eq(bytes)
      storage2.stop
    ensure
      File.delete(path) if File.exists?(path)
    end
  end

  it "supports nested contexts and clear_all" do
    path = File.tempname("matter-storage-clear-all")
    File.delete(path) if File.exists?(path)

    begin
      storage = Matter::Storage::JsonFileBackend.new(path)
      storage.start
      storage.set(["context"], "key1", "value")
      storage.set(["context", "subcontext"], "key2", "value")
      storage.set(["context", "subcontext", "subsubcontext"], "key3", "value")

      storage.clear_all(["context", "subcontext"])

      storage.keys(["context"]).should eq(["key1"])
      storage.keys(["context", "subcontext"]).should eq([] of String)
      storage.keys(["context", "subcontext", "subsubcontext"]).should eq([] of String)
      storage.stop
    ensure
      File.delete(path) if File.exists?(path)
    end
  end

  it "returns a copy from values" do
    path = File.tempname("matter-storage-values")
    File.delete(path) if File.exists?(path)

    begin
      storage = Matter::Storage::JsonFileBackend.new(path)
      storage.start
      storage.set(["context"], "key", "value")

      values = storage.values(["context"])
      values["injected"] = "value"
      values.delete("key")

      storage.get(["context"], "key").should eq("value")
      storage.keys(["context"]).should eq(["key"])
      storage.stop
    ensure
      File.delete(path) if File.exists?(path)
    end
  end

  it "raises ArgumentError for keys and values on the root context" do
    storage = Matter::Storage::JsonFileBackend.new(File.tempname("matter-storage-root"))

    expect_raises(Matter::StorageError, "Context must not be empty!") do
      storage.keys([] of String)
    end

    expect_raises(Matter::StorageError, "Context must not be empty!") do
      storage.values([] of String)
    end

    expect_raises(Matter::StorageError, "Context must not be an empty string.") do
      storage.keys(["ok", ""])
    end
  end

  it "moves a corrupt file aside and starts empty" do
    path = File.tempname("matter-storage-corrupt")
    File.write(path, "{ this is not json")

    begin
      storage = Matter::Storage::JsonFileBackend.new(path)
      storage.start

      storage.keys(["context"]).should be_empty
      File.exists?(path).should be_false
      preserved = Dir.glob("#{path}.corrupt-*")
      preserved.size.should eq(1)
      File.read(preserved.first).should eq("{ this is not json")

      storage.set(["context"], "key", "value")
      storage.stop
      File.exists?(path).should be_true
    ensure
      Dir.glob("#{path}*").each { |file| File.delete(file) }
    end
  end

  it "lists root contexts" do
    storage = Matter::Storage::JsonFileBackend.new(File.tempname("matter-storage-contexts"))
    storage.set(["alpha", "child"], "key", "value")
    storage.set(["beta"], "key", "value")

    storage.contexts([] of String).should eq(["alpha", "beta"])
  end
end
