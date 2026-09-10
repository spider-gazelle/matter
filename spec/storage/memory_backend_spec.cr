require "../spec_helper"
require "../../src/matter/storage/memory_backend"

# Tests ported from matter.js
# packages/general/test/storage/StorageBackendMemoryTest.ts

describe Matter::Storage::MemoryBackend do
  describe "basic operations" do
    it "write and read success" do
      storage = Matter::Storage::MemoryBackend.new

      storage.set(["context"], "key", "value")

      value = storage.get(["context"], "key")
      value.should eq("value")
    end

    it "multi-write and read success" do
      storage = Matter::Storage::MemoryBackend.new

      storage.set(["context"], "key", "value")
      storage.set(["context"], "key2", "value2")

      value = storage.get(["context"], "key")
      value.should eq("value")
      value2 = storage.get(["context"], "key2")
      value2.should eq("value2")
    end

    it "multi-write and values read" do
      storage = Matter::Storage::MemoryBackend.new

      storage.set(["context"], "key", "value")
      storage.set(["context"], "key2", "value2")

      values = storage.values(["context"])
      values.should eq({"key" => "value", "key2" => "value2"})
    end

    it "write and delete success" do
      storage = Matter::Storage::MemoryBackend.new

      storage.set(["context"], "key", "value")
      storage.delete(["context"], "key")

      value = storage.get(["context"], "key")
      value.should be_nil
    end
  end

  describe "multiple context levels" do
    it "write and read success with multiple context levels" do
      storage = Matter::Storage::MemoryBackend.new

      storage.set(["context", "subcontext", "subsubcontext"], "key", "value")

      value = storage.get(["context", "subcontext", "subsubcontext"], "key")
      value.should eq("value")
    end

    it "return keys with storage values" do
      storage = Matter::Storage::MemoryBackend.new

      storage.set(["context", "subcontext", "subsubcontext"], "key", "value")

      keys = storage.keys(["context", "subcontext", "subsubcontext"])
      keys.should eq(["key"])
    end

    it "return keys with storage without subcontexts values" do
      storage = Matter::Storage::MemoryBackend.new

      storage.set(["context", "subcontext"], "key", "value")
      storage.set(["context", "subcontext", "subsubcontext"], "key", "value")

      keys = storage.keys(["context", "subcontext"])
      keys.should eq(["key"])
    end

    it "clear all keys with multiple contexts" do
      storage = Matter::Storage::MemoryBackend.new

      storage.set(["context"], "key1", "value")
      storage.set(["context", "subcontext"], "key2", "value")
      storage.set(["context", "subcontext", "subsubcontext"], "key3", "value")

      storage.clear_all(["context", "subcontext"])

      storage.keys(["context"]).should eq(["key1"])
      storage.keys(["context", "subcontext"]).should eq([] of String)
      storage.keys(["context", "subcontext", "subsubcontext"]).should eq([] of String)
    end
  end

  describe "contexts method" do
    it "return all contexts with multiple contexts" do
      storage = Matter::Storage::MemoryBackend.new

      storage.set(["context"], "key1", "value")
      storage.set(["context", "subcontext"], "key2", "value")
      storage.set(["context", "subcontext2"], "key2", "value")
      storage.set(["context", "subcontext", "subsubcontext"], "key3", "value")

      storage.contexts(["context", "subcontext", "subsubcontext"]).should eq([] of String)
      storage.contexts(["context", "subcontext"]).should eq(["subsubcontext"])
      storage.contexts(["context"]).should eq(["subcontext", "subcontext2"])
      storage.contexts([] of String).should eq(["context"])
    end

    it "returns empty array for context without subcontexts" do
      storage = Matter::Storage::MemoryBackend.new

      storage.set(["context"], "key1", "value")

      storage.contexts(["context"]).should eq([] of String)
    end

    it "returns contexts for root level" do
      storage = Matter::Storage::MemoryBackend.new

      storage.set(["context1"], "key1", "value")
      storage.set(["context2"], "key2", "value")

      storage.contexts([] of String).should eq(["context1", "context2"])
    end
  end

  describe "error handling" do
    it "throws error when context is empty on set" do
      storage = Matter::Storage::MemoryBackend.new

      expect_raises(Matter::StorageError, "Context and key must not be empty!") do
        storage.set([] of String, "key", "value")
      end
    end

    it "throws error when context has empty string on set" do
      storage = Matter::Storage::MemoryBackend.new

      expect_raises(Matter::StorageError, "Context must not be an empty string.") do
        storage.set([""], "key", "value")
      end
    end

    it "throws error when key is empty on set" do
      storage = Matter::Storage::MemoryBackend.new

      expect_raises(Matter::StorageError, "Context and key must not be empty!") do
        storage.set(["context"], "", "value")
      end
    end

    it "throws error when context has empty string in subcontext on get" do
      storage = Matter::Storage::MemoryBackend.new

      expect_raises(Matter::StorageError, "Context must not be an empty string.") do
        storage.get(["ok", ""], "key")
      end
    end

    it "throws error when key is empty on get" do
      storage = Matter::Storage::MemoryBackend.new

      expect_raises(Matter::StorageError, "Context and key must not be empty!") do
        storage.get(["context", "subcontext"], "")
      end
    end
  end

  describe "complex data types" do
    it "stores and retrieves integers" do
      storage = Matter::Storage::MemoryBackend.new

      storage.set(["context"], "count", 42)
      storage.get(["context"], "count").should eq(42)
    end

    it "stores and retrieves arrays" do
      storage = Matter::Storage::MemoryBackend.new

      list = [1, 2, 3] of Matter::Storage::LegacyType
      storage.set(["context"], "list", list)
      storage.get(["context"], "list").should eq(list)
    end

    it "stores and retrieves hashes" do
      storage = Matter::Storage::MemoryBackend.new

      data = {"name" => "test", "value" => 123} of String => Matter::Storage::LegacyType
      storage.set(["context"], "config", data)
      storage.get(["context"], "config").should eq(data)
    end

    it "stores and retrieves byte slices" do
      storage = Matter::Storage::MemoryBackend.new

      bytes = Bytes[1, 2, 3, 4, 5]
      storage.set(["context"], "data", bytes)
      storage.get(["context"], "data").should eq(bytes)
    end
  end

  describe "clear operations" do
    it "clears all data with clear" do
      storage = Matter::Storage::MemoryBackend.new

      storage.set(["context1"], "key1", "value1")
      storage.set(["context2"], "key2", "value2")
      storage.set(["context3"], "key3", "value3")

      storage.clear

      storage.keys(["context1"]).should eq([] of String)
      storage.keys(["context2"]).should eq([] of String)
      storage.keys(["context3"]).should eq([] of String)
    end

    it "clear_all with empty contexts clears everything" do
      storage = Matter::Storage::MemoryBackend.new

      storage.set(["context1"], "key1", "value1")
      storage.set(["context2"], "key2", "value2")

      storage.clear_all([] of String)

      storage.keys(["context1"]).should eq([] of String)
      storage.keys(["context2"]).should eq([] of String)
    end
  end

  describe "initialization" do
    it "starts and stops correctly" do
      storage = Matter::Storage::MemoryBackend.new

      storage.initialized?.should be_true

      storage.stop
      storage.initialized?.should be_false

      storage.start
      storage.initialized?.should be_true
    end
  end

  describe "practical scenarios" do
    it "manages device configuration across contexts" do
      storage = Matter::Storage::MemoryBackend.new

      # Store device settings
      storage.set(["devices", "light1"], "brightness", 75)
      storage.set(["devices", "light1"], "on", true)
      storage.set(["devices", "light2"], "brightness", 50)
      storage.set(["devices", "light2"], "on", false)

      # Read back settings
      storage.get(["devices", "light1"], "brightness").should eq(75)
      storage.get(["devices", "light1"], "on").should be_true
      storage.get(["devices", "light2"], "brightness").should eq(50)
      storage.get(["devices", "light2"], "on").should be_false

      # List all devices
      storage.contexts(["devices"]).should eq(["light1", "light2"])
    end

    it "handles configuration updates and deletions" do
      storage = Matter::Storage::MemoryBackend.new

      # Initial configuration
      storage.set(["app", "config"], "theme", "dark")
      storage.set(["app", "config"], "language", "en")
      storage.set(["app", "config"], "version", "1.0")

      # Update single value
      storage.set(["app", "config"], "theme", "light")

      # Verify update
      values = storage.values(["app", "config"])
      values["theme"].should eq("light")
      values["language"].should eq("en")

      # Delete a key
      storage.delete(["app", "config"], "version")

      # Verify deletion
      storage.keys(["app", "config"]).should eq(["language", "theme"])
    end
  end

  describe "root context" do
    it "returns a copy from values" do
      storage = Matter::Storage::MemoryBackend.new
      storage.set(["context"], "key", "value")

      values = storage.values(["context"])
      values["injected"] = "value"
      values.delete("key")

      storage.get(["context"], "key").should eq("value")
      storage.keys(["context"]).should eq(["key"])
    end

    it "raises ArgumentError for keys and values on the root context" do
      storage = Matter::Storage::MemoryBackend.new

      expect_raises(Matter::StorageError, "Context must not be empty!") do
        storage.keys([] of String)
      end

      expect_raises(Matter::StorageError, "Context must not be empty!") do
        storage.values([] of String)
      end
    end

    it "raises ArgumentError for empty context segments" do
      storage = Matter::Storage::MemoryBackend.new

      expect_raises(Matter::StorageError, "Context must not be an empty string.") do
        storage.keys(["ok", ""])
      end
    end

    it "lists root contexts" do
      storage = Matter::Storage::MemoryBackend.new
      storage.set(["alpha", "child"], "key", "value")
      storage.set(["beta"], "key", "value")

      storage.contexts([] of String).should eq(["alpha", "beta"])
    end
  end

  describe "smoke" do
    it "stores and retrieves a string under a context" do
      storage = Matter::Storage::MemoryBackend.new
      storage.set(["one"], "two", "three")
      storage.get(["one"], "two").should eq "three"
    end
  end
end
