module Matter
  module Storage
    class Manager
      getter storage : Base

      def initialize(@storage : Base)
      end

      def create_context(context : String) : Context
        raise Exception.new("The storage needs to be initialized first") unless storage.initialized?
        raise Exception.new("Context must not be an empty string!") if context.size == 0
        raise Exception.new("Context must not contain dots!") if context.includes?(".")

        Context.new(storage, [context])
      end
    end
  end
end
