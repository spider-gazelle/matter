# Compile-failure fixture for `spec/cluster/dsl_spec.cr`: a computed attribute
# declared without a reader method must be rejected by `dsl_generate`.
require "../../src/matter/cluster/cluster"

class MissingReaderCluster < Matter::Cluster::Base
  cluster 0xFFF1_FC11, revision: 1

  attribute 0x0000, :elapsed, UInt32, computed: true
end
