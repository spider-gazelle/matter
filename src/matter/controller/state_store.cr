require "json"
require "file_utils"
require "./state"

module Matter
  module Controller
    class StateStore
      getter storage_directory : String
      getter path : String

      def initialize(@storage_directory : String, filename : String = "controller.json")
        @path = File.join(@storage_directory, filename)
        FileUtils.mkdir_p(@storage_directory)
      end

      def load : State
        state = if File.exists?(@path)
                  State.from_json(File.read(@path))
                else
                  State.new
                end

        state, dirty = normalize(state)
        save(state) if dirty && File.exists?(@path)
        state
      rescue ex
        raise "Failed to load controller state (path=#{@path}): #{ex.message}"
      end

      def save(state : State) : Nil
        File.write(@path, state.to_pretty_json)
      rescue ex
        raise "Failed to save controller state (path=#{@path}): #{ex.message}"
      end

      private def normalize(state : State) : {State, Bool}
        dirty = false

        if fabric = state.fabric
          if state.commissioner_node_id != fabric.controller_node_id
            state = State.new(
              fabric: state.fabric,
              nodes: state.nodes,
              commissioner_node_id: fabric.controller_node_id,
              unsecured_message_counter: state.unsecured_message_counter
            )
            dirty = true
          end
        elsif state.commissioner_node_id == 0_u64
          state = State.new(
            fabric: state.fabric,
            nodes: state.nodes,
            commissioner_node_id: random_nonzero_u64,
            unsecured_message_counter: state.unsecured_message_counter
          )
          dirty = true
        end

        {state, dirty}
      end

      private def random_nonzero_u64 : UInt64
        loop do
          id = Random::Secure.rand(UInt64)
          return id unless id == 0_u64
        end
      end
    end
  end
end
