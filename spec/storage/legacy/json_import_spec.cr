require "../../spec_helper"
require "../../../src/matter/storage/legacy"

module LegacyImportSpec
  include Matter::Storage

  FIXTURE = File.join(__DIR__, "..", "..", "fixtures", "legacy_storage.json")

  # Synthetic byte material used by the fixture: `size` consecutive bytes from `start`.
  def self.run(start : Int, size : Int) : Bytes
    Bytes.new(size) { |i| ((start + i) & 0xFF).to_u8 }
  end

  def self.key(start : Int, size : Int) : Bytes
    prefix = Bytes[0x04]
    result = Bytes.new(prefix.size + size)
    prefix.copy_to(result)
    run(start, size).copy_to(result + prefix.size)
    result
  end

  def self.with_temp_dir(& : String ->) : Nil
    directory = File.join(Dir.tempdir, "matter-legacy-spec-#{Random::Secure.hex(6)}")
    Dir.mkdir_p(directory)
    begin
      yield directory
    ensure
      FileUtils.rm_rf(directory)
    end
  end

  # Warnings logged by the most recent `import`. The legacy logger is redirected
  # to memory while importing so spec output stays clean.
  class_getter warnings = [] of String

  # Runs the block with the legacy logger captured into `warnings`.
  def self.quietly(& : -> T) : T forall T
    log = Matter::Storage::Legacy::Log
    captured = ::Log::MemoryBackend.new
    previous_backend = log.backend
    previous_level = log.level
    log.backend = captured
    log.level = ::Log::Severity::Warn
    begin
      yield
    ensure
      log.backend = previous_backend
      log.level = previous_level
      @@warnings = captured.entries.map(&.message)
    end
  end

  def self.import(path : String = FIXTURE) : Memory
    quietly do
      source = Legacy::JsonImport.new(path)
      source.open
      memory = Memory.new
      Migrator.copy(source, memory)
      source.close
      memory
    end
  end

  # The fixture imported once, lazily so it runs after the suite's log setup.
  @@store : Memory?

  def self.store : Memory
    @@store ||= import
  end

  def self.import_json(directory : String, content : String) : Memory
    path = File.join(directory, "legacy.json")
    File.write(path, content)
    import(path)
  end

  def self.doc(store : Backend, collection : String, id : String) : Document
    store.read(collection, id) || raise "missing #{collection}/#{id}"
  end

  def self.fixture(collection : String, id : String) : Document
    doc(store, collection, id)
  end

  def self.array(value : Type) : Array(Type)
    value.as(Array(Type))
  end

  def self.hash(value : Type) : Document
    value.as(Document)
  end

  # An `Array(Type)` literal usable as a `Document` value.
  def self.list(*values : Type) : Type
    values.map(&.as(Type)).to_a
  end
end

