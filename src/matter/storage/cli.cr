require "option_parser"
require "../storage"
require "./legacy"

module Matter
  module Storage
    # `matter-storage`: copy a store between backends or print its contents.
    #
    # ```text
    # matter-storage migrate --from yaml:old.yml --to json:new.json
    # matter-storage inspect json:new.json
    # ```
    #
    # Store URIs are those accepted by `Migrator.open`: `memory:`,
    # `yaml:<path>`, `json:<path>` and, for pre-refactor files,
    # `legacy:<path>` (see `Storage::Legacy`).
    module CLI
      PROGRAM = "matter-storage"

      MIGRATE_COMMAND = "migrate"
      INSPECT_COMMAND = "inspect"

      EXIT_OK      = 0
      EXIT_FAILURE = 1
      EXIT_USAGE   = 2

      # Document keys whose values are never printed.
      SENSITIVE_KEY = /key|secret|ipk|challenge|cert/i
      REDACTED      = "<redacted>"
      NULL          = "null"
      INDENT        = "  "

      # Runs the CLI with *args*, writing to *output* / *error*, and returns
      # the process exit code.
      def self.run(args : Array(String), output : IO = STDOUT, error : IO = STDERR) : Int32
        command = nil
        from = nil
        to = nil
        help = false
        positional = [] of String

        parser = OptionParser.new do |opts|
          opts.banner = "Usage: #{PROGRAM} <command> [options]\n\nStore URIs: memory:, yaml:<path>, json:<path>\n\nCommands:"
          opts.on(MIGRATE_COMMAND, "Copy every collection from one store to another") do
            command = MIGRATE_COMMAND
            opts.on("--from URI", "Source store") { |uri| from = uri }
            opts.on("--to URI", "Destination store") { |uri| to = uri }
          end
          opts.on(INSPECT_COMMAND, "Print collections, ids and documents (secrets redacted)") do
            command = INSPECT_COMMAND
          end
          opts.on("-h", "--help", "Show this help") { help = true }
          opts.unknown_args { |before, after| positional = before + after }
          opts.invalid_option { |flag| raise ArgumentError.new("Unknown option #{flag}") }
          opts.missing_option { |flag| raise ArgumentError.new("#{flag} needs a value") }
        end

        begin
          parser.parse(args)

          if help
            output.puts parser
            return EXIT_OK
          end

          case command
          when MIGRATE_COMMAND
            source_uri = from
            target_uri = to
            raise ArgumentError.new("#{MIGRATE_COMMAND} needs --from and --to") unless source_uri && target_uri
            migrate(source_uri, target_uri, output)
          when INSPECT_COMMAND
            uri = positional.first? || raise ArgumentError.new("#{INSPECT_COMMAND} needs a store URI")
            inspect(uri, output)
          else
            error.puts parser
            EXIT_USAGE
          end
        rescue ex : ArgumentError
          error.puts "#{PROGRAM}: #{ex.message}"
          error.puts parser
          EXIT_USAGE
        rescue ex : StorageError | File::Error
          error.puts "#{PROGRAM}: #{ex.message}"
          EXIT_FAILURE
        end
      end

      private def self.migrate(from_uri : String, to_uri : String, output : IO) : Int32
        source = Migrator.open(from_uri)
        target = Migrator.open(to_uri)
        counts = Migrator.copy(source, target)
        counts.each { |collection, count| output.puts "#{collection}: #{count} document#{count == 1 ? "" : "s"}" }
        output.puts "Copied #{counts.values.sum} document#{counts.values.sum == 1 ? "" : "s"} from #{from_uri} to #{to_uri}"
        source.close
        target.close
        EXIT_OK
      end

      private def self.inspect(uri : String, output : IO) : Int32
        backend = Migrator.open(uri)
        collections = backend.collections
        output.puts "#{uri}: #{collections.size} collection#{collections.size == 1 ? "" : "s"}"
        collections.each do |collection|
          documents = backend.all(collection)
          output.puts "#{collection} (#{documents.size})"
          documents.each do |id, document|
            output.puts "#{INDENT}#{id}"
            document.each { |key, value| output.puts "#{INDENT * 2}#{key}: #{render(key, value)}" }
          end
        end
        backend.close
        EXIT_OK
      end

      # Renders *value* for display, hiding byte strings and anything stored
      # under a sensitive-looking key.
      def self.render(key : String, value : Type) : String
        case value
        in Bytes
          "<bytes #{value.size}>"
        in Nil
          NULL
        in Bool, Int64, UInt64, Float64, String, Time, Array(Type), Hash(String, Type)
          key.matches?(SENSITIVE_KEY) ? REDACTED : render(value)
        end
      end

      private def self.render(value : Type) : String
        case value
        in Nil
          NULL
        in Bool, Int64, UInt64, Float64
          value.to_s
        in String
          value.inspect
        in Time
          value.to_rfc3339(fraction_digits: YamlFile::TIME_FRACTION_DIGITS)
        in Bytes
          "<bytes #{value.size}>"
        in Array(Type)
          "[#{value.join(", ") { |element| render(element) }}]"
        in Hash(String, Type)
          "{#{value.join(", ") { |nested_key, element| "#{nested_key}: #{render(nested_key, element)}" }}}"
        end
      end
    end
  end
end

# Run when built as the `matter-storage` target; stay quiet under `crystal spec`.
{% unless @top_level.has_constant?("Spec") %}
  exit Matter::Storage::CLI.run(ARGV)
{% end %}
