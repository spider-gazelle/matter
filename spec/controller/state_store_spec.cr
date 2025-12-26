require "../spec_helper"
require "../../src/matter/controller/state_store"
require "file_utils"

private def with_tmp_dir(prefix : String, & : String ->) : Nil
  dir = File.join(Dir.tempdir, "#{prefix}-#{Random::Secure.random_bytes(8).hexstring}")
  FileUtils.mkdir_p(dir)
  yield dir
ensure
  FileUtils.rm_r(dir) if dir && Dir.exists?(dir)
end

describe Matter::Controller::StateStore do
  it "loads empty state when file missing" do
    with_tmp_dir("matter-controller") do |dir|
      store = Matter::Controller::StateStore.new(dir)
      state = store.load
      state.fabric.should be_nil
      state.nodes.should be_empty
    end
  end

  it "round-trips fabric and nodes" do
    with_tmp_dir("matter-controller") do |dir|
      store = Matter::Controller::StateStore.new(dir)

      fabric = Matter::Controller::FabricInfo.new(
        fabric_id: 0x1111_u64,
        controller_node_id: 0x2222_u64,
        ipk_value_hex: Bytes.new(16, 0xAA_u8).hexstring,
        root_cert_hex: Bytes[0x15, 0x30, 0x01, 0x01].hexstring,
        root_public_key_hex: (Bytes[0x04_u8] + Bytes.new(64, 0xBB_u8)).hexstring,
        controller_noc_hex: Bytes[0x15, 0x30, 0x01, 0x02].hexstring,
        controller_private_key_hex: Bytes.new(32, 0xCC_u8).hexstring,
        admin_vendor_id: 0xFFF1_u16
      )

      nodes = {
        0x1_u64 => Matter::Controller::NodeInfo.new(node_id: 0x1_u64, address: "192.168.1.10", port: 5540),
        0x2_u64 => Matter::Controller::NodeInfo.new(node_id: 0x2_u64, address: nil, port: 5540),
      }

      state = Matter::Controller::State.new(fabric: fabric, nodes: nodes)
      store.save(state)

      loaded = store.load
      loaded.fabric.as(Matter::Controller::FabricInfo).fabric_id.should eq(0x1111_u64)
      loaded.fabric.as(Matter::Controller::FabricInfo).controller_node_id.should eq(0x2222_u64)
      loaded.fabric.as(Matter::Controller::FabricInfo).ipk_value.size.should eq(16)

      loaded.nodes.size.should eq(2)
      loaded.nodes[0x1_u64].address.should eq("192.168.1.10")
      loaded.nodes[0x1_u64].port.should eq(5540)
      loaded.nodes[0x2_u64].address.should be_nil
    end
  end
end
