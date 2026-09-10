require "./tree_backend"

module Matter
  module Storage
    # An in-memory store, open from construction. Useful for tests and for
    # devices whose state is rebuilt on every start.
    class Memory < TreeBackend
      def initialize
        open
      end

      def open : Nil
        @mutex.synchronize do
          return if @open
          @open = true
          seed_schema
        end
      end

      def path : String?
        nil
      end

      # Discards every document (including `meta/schema`) and closes the store.
      def destroy! : Nil
        @mutex.synchronize do
          @tree.clear
          close
        end
      end

      protected def persist : Nil
      end
    end
  end
end
