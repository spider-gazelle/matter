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
    end
  end
end
