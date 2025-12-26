require "./context"

module ChipTool
  record CommandInfo, name : String, description : String

  alias Handler = Proc(Context, Array(String), Int32)

  module Registry
    extend self

    @@handlers = Hash(String, Hash(String, Handler)).new
    @@index = Hash(String, Array(CommandInfo)).new

    def register(set_name : String, command_name : String, description : String, &block : Handler) : Nil
      @@handlers[set_name] ||= {} of String => Handler
      @@handlers[set_name][command_name] = block

      @@index[set_name] ||= [] of CommandInfo
      @@index[set_name] << CommandInfo.new(command_name, description)
      @@index[set_name].sort_by!(&.name)
    end

    def lookup(set_name : String, command_name : String) : Handler?
      @@handlers[set_name]?.try(&.[command_name]?)
    end

    def command_index : Hash(String, Array(CommandInfo))
      @@index.to_a.sort_by(&.[0]).to_h
    end
  end
end
