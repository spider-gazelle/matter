module Matter
  module Storage
    abstract class Base
      abstract def start : Nil
      abstract def stop : Nil
      abstract def initialized? : Bool
      abstract def get(contexts : Array(String), key : String) : Type
      abstract def set(contexts : Array(String), key : String, value : Type) : Nil
      abstract def delete(contexts : Array(String), key : String) : Nil
      abstract def keys(contexts : Array(String)) : Array(String)
      abstract def values(contexts : Array(String)) : Hash(String, Type)
      abstract def contexts(contexts : Array(String)) : Array(String)
      abstract def clear : Nil
      abstract def clear_all(contexts : Array(String)) : Nil

      CONTEXT_SEPARATOR = "."

      # Join a context path into the flat key used by the backing store.
      # Raises `Matter::StorageError` when the path is empty or contains an empty segment.
      protected def create_context_key(contexts : Array(String)) : String
        raise Matter::StorageError.new("Context must not be empty!") if contexts.empty?

        key = contexts.join(CONTEXT_SEPARATOR)

        if key.empty? || key.includes?(CONTEXT_SEPARATOR * 2) || key.starts_with?(CONTEXT_SEPARATOR) || key.ends_with?(CONTEXT_SEPARATOR)
          raise Matter::StorageError.new("Context must not be an empty string.")
        end

        key
      end
    end
  end
end
