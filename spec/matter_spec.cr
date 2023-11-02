require "./spec_helper"

describe Matter do
  it "creates a memory backend storage with a context and stores a string" do
    storage = Matter::Storage::MemoryBackend.new
    storage_manager = Matter::Storage::Manager.new(storage)

    context = storage_manager.create_context("one")
    context.set("two", "three")
  end
end
