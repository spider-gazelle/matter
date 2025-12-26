require "file_utils"

require "./context"
require "./help"
require "./commands"

module ChipTool
  class CLI
    def self.run(argv : Array(String)) : Int32
      ctx, args = Context.parse(argv)

      if args.empty? || args.first.in?("help", "--help", "-h")
        puts Help.render
        return 0
      end

      set_name = args.shift
      command_name = args.shift?

      unless command_name
        puts Help.render(error: "missing command for #{set_name}")
        return 2
      end

      if handler = Registry.lookup(set_name, command_name)
        handler.call(ctx, args)
      else
        puts Help.render(error: "unknown command: #{set_name} #{command_name}")
        2
      end
    rescue ex
      STDERR.puts "chip-tool: error: #{ex.message}"
      ex.backtrace?.try { |backtrace| STDERR.puts backtrace.join('\n') }
      1
    end
  end
end
