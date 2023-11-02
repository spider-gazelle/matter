module Matter
  module Storage
    class Context
      getter storage : Base
      getter contexts : Array(String)

      def initialize(@storage : Base, @contexts : Array(String))
      end

      def get(key : String, default_value : Type? = nil) : Type
        value = storage.get(contexts, key)

        return value unless value.nil?
        raise Exception.new("No value found for key #{key} in context #{contexts} and no default value specified!") if value.nil? && default_value.nil?

        default_value
      end

      def set(key : String, value : Type) : Void
        storage.set(contexts, key, value)
      end

      def has(key : String) : Bool
        storage.get(contexts, key).nil? ? false : true
      end

      def delete(key : String) : Void
        storage.delete(contexts, key)
      end

      def create_context(context : String)
        raise Exception.new("Context must not be an empty string!") if context.size == 0
        raise Exception.new("Context must not contain dots!") if context.includes?(".")

        Context.new(storage, ([] of String).concat(contexts).push(context))
      end

      def keys : Array(String)
        storage.keys(contexts)
      end

      # Clears all keys in this context.
      def clear : Void
        keys.each do |key|
          delete(key)
        end
      end

      # Clears all keys in this context and all created sub-contexts.
      def clear_all : Void
        storage.clear_all(contexts)
      end
    end
  end
end
