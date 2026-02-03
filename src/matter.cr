require "big"
require "log"
require "json"
require "time/instant"

require "tlv"
require "verhoeff"

module Matter
  {% begin %}
    VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify.downcase }}
  {% end %}
end

require "./matter/**"
