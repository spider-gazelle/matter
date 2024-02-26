module Matter
  module Utilities
    class Cache(T)
      @known_keys = Set(String).new
      @values = Hash(String, T).new
      @timestamps = Hash(String, Int64).new
      @periodic_timer = Channel(Bool).new

      def initialize(@generator : String -> T, @expiration_ms : Int64, @expire_callback : (String, T -> Nil)? = nil)
        spawn do
          loop do
            if has_expired = @periodic_timer.receive?
              expire
            end
          end
        end

        spawn do
          loop do
            sleep @expiration_ms / 1000

            @periodic_timer.send(true)
          end
        end
      end

      def get(params : Array) : T
        key = params.join(",")
        value = @values[key]?

        if value.nil?
          value = @generator.call(key)
          @values[key] = value
          @known_keys.add(key)
        end

        @timestamps[key] = Time.local.to_unix_ms
        value
      end

      def keys : Array(String)
        @known_keys.to_a
      end

      def clear
        @values.each_key { |key| delete_entry(key) }
        @values.clear
        @timestamps.clear
      end

      def close
        clear
        @known_keys.clear
        @periodic_timer.send(true)
      end

      private def delete_entry(key : String)
        value = @values[key]?

        unless @expire_callback.nil? || value.nil?
          @expire_callback.not_nil!.call(key, value)
        end

        @values.delete(key)
        @timestamps.delete(key)
      end

      private def expire
        now = Time.local.to_unix_ms

        @timestamps.each do |key, timestamp|
          next if now - timestamp < @expiration_ms
          delete_entry(key)
        end
      end
    end
  end
end
