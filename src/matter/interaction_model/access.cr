# Access-control primitives shared by cluster metadata (`Cluster::Base`),
# the interaction-model handler and the AccessControl cluster.
module Matter
  module InteractionModel
    # This value implicitly grants View privileges
    enum EntryPrivilege : UInt8
      # Can read and observe all (except Access Control Cluster and as seen by a non-Proxy)
      View = 1

      # Can read and observe all (as seen by a Proxy)
      ProxyView = 2

      # View privileges, and can perform the primary function of this Node (except Access Control Cluster)
      # This value implicitly grants View privileges
      Operate = 3

      # Operate privileges, and can modify persistent configuration of this Node (except Access Control Cluster)
      # This value implicitly grants Operate & View privileges
      Manage = 4

      # Manage privileges, and can observe and modify the Access Control Cluster
      # This value implicitly grants Manage, Operate, Proxy View & View privileges
      Administer = 5
    end

    enum EntryAuthMode : UInt8
      # Passcode authenticated session
      Pase = 1

      # Certificate authenticated session
      Case = 2

      # Group authenticated session
      Group = 3
    end
  end
end
