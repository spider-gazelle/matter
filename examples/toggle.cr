require "../src/matter"

require "socket"

module Toggle
  alias Configuration = Matter::Cluster::Definitions::BasicInformation::Configuration

  server = Matter::MDNS::Server.new

  pp server
end

sleep
