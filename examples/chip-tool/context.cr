require "file_utils"

module ChipTool
  # Command-line context: where the controller keeps its state and how long to
  # wait for devices. The controller state lives in one YAML store,
  # `<storage_directory>/controller.yml`, shared by every command.
  class Context
    DEFAULT_TIMEOUT       = 10.seconds
    DEFAULT_STORAGE_DIR   = "chip-tool-storage"
    STORAGE_DIR_ENV       = "MATTER_CHIP_TOOL_STORAGE"
    CONTROLLER_STATE_FILE = "controller.yml"

    getter storage_directory : String
    getter timeout : Time::Span
    getter state_store : Matter::Controller::StateStore

    def initialize(@storage_directory : String, @timeout : Time::Span = DEFAULT_TIMEOUT)
      FileUtils.mkdir_p(@storage_directory)
      backend = Matter::Storage::YamlFile.new(File.join(@storage_directory, CONTROLLER_STATE_FILE))
      @state_store = Matter::Controller::StateStore.new(backend)
    end

    def self.parse(argv : Array(String)) : {Context, Array(String)}
      args = argv.dup

      storage_dir = ENV[STORAGE_DIR_ENV]? || File.join(Dir.current, DEFAULT_STORAGE_DIR)
      timeout = DEFAULT_TIMEOUT

      i = 0
      while i < args.size
        case args[i]
        when "--storage-directory"
          value = args[i + 1]?
          raise ArgumentError.new("missing value for --storage-directory") unless value
          storage_dir = value
          args.delete_at(i)
          args.delete_at(i)
          next
        when "--timeout"
          value = args[i + 1]?
          raise ArgumentError.new("missing value for --timeout") unless value
          timeout = value.to_f64.seconds
          args.delete_at(i)
          args.delete_at(i)
          next
        end
        i += 1
      end

      {new(storage_dir, timeout), args}
    end
  end
end
