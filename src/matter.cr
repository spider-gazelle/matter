require "mdns"
require "big"
require "tlv"
require "./matter/**"

module Matter
end

storage = Matter::Storage::MemoryBackend.new
storage_manager = Matter::Storage::Manager.new(storage)

server = Matter::Server.new(storage_manager)

context = storage_manager.create_context("one")
context.set("two", "three")
