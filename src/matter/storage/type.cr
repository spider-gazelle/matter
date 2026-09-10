module Matter
  module Storage
    # Values that can be persisted in `Storage::Base`.
    #
    # Storage is primarily used for JSON persistence (fabrics, sessions, cluster
    # state) and supports a small set of primitive types plus nested arrays and
    # string-keyed hashes.
    alias LegacyScalar = Bool | String |
                         Int8 | Int16 | Int32 | Int64 |
                         UInt8 | UInt16 | UInt32 | UInt64 |
                         Float32 | Float64 |
                         BigInt |
                         Bytes?

    alias LegacyType = LegacyScalar | Array(LegacyType) | Hash(String, LegacyType)
  end
end
