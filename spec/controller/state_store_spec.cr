require "../spec_helper"
require "../../src/matter/controller/state_store"

private def with_temp_file(& : String ->) : Nil
  path = File.join(Dir.tempdir, "matter-controller-#{Random::Secure.hex(6)}.yml")
  yield path
ensure
  File.delete?(path) if path
end

private def sample_fabric : Matter::Controller::FabricInfo
  Matter::Controller::FabricInfo.new(
    fabric_id: 0x1111_u64,
    controller_node_id: 0x2222_u64,
    ipk_value: Bytes.new(16, 0xAA_u8),
    root_cert: Bytes[0x15, 0x30, 0x01, 0x01],
    root_public_key: Bytes[0x04_u8] + Bytes.new(64, 0xBB_u8),
    controller_noc: Bytes[0x15, 0x30, 0x01, 0x02],
    controller_private_key: Bytes.new(32, 0xCC_u8),
    admin_vendor_id: 0xFFF1_u16
  )
end

describe Matter::Controller::StateStore do
  it "loads empty state when nothing is stored" do
    store = Matter::Controller::StateStore.new(Matter::Storage::Memory.new)
    state = store.load
    state.fabric.should be_nil
    state.nodes.should be_empty
    state.commissioner_node_id.should_not eq(0_u64)
    state.unsecured_message_counter.should eq(0_u32)
  end

  it "does not write a generated commissioner id until saved" do
    backend = Matter::Storage::Memory.new
    Matter::Controller::StateStore.new(backend).load
    backend.collections.should eq([Matter::Storage::Collections::META])
  end

  it "round-trips fabric and nodes through a YAML file" do
    with_temp_file do |path|
      store = Matter::Controller::StateStore.new(Matter::Storage::YamlFile.new(path))

      nodes = {
        0x1_u64 => Matter::Controller::NodeInfo.new(node_id: 0x1_u64, address: "192.168.1.10", port: 5540),
        0x2_u64 => Matter::Controller::NodeInfo.new(node_id: 0x2_u64, address: nil, port: 5540),
      }

      store.save(Matter::Controller::State.new(fabric: sample_fabric, nodes: nodes))
      store.backend.close

      loaded = Matter::Controller::StateStore.new(Matter::Storage::YamlFile.new(path)).load
      loaded.commissioner_node_id.should eq(0x2222_u64)
      loaded.unsecured_message_counter.should eq(0_u32)
      fabric = loaded.fabric.as(Matter::Controller::FabricInfo)
      fabric.fabric_id.should eq(0x1111_u64)
      fabric.controller_node_id.should eq(0x2222_u64)
      fabric.ipk_value.should eq(Bytes.new(16, 0xAA_u8))
      fabric.root_public_key.size.should eq(65)
      fabric.controller_private_key.should eq(Bytes.new(32, 0xCC_u8))

      loaded.nodes.size.should eq(2)
      loaded.nodes[0x1_u64].address.should eq("192.168.1.10")
      loaded.nodes[0x1_u64].port.should eq(5540)
      loaded.nodes[0x2_u64].address.should be_nil
    end
  end

  it "stores the state as the controller/state document" do
    backend = Matter::Storage::Memory.new
    store = Matter::Controller::StateStore.new(backend)
    store.save(Matter::Controller::State.new(fabric: sample_fabric, commissioner_node_id: 0x2222_u64, unsecured_message_counter: 9_u32))

    document = backend.read(Matter::Controller::StateStore::COLLECTION, Matter::Controller::StateStore::DOCUMENT_ID).as(Matter::Storage::Document)
    document["commissioner_node_id"].should eq(0x2222_i64)
    document["unsecured_message_counter"].should eq(9_i64)
    document["fabric"].as(Matter::Storage::Document)["ipk_value"].should eq(Bytes.new(16, 0xAA_u8))
    document["nodes"].should eq(Matter::Storage::Document.new)
  end

  it "aligns a stored commissioner id with the fabric and writes it back" do
    backend = Matter::Storage::Memory.new
    store = Matter::Controller::StateStore.new(backend)
    store.save(Matter::Controller::State.new(fabric: sample_fabric, commissioner_node_id: 0x9999_u64))

    store.load.commissioner_node_id.should eq(0x2222_u64)
    document = backend.read(Matter::Controller::StateStore::COLLECTION, Matter::Controller::StateStore::DOCUMENT_ID).as(Matter::Storage::Document)
    document["commissioner_node_id"].should eq(0x2222_i64)
  end

  it "wraps decode failures in a StorageError" do
    backend = Matter::Storage::Memory.new
    backend.write(Matter::Controller::StateStore::COLLECTION, Matter::Controller::StateStore::DOCUMENT_ID, Matter::Storage::Document{"nodes" => "bogus"})

    expect_raises(Matter::StorageError, /nodes/) do
      Matter::Controller::StateStore.new(backend).load
    end
  end
end
