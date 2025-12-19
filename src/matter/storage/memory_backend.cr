module Matter
  module Storage
    class MemoryBackend < Base
      getter store : Hash(String, Type) = {} of String => Type
      getter? initialized : Bool = true

      def start : Nil
        @initialized = true
      end

      def stop : Nil
        @initialized = false
      end

      def get(contexts : Array(String), key : String) : Type
        raise Exception.new("Context and key must not be empty!") if contexts.size == 0 || key.size == 0

        context_key = create_context_key(contexts)

        if context = store[context_key]?
          return context.as(Hash(String, Type))[key]?
        end

        nil
      end

      def set(contexts : Array(String), key : String, value : Type) : Nil
        raise Exception.new("Context and key must not be empty!") if contexts.size == 0 || key.size == 0

        context_key = create_context_key(contexts)

        unless store.has_key?(context_key)
          store[context_key] = {} of String => Type
        end

        store[context_key].as(Hash(String, Type)).[key] = value
      end

      # Set multiple key-value pairs at once
      def set(contexts : Array(String), values : Hash(String, Type)) : Nil
        raise Exception.new("Context must not be empty!") if contexts.size == 0

        values.each do |key, value|
          set(contexts, key, value)
        end
      end

      def delete(contexts : Array(String), key : String) : Nil
        raise Exception.new("Context and key must not be empty!") if contexts.size == 0 || key.size == 0

        context_key = create_context_key(contexts)

        if context = store[context_key]?
          context
            .as(Hash(String, Type))
            .delete(key)
        end
      end

      def keys(contexts : Array(String)) : Array(String)
        raise Exception.new("Context must not be empty!") if contexts.size == 0

        context_key = create_context_key(contexts)

        if context = store[context_key]?
          return context
            .as(Hash(String, Type))
            .keys
            .sort
        end

        [] of String
      end

      # Get all key-value pairs in a context
      def values(contexts : Array(String)) : Hash(String, Type)
        raise Exception.new("Context must not be empty!") if contexts.size == 0

        context_key = create_context_key(contexts)

        if context = store[context_key]?
          return context.as(Hash(String, Type))
        end

        {} of String => Type
      end

      # Get list of immediate subcontext names
      def contexts(contexts : Array(String)) : Array(String)
        context_key = contexts.size == 0 ? "" : create_context_key(contexts)
        prefix = context_key.size == 0 ? "" : "#{context_key}."

        subcontexts = Set(String).new

        store.keys.each do |key|
          # For root level contexts (empty context_key)
          if context_key.size == 0
            # Get the first segment before any dot, or the whole key if no dot
            if dot_index = key.index('.')
              subcontexts << key[0...dot_index]
            else
              # This is a direct context at root level
              subcontexts << key
            end
          elsif key.starts_with?(prefix)
            # Get the part after the prefix
            remainder = key[prefix.size..-1]
            # Get the first segment (immediate subcontext)
            if dot_index = remainder.index('.')
              subcontexts << remainder[0...dot_index]
            else
              # This IS a direct subcontext (no further nesting)
              subcontexts << remainder
            end
          end
        end

        subcontexts.to_a.sort
      end

      def clear : Nil
        store.clear
      end

      def clear_all(contexts : Array(String)) : Nil
        # Handle empty contexts - clear everything
        if contexts.size == 0
          store.clear
          return
        end

        context_key = create_context_key(contexts)
        prefix = "#{context_key}."

        # Delete the context itself and all subcontexts
        keys_to_delete = store.keys.select do |key|
          key == context_key || key.starts_with?(prefix)
        end

        keys_to_delete.each { |key| store.delete(key) }
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