describe Matter::Storage::Legacy::JsonImport do
  describe "the fixture" do
    it "produces every collection" do
      LegacyImportSpec.store.collections.should eq([
        Matter::Storage::Collections::APP, Matter::Storage::Collections::CLUSTERS, Matter::Storage::Collections::DEVICE, Matter::Storage::Collections::FABRICS,
        Matter::Storage::Collections::META, Matter::Storage::Collections::SESSIONS, Matter::Storage::Collections::SUBSCRIPTIONS,
      ])
    end

    it "imports a fabric whose id exceeds Int64::MAX" do
      LegacyImportSpec.store.ids(Matter::Storage::Collections::FABRICS).should eq(["1", "2"])
      fabric = LegacyImportSpec.fixture(Matter::Storage::Collections::FABRICS, "1")

      fabric["fabric_index"].should eq(1_i64)
      fabric["fabric_id"].should be_a(UInt64)
      fabric["fabric_id"].should eq(14250677199893128768_u64)
      fabric["node_id"].should eq(5000000001_i64)
      fabric["vendor_id"].should eq(65521_i64)
      fabric["label"].should eq("Home")
      fabric["root_public_key"].should eq(LegacyImportSpec.key(0x00, 64))
      fabric["operational_cert"].should eq(LegacyImportSpec.run(0x30, 40))
      fabric["operational_private_key"].should eq(LegacyImportSpec.run(0x50, 32))
      fabric["operational_public_key"].should eq(LegacyImportSpec.key(0x80, 64))
      fabric["ipk"].should eq(LegacyImportSpec.run(0x10, 16))
      fabric["root_cert"].should eq(LegacyImportSpec.run(0x70, 24))
      fabric.has_key?("intermediate_cert").should be_false
      fabric.has_key?("operational_key").should be_false
      fabric["cats"].should eq([0x1234abcd_i64, 1_i64])
      fabric["created_at"].should eq(Time.unix(1757462400))
      fabric["last_used_at"].should eq(Time.unix(1757466000))
      fabric["created_at"].as(Time).location.should eq(Time::Location::UTC)
      fabric.keys.sort!.should eq(%w[cats created_at fabric_id fabric_index ipk label last_used_at node_id operational_cert operational_private_key operational_public_key root_cert root_public_key vendor_id])
    end

    it "imports a fabric with a small id, no certs and no CATs" do
      fabric = LegacyImportSpec.fixture(Matter::Storage::Collections::FABRICS, "2")
      fabric["fabric_id"].should be_a(Int64)
      fabric["fabric_id"].should eq(4660_i64)
      fabric["label"].should eq("")
      fabric["cats"].should eq([] of Matter::Storage::Type)
      fabric.has_key?("root_cert").should be_false
      fabric.has_key?("intermediate_cert").should be_false
    end

    it "imports a session with every optional field" do
      LegacyImportSpec.store.ids(Matter::Storage::Collections::SESSIONS).should eq(["100", "101"])
      session = LegacyImportSpec.fixture(Matter::Storage::Collections::SESSIONS, "100")

      session["session_id"].should eq(100_i64)
      session["peer_session_id"].should eq(200_i64)
      session["session_type"].should eq(Matter::Session::SessionType::Unicast.to_s)
      session["encryption_key"].should eq(LegacyImportSpec.run(0x01, 16))
      session["decryption_key"].should eq(LegacyImportSpec.run(0x21, 16))
      session["initiator"].should be_false
      session["case_session"].should be_true
      session["local_message_counter"].should eq(123456_i64)
      session["peer_message_counter"].should eq(654321_i64)
      session["peer_node_id"].should eq(112233_i64)
      session["local_node_id"].should eq(5000000001_i64)
      session["attestation_challenge"].should eq(LegacyImportSpec.run(0x41, 16))
      session["fabric_index"].should eq(1_i64)
      session["created_at"].should eq(Time.unix(1757462500))
      session["last_activity_at"].should eq(Time.unix(1757466100))
      session.keys.sort!.should eq(%w[attestation_challenge case_session created_at decryption_key encryption_key fabric_index initiator last_activity_at local_message_counter local_node_id peer_message_counter peer_node_id peer_session_id session_id session_type])
    end

    it "omits optional session fields that were absent or flagged off" do
      session = LegacyImportSpec.fixture(Matter::Storage::Collections::SESSIONS, "101")
      session["session_type"].should eq(Matter::Session::SessionType::Unsecured.to_s)
      session["initiator"].should be_true
      session["case_session"].should be_false
      session["local_message_counter"].should eq(99_i64)
      session.keys.sort!.should eq(%w[case_session created_at decryption_key encryption_key initiator last_activity_at local_message_counter peer_session_id session_id session_type])
    end

    it "imports subscriptions, accepting the legacy next_exchange_id key" do
      LegacyImportSpec.store.ids(Matter::Storage::Collections::SUBSCRIPTIONS).should eq(["1", "3"])
      wildcard = LegacyImportSpec.fixture(Matter::Storage::Collections::SUBSCRIPTIONS, "1")

      wildcard["subscription_id"].should eq(1_i64)
      wildcard["min_interval"].should eq(0_i64)
      wildcard["max_interval"].should eq(60_i64)
      wildcard["peer_address"].should eq("fe80::1")
      wildcard["peer_port"].should eq(5540_i64)
      wildcard["session_id"].should eq(100_i64)
      wildcard["exchange_id"].should eq(4097_i64)
      wildcard["last_report_at"].should eq(Time.unix(1757466200))
      wildcard["attribute_paths"].should eq([Matter::Storage::Document{"cluster" => 6_i64}])
      wildcard.has_key?("next_exchange_id").should be_false

      concrete = LegacyImportSpec.fixture(Matter::Storage::Collections::SUBSCRIPTIONS, "3")
      concrete["exchange_id"].should eq(12_i64)
      concrete["attribute_paths"].should eq([Matter::Storage::Document{"endpoint" => 1_i64, "cluster" => 8_i64, "attribute" => 0_i64}])
    end

    it "imports the device identity and counters" do
      LegacyImportSpec.store.ids(Matter::Storage::Collections::DEVICE).should eq(["counters", "identity"])
      LegacyImportSpec.fixture(Matter::Storage::Collections::DEVICE, "identity").should eq(Matter::Storage::Document{
        "commissioning_hostname" => "0123456789ABCDEF.local",
        "serial_number"          => "ABCDEF0123456789",
        "unique_id"              => "00112233445566778899aabbccddeeff",
      })
      LegacyImportSpec.fixture(Matter::Storage::Collections::DEVICE, "counters").should eq(Matter::Storage::Document{"next_subscription_id" => 4_i64})
    end

    it "keys cluster documents by endpoint and cluster id" do
      LegacyImportSpec.store.ids(Matter::Storage::Collections::CLUSTERS).should eq(%w[0-31 0-40 0-63 0-65 1-4 1-6 1-8 1-98 2-57])
    end

    it "copies simple cluster states, dropping nulls" do
      LegacyImportSpec.fixture(Matter::Storage::Collections::CLUSTERS, "0-40").should eq(Matter::Storage::Document{
        "node_label" => "Crystal Light", "location" => "AU", "local_config_disabled" => false, "data_version" => 3_i64,
      })
      LegacyImportSpec.fixture(Matter::Storage::Collections::CLUSTERS, "1-6").should eq(Matter::Storage::Document{
        "on_off" => true, "global_scene_control" => true, "on_time" => 0_i64, "off_wait_time" => 0_i64,
        "start_up_on_off" => 2_i64, "data_version" => 5_i64,
      })
      LegacyImportSpec.fixture(Matter::Storage::Collections::CLUSTERS, "2-57").should eq(Matter::Storage::Document{
        "node_label" => "Lamp", "reachable" => true, "data_version" => 1_i64,
      })

      level = LegacyImportSpec.fixture(Matter::Storage::Collections::CLUSTERS, "1-8")
      level["current_level"].should eq(128_i64)
      level["off_transition_time"].should eq(5_i64)
      level["default_move_rate"].should eq(50_i64)
      level.has_key?("on_level").should be_false
      level.has_key?("on_transition_time").should be_false
      level.has_key?("start_up_current_level").should be_false
      level.keys.size.should eq(12)
    end

    it "keeps group ids as string keys" do
      LegacyImportSpec.fixture(Matter::Storage::Collections::CLUSTERS, "1-4").should eq(Matter::Storage::Document{
        "groups"       => Matter::Storage::Document{"257" => "Kitchen", "258" => ""},
        "data_version" => 1_i64,
      })
    end

    it "converts access control extension data to bytes and keeps enum values numeric" do
      acl = LegacyImportSpec.fixture(Matter::Storage::Collections::CLUSTERS, "0-31")
      acl["data_version"].should eq(2_i64)

      entries = LegacyImportSpec.array(acl["acl"])
      entries.size.should eq(2)
      LegacyImportSpec.hash(entries[0]).should eq(Matter::Storage::Document{
        "privilege" => 5_i64, "auth_mode" => 2_i64, "subjects" => LegacyImportSpec.list(112233_i64), "fabric_index" => 1_i64,
      })
      second = LegacyImportSpec.hash(entries[1])
      second["subjects"].should eq([445566_i64, UInt64::MAX])
      second["targets"].should eq([Matter::Storage::Document{"cluster" => 6_i64, "endpoint" => 1_i64}])

      acl["extension"].should eq([Matter::Storage::Document{"data" => Bytes[0x15, 0x36, 0x01, 0x18], "fabric_index" => 1_i64}])
    end

    it "converts group key management epoch keys to bytes" do
      gkm = LegacyImportSpec.fixture(Matter::Storage::Collections::CLUSTERS, "0-63")
      gkm["data_version"].should eq(1_i64)
      key_sets = LegacyImportSpec.hash(gkm["key_sets"])
      key_sets.keys.should eq(["1"])
      key_set = LegacyImportSpec.hash(LegacyImportSpec.array(key_sets["1"])[0])
      key_set.should eq(Matter::Storage::Document{
        "group_key_set_id"           => 1_i64,
        "group_key_security_policy"  => 0_i64,
        "epoch_key0"                 => LegacyImportSpec.run(0xD0, 16),
        "epoch_start_time0"          => 1757462400000000_i64,
        "epoch_key1"                 => LegacyImportSpec.run(0xE0, 16),
        "epoch_start_time1"          => 1757466000000000_i64,
        "group_key_multicast_policy" => 0_i64,
      })
      gkm["group_key_map"].should eq([Matter::Storage::Document{"group_id" => 257_i64, "group_key_set_id" => 1_i64, "fabric_index" => 1_i64}])
      gkm["group_table"].should eq([Matter::Storage::Document{"group_id" => 257_i64, "endpoints" => LegacyImportSpec.list(1_i64), "group_name" => "Kitchen", "fabric_index" => 1_i64}])
    end

    it "flattens scenes and their extension field sets" do
      scenes = LegacyImportSpec.fixture(Matter::Storage::Collections::CLUSTERS, "1-98")
      scenes["data_version"].should eq(2_i64)
      scenes["fabric_scene_info"].should eq(Matter::Storage::Document{
        "1" => Matter::Storage::Document{
          "scene_count" => 1_i64, "current_scene" => 1_i64, "current_group" => 257_i64,
          "scene_valid" => true, "remaining_capacity" => 15_i64, "fabric_index" => 1_i64,
        },
      })
      scenes["scenes"].should eq([
        Matter::Storage::Document{
          "fabric_index"         => 1_i64,
          "group_id"             => 257_i64,
          "scene_id"             => 1_i64,
          "transition_time"      => 1000_i64,
          "scene_name"           => "Evening",
          "extension_field_sets" => LegacyImportSpec.list(
            Matter::Storage::Document{"cluster_id" => 6_i64, "attributes" => LegacyImportSpec.list(Matter::Storage::Document{"attribute_id" => 0_i64, "value" => Bytes[0x09, 0x01]})},
            Matter::Storage::Document{"cluster_id" => 8_i64, "attributes" => LegacyImportSpec.list(
              Matter::Storage::Document{"attribute_id" => 0_i64, "value" => Bytes[0x04, 0x80]},
              Matter::Storage::Document{"attribute_id" => 17_i64, "value" => Bytes[0x04, 0x00]},
            )},
          ),
        },
      ])
    end

    it "wraps the user label array in a document" do
      LegacyImportSpec.fixture(Matter::Storage::Collections::CLUSTERS, "0-65").should eq(Matter::Storage::Document{
        "labels" => LegacyImportSpec.list(
          Matter::Storage::Document{"label" => "room", "value" => "kitchen"},
          Matter::Storage::Document{"label" => "floor", "value" => "1"},
        ),
        "data_version" => 0_i64,
      })
    end

    it "imports the bridge document and preserves unknown keys under app" do
      LegacyImportSpec.store.ids(Matter::Storage::Collections::APP).should eq(%w[bridged_devices legacy-custom-blob legacy-custom-note])
      LegacyImportSpec.fixture(Matter::Storage::Collections::APP, "bridged_devices").should eq(Matter::Storage::Document{
        "devices"        => LegacyImportSpec.list(Matter::Storage::Document{"endpoint_id" => 2_i64, "name" => "Lamp", "unique_id" => "lamp-0001"}),
        "device_counter" => 1_i64,
      })
      LegacyImportSpec.fixture(Matter::Storage::Collections::APP, "legacy-custom-note").should eq(Matter::Storage::Document{"value" => "kept verbatim"})
      LegacyImportSpec.fixture(Matter::Storage::Collections::APP, "legacy-custom-blob").should eq(Matter::Storage::Document{"value" => Bytes[1, 2, 3]})
    end

    it "warns once per unknown entry and about nothing else" do
      LegacyImportSpec.import.should_not be_nil
      LegacyImportSpec.warnings.should eq([
        "Legacy storage entry custom/note is not recognised; keeping it as app/legacy-custom-note",
        "Legacy storage entry custom/blob is not recognised; keeping it as app/legacy-custom-blob",
      ])
    end

    it "survives a YAML round trip unchanged" do
      LegacyImportSpec.with_temp_dir do |directory|
        path = File.join(directory, "store.yml")
        yaml = Matter::Storage::Migrator.open("yaml:#{path}")
        Matter::Storage::Migrator.copy(LegacyImportSpec.store, yaml)
        yaml.close

        reopened = Matter::Storage::Migrator.open("yaml:#{path}")
        reopened.collections.should eq(LegacyImportSpec.store.collections)
        LegacyImportSpec.store.collections.each do |collection|
          reopened.all(collection).should eq(LegacyImportSpec.store.all(collection))
        end
        reopened.close
      end
    end
  end

  describe "resilience" do
    it "skips an inner document that is not valid JSON and keeps the rest" do
      LegacyImportSpec.with_temp_dir do |directory|
        store = LegacyImportSpec.import_json(directory, {
          "cluster_state" => {
            "endpoint_0_cluster_40" => "{not json",
            "endpoint_1_cluster_6"  => {"on_off" => true, "data_version" => 1}.to_json,
          },
        }.to_json)

        store.ids(Matter::Storage::Collections::CLUSTERS).should eq(["1-6"])
        store.collections.should eq([Matter::Storage::Collections::CLUSTERS, Matter::Storage::Collections::META])
        LegacyImportSpec.warnings.should eq(["Skipping legacy clusters/0-40: JSON::ParseException while converting"])
      end
    end

    it "skips a fabric missing required fields without losing its neighbours" do
      LegacyImportSpec.with_temp_dir do |directory|
        table = {
          "1" => {"fabric_index" => 1, "label" => "incomplete", "ipk" => "c2VjcmV0"},
          "2" => {
            "fabric_id" => 2, "fabric_index" => 2, "node_id" => 3, "vendor_id" => 4, "label" => "ok",
            "root_public_key" => "AQ==", "operational_cert" => "AQ==", "operational_key" => "AQ==", "operational_public_key" => "AQ==", "ipk" => "AQ==",
            "intermediate_cert" => "", "root_cert" => "", "created_at" => 1, "last_used_at" => 1, "cats" => "",
          },
        }
        store = LegacyImportSpec.import_json(directory, {"fabrics" => {"fabric_table" => table.to_json}}.to_json)
        store.ids(Matter::Storage::Collections::FABRICS).should eq(["2"])
        LegacyImportSpec.warnings.should eq(["Skipping legacy fabrics/1: Matter::Storage::Legacy::ImportError while converting"])
      end
    end

    it "keeps unknown cluster ids and unknown contexts verbatim" do
      LegacyImportSpec.with_temp_dir do |directory|
        store = LegacyImportSpec.import_json(directory, {
          "cluster_state" => {"endpoint_3_cluster_1234" => %({"foo":1})},
          "protocol"      => {"next_subscription_id" => {"__type__" => "uint64", "value" => "18446744073709551615"}},
          "weird/ctx"     => "not an object",
        }.to_json)

        store.ids(Matter::Storage::Collections::APP).should eq(%w[legacy-cluster_state-endpoint_3_cluster_1234 legacy-weird_ctx])
        LegacyImportSpec.doc(store, Matter::Storage::Collections::APP, "legacy-cluster_state-endpoint_3_cluster_1234").should eq(Matter::Storage::Document{"value" => %({"foo":1})})
        LegacyImportSpec.doc(store, Matter::Storage::Collections::APP, "legacy-weird_ctx").should eq(Matter::Storage::Document{"value" => "not an object"})
        LegacyImportSpec.doc(store, Matter::Storage::Collections::DEVICE, "counters")["next_subscription_id"].should eq(UInt64::MAX)
        LegacyImportSpec.warnings.should eq([
          "Legacy storage entry cluster_state/endpoint_3_cluster_1234 is not recognised; keeping it as app/legacy-cluster_state-endpoint_3_cluster_1234",
          "Legacy storage entry weird/ctx is not recognised; keeping it as app/legacy-weird_ctx",
        ])
      end
    end

    it "rejects a missing file and a file that is not an object" do
      LegacyImportSpec.with_temp_dir do |directory|
        expect_raises(Matter::StorageError, /does not exist/) { Matter::Storage::Legacy::JsonImport.new(File.join(directory, "nope.json")).open }

        path = File.join(directory, "array.json")
        File.write(path, "[1, 2]")
        expect_raises(Matter::Storage::Legacy::ImportError, /JSON object/) { Matter::Storage::Legacy::JsonImport.new(path).open }
      end
    end
  end

  describe "as a backend" do
    it "is a read-only view" do
      source = Matter::Storage::Legacy::JsonImport.new(LegacyImportSpec::FIXTURE)
      source.open?.should be_false
      expect_raises(Matter::StorageError, /not open/) { source.collections }

      LegacyImportSpec.quietly { source.open }
      source.path.should eq(LegacyImportSpec::FIXTURE)
      source.read(Matter::Storage::Collections::FABRICS, "1").should_not be_nil
      source.read(Matter::Storage::Collections::FABRICS, "9").should be_nil
      source.ids(Matter::Storage::Collections::FABRICS).should eq(["1", "2"])
      source.all(Matter::Storage::Collections::DEVICE).keys.should eq(["counters", "identity"])
      source.ids("missing").should be_empty
      source.read(Matter::Storage::Collections::META, Matter::Storage::Collections::META_SCHEMA_ID).should eq(Matter::Storage::Backend.schema_document)

      yielded = false
      source.transaction { yielded = true }
      yielded.should be_true

      document = Matter::Storage::Document{"x" => 1_i64}
      expect_raises(Matter::StorageError, /read-only/) { source.write(Matter::Storage::Collections::APP, "x", document) }
      expect_raises(Matter::StorageError, /read-only/) { source.delete(Matter::Storage::Collections::APP, "x") }
      expect_raises(Matter::StorageError, /read-only/) { source.clear(Matter::Storage::Collections::APP) }
      expect_raises(Matter::StorageError, /read-only/) { source.clear_all }
      expect_raises(Matter::StorageError, /read-only/) { source.destroy! }

      source.close
      source.open?.should be_false
      File.exists?(LegacyImportSpec::FIXTURE).should be_true
    end

    it "opens through the legacy: URI scheme" do
      backend = LegacyImportSpec.quietly { Matter::Storage::Migrator.open("legacy:#{LegacyImportSpec::FIXTURE}") }
      backend.should be_a(Matter::Storage::Legacy::JsonImport)
      backend.open?.should be_true
      backend.close

      expect_raises(Matter::StorageError, /path/) { Matter::Storage::Migrator.open("legacy:") }
    end
  end
end
