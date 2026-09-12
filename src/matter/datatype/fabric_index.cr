module Matter
  module DataType
    # A fabric index is a bare `UInt8` on the wire, so it has no wrapper struct.
    # The spec reserves index 0 to mean "not associated with any fabric"; a field
    # that is absent altogether is represented by `nil`.
    NO_FABRIC = 0_u8
  end
end
