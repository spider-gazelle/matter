module Matter
  module Storage
    abstract class Base
      abstract def start : Void
      abstract def stop : Void
      abstract def initialized? : Bool
      abstract def get(contexts : Array(String), key : String) : Type
      abstract def set(contexts : Array(String), key : String, value : Type) : Void
      abstract def delete(contexts : Array(String), key : String) : Void
      abstract def keys(contexts : Array(String)) : Array(String)
      abstract def clear_all(contexts : Array(String)) : Void
    end
  end
end
