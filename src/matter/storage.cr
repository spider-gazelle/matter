# Persistent storage backends.
#
# `storage/manager` is deliberately not loaded here: it depends on the fabric
# table, protocol persistence and clusters, so `matter.cr` loads it after the
# protocol layer.
require "./storage/type"
require "./storage/base"
require "./storage/memory_backend"
require "./storage/json_file_backend"
