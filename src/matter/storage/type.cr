module Matter
  module Storage
    alias BaseType = String | Int8 | Int16 | Int32 | Int64 | UInt8 | UInt16 | UInt32 | UInt64 | Float32 | Float64 | BigInt | Bool | Slice(UInt8) | BigInt | Nil
    alias ComplexType = DataType::AttributeId | DataType::ClusterId | DataType::CommandId | DataType::EndpointNumber | DataType::EventId | DataType::FabricId | DataType::FabricIndex | DataType::GroupId | DataType::NodeId | DataType::VendorId

    alias Type = BaseType | ComplexType | Array(Type) | Hash(String, Type) | Hash(BaseType, Type)
  end
end
