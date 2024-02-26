module Matter
  module Cluster
    module Definitions
      module ModeSelect
        # A Semantic Tag is meant to be interpreted by the client for the purpose the cluster serves.
        struct SemanticTag
          include TLV::Serializable

          # If this field is null, the Value field shall be defined in a standard namespace as indicated by the
          # StandardNamespace attribute. If this field is not null, it shall indicate a manufacturer code (Vendor ID),
          # and the Value field shall indicate a semantic tag defined by the manufacturer. Each manufacturer code
          # supports a single namespace of values. The same manufacturer code and semantic tag value in separate cluster
          # instances are part of the same namespace and have the same meaning. For example: a manufacturer tag meaning
          # "pinch", has the same meaning in a cluster whose purpose is to choose the amount of sugar, or amount of salt.
          @[TLV::Field(tag: 0)]
          property mfg_code : DataType::VendorId?

          # This field shall indicate the semantic tag within a semantic tag namespace which is either manufacturer
          # specific or standard. For semantic tags in a standard namespace, see Standard Namespace.
          @[TLV::Field(tag: 1)]
          property value : UInt16
        end

        # This is a struct representing a possible mode of the server.
        struct ModeOption
          include TLV::Serializable

          # This field is readable text that describes the mode option that can be used by a client to indicate to the
          # user what this option means. This field is meant to be readable and understandable by the user.
          @[TLV::Field(tag: 0)]
          property label : String

          # The Mode field is used to identify the mode option. The value shall be unique for every item in the
          # SupportedModes attribute.
          @[TLV::Field(tag: 1)]
          property mode : UInt8

          # This field is a list of semantic tags that map to the mode option. This may be used by clients to determine
          # the meaning of the mode option as defined in a standard or manufacturer specific namespace. Semantic tags
          # can help clients look for options that meet certain criteria. A semantic tag shall be either a standard tag
          # or manufacturer specific tag as defined in each SemanticTagStruct list entry.
          #
          # A mode option may have more than one semantic tag. A mode option may be mapped to a mixture of standard and
          # manufacturer specific semantic tags.
          #
          # All standard semantic tags are from a single namespace indicated by the StandardNamespace attribute.
          #
          # For example: A mode labeled "100%" can have both the HIGH (MS) and MAX (standard) semantic tag. Clients
          # seeking the option for either HIGH or MAX will find the same option in this case.
          @[TLV::Field(tag: 2)]
          property semantic_tags : Array(SemanticTag)
        end

        # Input to the ModeSelect changeToMode command
        struct ChangeToModeRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property new_mode : UInt8
        end
      end
    end
  end
end
