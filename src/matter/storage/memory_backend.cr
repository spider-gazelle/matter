module Matter
  module Storage
    class MemoryBackend < Base
      getter store : Hash(String, Type) = {} of String => Type
      getter? initialized : Bool = true

      def start : Void
        @initialized = true
      end

      def stop : Void
        @initialized = false
      end

      def get(contexts : Array(String), key : String) : Type
        raise Exception.new("Context and key must not be empty!") if context.size == 0 || key.size == 0

        context_key = create_context_key(contexts)

        if context = store[context_key]
          return context
            .as(Hash(String, Type))
            .[key]
        end
      end

      def set(contexts : Array(String), key : String, value : Type) : Void
        raise Exception.new("Context and key must not be empty!") if contexts.size == 0 || key.size == 0

        context_key = create_context_key(contexts)

        unless store.has_key?(context_key)
          store[context_key] = {} of String => Type
        end

        store[context_key].as(Hash(String, Type)).[key] = value
      end

      def delete(contexts : Array(String), key : String) : Void
        raise Exception.new("Context and key must not be empty!") if contexts.size == 0 || key.size == 0

        context_key = create_context_key(contexts)

        if context = store[context_key]
          return context
            .as(Hash(String, Type))
            .delete(key)
        end
      end

      def keys(contexts : Array(String)) : Array(String)
        raise Exception.new("Context must not be empty!") if contexts.size == 0

        context_key = create_context_key(contexts)

        if context = store[context_key]
          return context
            .as(Hash(String, Type))
            .keys
        end

        [] of String
      end

      def clear
        store.clear
      end

      def clear_all(contexts : Array(String)) : Void
        context_key = create_context_key(contexts)

        store.delete(context_key) if context_key.size != 0

        start_context_key = context_key.size == 0 ? context_key : ""

        store.keys.each do |key|
          store.delete(key) if key.starts_with?(start_context_key)
        end
      end

      private def create_context_key(contexts : Array(String)) : String
        key = contexts.join(".")

        if key.size == 0 || key.includes?("..") || key.starts_with?(".") || key.ends_with?(".")
          raise Exception.new("Context must not be an empty string.")
        end

        key
      end
    end
  end
end
