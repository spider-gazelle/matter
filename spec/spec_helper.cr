require "spec"
require "timecop"
require "../src/matter"
require "./support/test_network_backend"

Spec.before_suite do
  ::Log.setup("*", :trace)
end
