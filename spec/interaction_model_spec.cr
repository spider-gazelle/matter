require "./spec_helper"
require "../src/matter/interaction_model/status_code"
require "../src/matter/interaction_model/paths"
require "../src/matter/interaction_model/messages"

describe Matter::InteractionModel do
  describe "StatusCode" do
    it "creates success status" do
      status = Matter::InteractionModel::StatusCode::Success
      status.success?.should be_true
      status.to_s.should eq("Success")
    end

    it "creates error statuses" do
      status = Matter::InteractionModel::StatusCode::UnsupportedAttribute
      status.success?.should be_false
      status.to_s.should eq("Unsupported Attribute")
    end

    it "creates Status with code" do
      status = Matter::InteractionModel::Status.new(
        Matter::InteractionModel::StatusCode::Success
      )
      status.success?.should be_true
      status.to_s.should eq("Success")
    end

    it "creates Status with cluster-specific code" do
      status = Matter::InteractionModel::Status.new(
        Matter::InteractionModel::StatusCode::Failure,
        cluster_status: 0x42_u8
      )
      status.success?.should be_false
      status.to_s.should eq("Failure (cluster: 0x42)")
    end
  end

  describe "AttributePath" do
    it "creates concrete attribute path" do
      path = Matter::InteractionModel::AttributePath.new(
        endpoint: 1_u16,
        cluster: 0x0006_u32,
        attribute: 0x0000_u32
      )

      path.endpoint.should eq(1_u16)
      path.cluster.should eq(0x0006_u32)
      path.attribute.should eq(0x0000_u32)
      path.concrete?.should be_true
      path.wildcard?.should be_false
    end

    it "creates wildcard attribute path" do
      path = Matter::InteractionModel::AttributePath.new(
        endpoint: 1_u16,
        cluster: 0x0006_u32
      )

      path.wildcard?.should be_true
      path.concrete?.should be_false
    end

    it "formats attribute path as string" do
      path = Matter::InteractionModel::AttributePath.new(
        endpoint: 1_u16,
        cluster: 0x0006_u32,
        attribute: 0x0000_u32
      )

      path.to_s.should eq("E:1/C:0x6/A:0x0")
    end

    it "supports list index in path" do
      path = Matter::InteractionModel::AttributePath.new(
        endpoint: 1_u16,
        cluster: 0x0006_u32,
        attribute: 0x0001_u32,
        list_index: 5_u16
      )

      path.list_index.should eq(5_u16)
      path.to_s.should contain("[5]")
    end

    it "compares attribute paths" do
      path1 = Matter::InteractionModel::AttributePath.new(
        endpoint: 1_u16,
        cluster: 0x0006_u32,
        attribute: 0x0000_u32
      )

      path2 = Matter::InteractionModel::AttributePath.new(
        endpoint: 1_u16,
        cluster: 0x0006_u32,
        attribute: 0x0000_u32
      )

      path3 = Matter::InteractionModel::AttributePath.new(
        endpoint: 2_u16,
        cluster: 0x0006_u32,
        attribute: 0x0000_u32
      )

      path1.should eq(path2)
      path1.should_not eq(path3)
    end
  end

  describe "CommandPath" do
    it "creates command path" do
      path = Matter::InteractionModel::CommandPath.new(
        endpoint: 1_u16,
        cluster: 0x0006_u32,
        command: 0x0001_u32
      )

      path.endpoint.should eq(1_u16)
      path.cluster.should eq(0x0006_u32)
      path.command.should eq(0x0001_u32)
      path.to_s.should eq("E:1/C:0x6/Cmd:0x1")
    end

    it "compares command paths" do
      path1 = Matter::InteractionModel::CommandPath.new(1_u16, 0x0006_u32, 0x0001_u32)
      path2 = Matter::InteractionModel::CommandPath.new(1_u16, 0x0006_u32, 0x0001_u32)
      path3 = Matter::InteractionModel::CommandPath.new(1_u16, 0x0006_u32, 0x0002_u32)

      path1.should eq(path2)
      path1.should_not eq(path3)
    end
  end

  describe "EventPath" do
    it "creates event path" do
      path = Matter::InteractionModel::EventPath.new(
        endpoint: 1_u16,
        cluster: 0x0006_u32,
        event: 0x0000_u32,
        is_urgent: false
      )

      path.endpoint.should eq(1_u16)
      path.cluster.should eq(0x0006_u32)
      path.event.should eq(0x0000_u32)
      path.is_urgent?.should be_false
    end

    it "creates urgent event path" do
      path = Matter::InteractionModel::EventPath.new(
        endpoint: 1_u16,
        cluster: 0x0006_u32,
        event: 0x0001_u32,
        is_urgent: true
      )

      path.is_urgent?.should be_true
      path.to_s.should contain("(urgent)")
    end
  end

  describe "ConcreteAttributePath" do
    it "creates concrete path" do
      path = Matter::InteractionModel::ConcreteAttributePath.new(
        endpoint: 1_u16,
        cluster: 0x0006_u32,
        attribute: 0x0000_u32
      )

      path.endpoint.should eq(1_u16)
      path.cluster.should eq(0x0006_u32)
      path.attribute.should eq(0x0000_u32)
    end

    it "converts to AttributePath" do
      concrete = Matter::InteractionModel::ConcreteAttributePath.new(
        endpoint: 1_u16,
        cluster: 0x0006_u32,
        attribute: 0x0000_u32
      )

      path = concrete.to_path
      path.should be_a(Matter::InteractionModel::AttributePath)
      path.endpoint.should eq(1_u16)
      path.cluster.should eq(0x0006_u32)
      path.attribute.should eq(0x0000_u32)
    end
  end

  describe "ReadRequest" do
    it "creates read request for attributes" do
      path = Matter::InteractionModel::AttributePath.new(
        endpoint: 1_u16,
        cluster: 0x0006_u32,
        attribute: 0x0000_u32
      )

      request = Matter::InteractionModel::ReadRequest.new(
        attribute_requests: [path]
      )

      request.attribute_requests.size.should eq(1)
      request.attribute_requests.first.should eq(path)
      request.fabric_filtered?.should be_true
    end

    it "creates read request with data version filter" do
      path = Matter::InteractionModel::ConcreteAttributePath.new(
        endpoint: 1_u16,
        cluster: 0x0006_u32,
        attribute: 0x0000_u32
      )

      filters = {path => 123_u32}
      request = Matter::InteractionModel::ReadRequest.new(
        attribute_requests: [path.to_path],
        data_version_filters: filters
      )

      request.data_version_filters.should eq(filters)
    end
  end

  describe "AttributeData" do
    it "creates attribute data with value" do
      path = Matter::InteractionModel::AttributePath.new(
        endpoint: 1_u16,
        cluster: 0x0006_u32,
        attribute: 0x0000_u32
      )

      data = Matter::InteractionModel::AttributeData.new(
        path: path,
        data_version: 5_u32,
        value: Bytes.new(4, 0_u8)
      )

      data.path.should eq(path)
      data.data_version.should eq(5_u32)
      data.value.size.should eq(4)
    end
  end

  describe "AttributeStatus" do
    it "creates attribute status" do
      path = Matter::InteractionModel::AttributePath.new(
        endpoint: 1_u16,
        cluster: 0x0006_u32,
        attribute: 0x0000_u32
      )

      status = Matter::InteractionModel::AttributeStatus.new(
        path: path,
        status: Matter::InteractionModel::Status.new(
          Matter::InteractionModel::StatusCode::Success
        )
      )

      status.path.should eq(path)
      status.status.success?.should be_true
    end
  end

  describe "ReadResponse" do
    it "creates read response with attribute data" do
      path = Matter::InteractionModel::AttributePath.new(
        endpoint: 1_u16,
        cluster: 0x0006_u32,
        attribute: 0x0000_u32
      )

      data = Matter::InteractionModel::AttributeData.new(
        path: path,
        data_version: 1_u32,
        value: Bytes.new(4)
      )

      response = Matter::InteractionModel::ReadResponse.new(
        attribute_reports: [data]
      )

      response.attribute_reports.size.should eq(1)
      response.attribute_reports.first.should eq(data)
      response.more_chunks?.should be_false
    end
  end

  describe "WriteRequest" do
    it "creates write request" do
      path = Matter::InteractionModel::AttributePath.new(
        endpoint: 1_u16,
        cluster: 0x0006_u32,
        attribute: 0x0000_u32
      )

      write_req = Matter::InteractionModel::AttributeWriteRequest.new(
        path: path,
        value: Bytes.new(4, 1_u8)
      )

      request = Matter::InteractionModel::WriteRequest.new(
        write_requests: [write_req]
      )

      request.write_requests.size.should eq(1)
      request.timed_request?.should be_false
    end

    it "creates timed write request" do
      path = Matter::InteractionModel::AttributePath.new(
        endpoint: 1_u16,
        cluster: 0x0006_u32,
        attribute: 0x0000_u32
      )

      write_req = Matter::InteractionModel::AttributeWriteRequest.new(
        path: path,
        value: Bytes.new(4),
        data_version: 10_u32
      )

      request = Matter::InteractionModel::WriteRequest.new(
        write_requests: [write_req],
        timed_request: true
      )

      request.timed_request?.should be_true
      request.write_requests.first.data_version.should eq(10_u32)
    end
  end

  describe "InvokeRequest" do
    it "creates invoke request" do
      path = Matter::InteractionModel::CommandPath.new(
        endpoint: 1_u16,
        cluster: 0x0006_u32,
        command: 0x0001_u32
      )

      command_data = Matter::InteractionModel::CommandDataIB.new(
        path: path,
        fields: Bytes.new(8)
      )

      request = Matter::InteractionModel::InvokeRequest.new(
        invoke_requests: [command_data]
      )

      request.invoke_requests.size.should eq(1)
      request.invoke_requests.first.path.should eq(path)
    end
  end

  describe "SubscribeRequest" do
    it "creates subscribe request" do
      attr_path = Matter::InteractionModel::AttributePath.new(
        endpoint: 1_u16,
        cluster: 0x0006_u32,
        attribute: 0x0000_u32
      )

      request = Matter::InteractionModel::SubscribeRequest.new(
        attribute_requests: [attr_path],
        min_interval_floor: 1_u16,
        max_interval_ceiling: 60_u16
      )

      request.attribute_requests.size.should eq(1)
      request.min_interval_floor.should eq(1_u16)
      request.max_interval_ceiling.should eq(60_u16)
      request.keep_subscriptions?.should be_false
    end
  end

  describe "SubscribeResponse" do
    it "creates subscribe response" do
      response = Matter::InteractionModel::SubscribeResponse.new(
        subscription_id: 1234_u32,
        min_interval: 1_u16,
        max_interval: 60_u16
      )

      response.subscription_id.should eq(1234_u32)
      response.min_interval.should eq(1_u16)
      response.max_interval.should eq(60_u16)
    end
  end

  describe "ReportData" do
    it "creates report data for subscription" do
      path = Matter::InteractionModel::AttributePath.new(
        endpoint: 1_u16,
        cluster: 0x0006_u32,
        attribute: 0x0000_u32
      )

      data = Matter::InteractionModel::AttributeData.new(
        path: path,
        data_version: 2_u32,
        value: Bytes.new(4)
      )

      report = Matter::InteractionModel::ReportData.new(
        subscription_id: 1234_u32,
        attribute_reports: [data]
      )

      report.subscription_id.should eq(1234_u32)
      report.attribute_reports.size.should eq(1)
      report.more_chunks?.should be_false
    end
  end

  describe "EventData" do
    it "creates event data" do
      path = Matter::InteractionModel::EventPath.new(
        endpoint: 1_u16,
        cluster: 0x0006_u32,
        event: 0x0000_u32
      )

      event = Matter::InteractionModel::EventData.new(
        path: path,
        event_number: 100_u64,
        priority: Matter::InteractionModel::EventPriority::Info,
        timestamp: 1234567890_u64,
        data: Bytes.new(16)
      )

      event.path.should eq(path)
      event.event_number.should eq(100_u64)
      event.priority.should eq(Matter::InteractionModel::EventPriority::Info)
    end
  end
end
