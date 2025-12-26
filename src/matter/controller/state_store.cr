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
        return State.new unless File.exists?(@path)
        State.from_json(File.read(@path))
      rescue ex
        raise "Failed to load controller state (path=#{@path}): #{ex.message}"
      end

      def save(state : State) : Nil
        File.write(@path, state.to_pretty_json)
      rescue ex
        raise "Failed to save controller state (path=#{@path}): #{ex.message}"
      end
    end
  end
end
