module Matter
  module Utilities
    class Cache(T)
      alias Interface = Socket::IPAddress

      @known_keys = Set(Interface).new
      @values = Hash(Interface, T).new
      @timestamps = Hash(Interface, Int64).new
      @periodic_timer = Channel(Bool).new

      def initialize(@generator : Interface -> T, @expiration_ms : Int64, @expire_callback : (Interface, T -> Nil)? = nil)
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

      def get(key : Interface) : T
        value = @values[key]?

        if value.nil?
          value = @generator.call(key)
          @values[key] = value
          @known_keys.add(key)
        end

        @timestamps[key] = Time.local.to_unix_ms
        value
      end

      def keys : Array(Interface)
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

      private def delete_entry(key : Interface)
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
