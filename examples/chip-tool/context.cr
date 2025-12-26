require "file_utils"

module ChipTool
  record Context, storage_directory : String, timeout : Time::Span do
    DEFAULT_TIMEOUT = 10.seconds

    def self.parse(argv : Array(String)) : {Context, Array(String)}
      args = argv.dup

      storage_dir = ENV["MATTER_CHIP_TOOL_STORAGE"]? || File.join(Dir.current, "chip-tool-storage")
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

      FileUtils.mkdir_p(storage_dir)

      {new(storage_dir, timeout), args}
    end
  end
end
