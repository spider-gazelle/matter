require "spec"
require "timecop"
require "../src/matter"

Spec.before_suite do
  ::Log.setup("*", :trace)
end
