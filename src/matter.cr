require "big"
require "log"
require "json"

require "tlv"
require "named_information"
require "verhoeff"

module Matter
  {% begin %}
    VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify.downcase }}
  {% end %}
end

require "./matter/**"
