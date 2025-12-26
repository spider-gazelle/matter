require "./registry"

require "./commands/pairing"
require "./commands/onoff"

module ChipTool
  module Commands
    extend self

    def register_all : Nil
      Pairing.register
      OnOff.register
    end
  end
end

ChipTool::Commands.register_all
