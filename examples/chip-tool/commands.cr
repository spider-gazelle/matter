require "./registry"

require "./commands/pairing"
require "./commands/onoff"
require "./commands/basicinformation"
require "./commands/descriptor"
require "./commands/administratorcommissioning"
require "./commands/operationalcredentials"
require "./commands/accesscontrol"

module ChipTool
  module Commands
    extend self

    def register_all : Nil
      Pairing.register
      OnOff.register
      BasicInformation.register
      Descriptor.register
      AdministratorCommissioning.register
      OperationalCredentials.register
      AccessControl.register
    end
  end
end

ChipTool::Commands.register_all
