require "./base"
require "./type"

module Matter
  module Storage
    class MemoryBackend < Base
      getter store : Hash(String, LegacyType) = {} of String => LegacyType
      getter? initialized : Bool = true

      def start : Nil
        @initialized = true
      end

      def stop : Nil
        @initialized = false
      end

      def get(contexts : Array(String), key : String) : LegacyType
        raise Matter::StorageError.new("Context and key must not be empty!") if contexts.size == 0 || key.size == 0

        context_key = create_context_key(contexts)

        if context = store[context_key]?
          return context.as(Hash(String, LegacyType))[key]?
        end

        nil
      end

      def set(contexts : Array(String), key : String, value : LegacyType) : Nil
        raise Matter::StorageError.new("Context and key must not be empty!") if contexts.size == 0 || key.size == 0

        context_key = create_context_key(contexts)

        unless store.has_key?(context_key)
          store[context_key] = {} of String => LegacyType
        end

        store[context_key].as(Hash(String, LegacyType)).[key] = value
      end

      def delete(contexts : Array(String), key : String) : Nil
        raise Matter::StorageError.new("Context and key must not be empty!") if contexts.size == 0 || key.size == 0

        context_key = create_context_key(contexts)

        if context = store[context_key]?
          context
            .as(Hash(String, LegacyType))
            .delete(key)
        end
      end

      def keys(contexts : Array(String)) : Array(String)
        context_key = create_context_key(contexts)

        if context = store[context_key]?
          return context
            .as(Hash(String, LegacyType))
            .keys
            .sort!
        end

        [] of String
      end

      # Get all key-value pairs in a context
      def values(contexts : Array(String)) : Hash(String, LegacyType)
        context_key = create_context_key(contexts)

        if context = store[context_key]?
          return context.as(Hash(String, LegacyType)).dup
        end

        {} of String => LegacyType
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
    end
  end
end
