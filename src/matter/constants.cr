module Matter
  module Constants
    {% begin %}
      VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify.downcase }}
    {% end %}
  end
end