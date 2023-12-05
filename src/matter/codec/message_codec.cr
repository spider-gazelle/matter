module Matter
  module Codec
    module MessageCodec
      HEADER_VERSION   = UInt8.new(0x00)
      COMMON_VENDOR_ID = UInt16.new(0x0000)

      enum SessionType : UInt8
        Unicast = 0
        Group   = 1
      end

      enum PacketHeaderFlag : UInt8
        HasDestNodeId   = 0b00000001
        HasDestGroupId  = 0b00000010
        HasSourceNodeId = 0b00000100
        Reserved        = 0b00001000
        VersionMask     = 0b11110000
      end

      enum PayloadHeaderFlag : UInt8
        IsInitiatorMessage = 0b00000001
        IsAckMessage       = 0b00000010
        RequiresAck        = 0b00000100
        HasSecureExtension = 0b00001000
        HasVendorId        = 0b00010000
      end

      enum SecurityFlag : UInt8
        HasPrivacyEnhancements = 0b10000000
        IsControlMessage       = 0b01000000
        HasMessageExtension    = 0b00100000
      end

      struct PacketHeader
        getter session_id : UInt16
        getter session_type : SessionType
        getter message_id : UInt32
        getter source_node_id : DataType::NodeId?
        getter destination_node_id : DataType::NodeId?
        getter destination_group_id : DataType::GroupId?
        getter? privacy_enhancements : Bool
        getter? control_message : Bool
        getter? message_extensions : Bool

        def initialize(@session_id : UInt16, @session_type : SessionType, @message_id : UInt32, @privacy_enhancements : Bool, @control_message : Bool, @message_extensions : Bool, @source_node_id : DataType::NodeId? = nil, @destination_node_id : DataType::NodeId? = nil, @destination_group_id : DataType::GroupId? = nil)
        end
      end

      struct PayloadHeader
        getter exchange_id : UInt16
        getter protocol_id : UInt16
        getter message_type : UInt8
        getter? initiator_message : Bool
        getter? requires_acknowledge : Bool
        getter acknowledged_message_id : UInt32?

        def initialize(@exchange_id : UInt16, @protocol_id : UInt16, @message_type : UInt8, @initiator_message : Bool, @requires_acknowledge : Bool, @acknowledged_message_id : UInt32? = nil)
        end
      end

      struct Packet
        getter header : PacketHeader
        getter payload : Slice(UInt8)

        def initialize(@header : PacketHeader, @payload : Slice(UInt8))
        end
      end

      struct Message
        getter packet_header : PacketHeader
        getter payload_header : PayloadHeader
        getter payload : Slice(UInt8)

        def initialize(@packet_header : PacketHeader, @payload_header : PayloadHeader, @payload : Slice(UInt8))
        end
      end

      module Base
        extend self

        def decode_packet(data : Slice(UInt8)) : Packet
          io = IO::Memory.new

          io.write(data)
          io.rewind
          header = decode_packet_header(io)

          Packet.new(header, io.getb_to_end)
        end

        def decode_payload(packet : Packet) : Message
          io = IO::Memory.new

          io.write(packet.payload)
          io.rewind
          header = decode_payload_header(io)

          Message.new(packet.header, header, io.getb_to_end)
        end

        def encode_payload(message : Message) : Packet
          io = IO::Memory.new
          header = encode_payload_header(message.payload_header, io)

          Packet.new(header: message.packet_header, payload: Slice.join([io.rewind.to_slice, message.payload]))
        end

        def encode_packet(packet : Packet) : Slice(UInt8)
          io = IO::Memory.new
          header = encode_packet_header(packet.header, io)

          Slice.join([io.rewind.to_slice, packet.payload])
        end

        private def encode_packet_header(packet_header : PacketHeader, io : IO::Memory, byte_format : IO::ByteFormat = IO::ByteFormat::LittleEndian)
          flags = (HEADER_VERSION << 4) | \
            (packet_header.destination_group_id.nil? ? 0 : PacketHeaderFlag::HasDestGroupId.value) | \
            (packet_header.destination_node_id.nil? ? 0 : PacketHeaderFlag::HasDestNodeId.value) | \
            (packet_header.source_node_id.nil? ? 0 : PacketHeaderFlag::HasSourceNodeId.value)

          security_flags = packet_header.session_type.value

          byte_format.encode(UInt8.new(flags), io)
          byte_format.encode(UInt16.new(packet_header.session_id), io)
          byte_format.encode(UInt8.new(security_flags), io)
          byte_format.encode(UInt32.new(packet_header.message_id), io)

          byte_format.encode(UInt64.new(packet_header.source_node_id.not_nil!.id), io) unless packet_header.source_node_id.nil?
          byte_format.encode(UInt64.new(packet_header.destination_node_id.not_nil!.id), io) unless packet_header.destination_node_id.nil?
          byte_format.encode(UInt32.new(packet_header.destination_group_id.not_nil!.id), io) unless packet_header.destination_group_id.nil?
        end

        private def encode_payload_header(payload_header : PayloadHeader, io : IO::Memory, byte_format : IO::ByteFormat = IO::ByteFormat::LittleEndian)
          vendor_id = (payload_header.protocol_id & 0xffff0000) >> 16

          flags = (payload_header.initiator_message? ? PayloadHeaderFlag::IsInitiatorMessage.value : 0) | \
            (payload_header.acknowledged_message_id.nil? ? 0 : PayloadHeaderFlag::IsAckMessage.value) | \
            (payload_header.requires_acknowledge? ? PayloadHeaderFlag::RequiresAck.value : 0) | \
            (vendor_id != COMMON_VENDOR_ID ? PayloadHeaderFlag::HasVendorId.value : 0)

          byte_format.encode(UInt8.new(flags), io)
          byte_format.encode(UInt8.new(payload_header.message_type), io)
          byte_format.encode(UInt16.new(payload_header.exchange_id), io)

          vendor_id != COMMON_VENDOR_ID ? byte_format.encode(UInt32.new(payload_header.protocol_id), io) : byte_format.encode(UInt16.new(payload_header.protocol_id), io)
          byte_format.encode(UInt32.new(payload_header.acknowledged_message_id.not_nil!), io) unless payload_header.acknowledged_message_id.nil?
        end

        private def decode_packet_header(io : IO::Memory, byte_format : IO::ByteFormat = IO::ByteFormat::LittleEndian) : PacketHeader
          flags = io.read_bytes(UInt8, byte_format)
          version = (flags & PacketHeaderFlag::VersionMask.value) >> 4

          has_destination_node_id = (flags & PacketHeaderFlag::HasDestNodeId.value) != 0
          has_destination_group_id = (flags & PacketHeaderFlag::HasDestGroupId.value) != 0
          has_source_node_id = (flags & PacketHeaderFlag::HasSourceNodeId.value) != 0

          raise Exception.new("The header cannot contain destination group and node at the same time") if has_destination_node_id && has_destination_group_id
          raise Exception.new("Unsupported header version #{version}") if version != HEADER_VERSION

          session_id = io.read_bytes(UInt16, byte_format)
          security_flags = io.read_bytes(UInt8, byte_format)
          message_id = io.read_bytes(UInt32, byte_format)

          source_node_id = has_source_node_id ? DataType::NodeId.new(io.read_bytes(UInt64, byte_format)) : nil
          destination_node_id = has_destination_node_id ? DataType::NodeId.new(io.read_bytes(UInt64, byte_format)) : nil
          destination_group_id = has_destination_group_id ? DataType::GroupId.new(io.read_bytes(UInt16, byte_format)) : nil

          session_type = security_flags & 0b00000011

          raise Exception.new("Unsupported session type #{session_type}") if session_type != SessionType::Group.value && session_type != SessionType::Unicast.value

          has_privacy_enhancements = (security_flags & SecurityFlag::HasPrivacyEnhancements.value) != 0
          raise Exception.new("Privacy enhancements not supported") if has_privacy_enhancements

          is_control_message = (security_flags & SecurityFlag::IsControlMessage.value) != 0
          raise Exception.new("Control Messages not supported") if is_control_message

          has_message_extensions = (security_flags & SecurityFlag::HasMessageExtension.value) != 0
          raise Exception.new("Message extensions not supported") if has_message_extensions

          PacketHeader.new(session_id: session_id,
            session_type: SessionType.from_value(session_type),
            message_id: message_id,
            source_node_id: source_node_id,
            destination_node_id: destination_node_id,
            destination_group_id: destination_group_id,
            privacy_enhancements: has_privacy_enhancements,
            control_message: is_control_message,
            message_extensions: has_message_extensions)
        end

        private def decode_payload_header(io : IO::Memory, byte_format : IO::ByteFormat = IO::ByteFormat::LittleEndian) : PayloadHeader
          flags = io.read_bytes(UInt8, byte_format)

          is_initiator_message = (flags & PayloadHeaderFlag::IsInitiatorMessage.value) != 0
          is_acknowledge_message = (flags & PayloadHeaderFlag::IsAckMessage.value) != 0
          requires_acknowledge = (flags & PayloadHeaderFlag::RequiresAck.value) != 0
          has_secured_extension = (flags & PayloadHeaderFlag::HasSecureExtension.value) != 0
          has_vendor_id = (flags & PayloadHeaderFlag::HasVendorId.value) != 0

          raise Exception.new("Secured extension is not supported") if has_secured_extension

          message_type = io.read_bytes(UInt8, byte_format)
          exchange_id = io.read_bytes(UInt16, byte_format)
          vendor_id = has_vendor_id ? io.read_bytes(UInt16, byte_format) : COMMON_VENDOR_ID
          protocol_id = (vendor_id << 16) | io.read_bytes(UInt16, byte_format)
          acknowledged_message_id = is_acknowledge_message ? io.read_bytes(UInt32, byte_format) : nil

          PayloadHeader.new(exchange_id: exchange_id,
            protocol_id: protocol_id,
            message_type: message_type,
            initiator_message: is_initiator_message,
            requires_acknowledge: requires_acknowledge,
            acknowledged_message_id: acknowledged_message_id)
        end
      end
    end
  end
end
