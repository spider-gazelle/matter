# Compile-failure fixture for `spec/cluster/dsl_spec.cr`: a mandatory command
# declared without a handler method must be rejected by `dsl_generate`.
require "../../src/matter/cluster/cluster"

class MissingHandlerCluster < Matter::Cluster::Base
  cluster 0xFFF1_FC11, revision: 1

  command 0x00, :unhandled
end
