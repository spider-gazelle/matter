module Matter
  module Utilities
    module DeepEqual
      def deep_equal?(a : Hash, b : Hash) : Bool
        if a == nil || b == nil || typeof(a) != typeof(b) || (typeof(a) != Hash && typeof(b) != Hash)
          return a == b
        end

        # If number of properties is different,
        # objects are not equivalent
        return false if a.keys.size != b.keys.size

        a.keys.each_with_index do |a_key, index|
          b_key = b.keys[index]

          return false if typeof(a_key) != typeof(b_key)

          if typeof(a[a_key]) == Hash && typeof(b[b_key]) == Hash
            # Turn the hashes into JSON format, easier to compare and less headache from the type checker
            return a[a_key].to_json == b[b_key].to_json
          else
            return false if a[a_key] != b[b_key]
          end
        end

        return true
      end
    end
  end
end
