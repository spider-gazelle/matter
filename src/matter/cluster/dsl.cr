module Matter
  module Cluster
    # Declarative cluster definitions for `Cluster::Base` subclasses.
    #
    # ```
    # class Matter::Cluster::OnOffCluster < Matter::Cluster::Base
    #   cluster 0x0006, revision: 6
    #
    #   feature :lighting, bit: 0
    #   feature :off_only, bit: 2
    #   conflicts :lighting, :off_only
    #
    #   attribute 0x0000, :on_off, Bool, default: false, persist: true, scene: true
    #   attribute 0x4001, :on_time, UInt16, default: 0_u16, writable: true, requires: :lighting
    #   attribute 0x4003, :start_up_on_off, StartUpOnOff, nullable: true, writable: true, requires: :lighting
    #
    #   command 0x00, :off
    #   command 0x01, :on, requires: {off_only: false}
    #   command 0x42, :on_with_timed_off, request: OnWithTimedOffRequest, requires: :lighting
    #
    #   def off : InteractionModel::Status
    #     self.on_off = false
    #     InteractionModel::Status.success
    #   end
    # end
    # ```
    #
    # Declarations:
    #
    # * `cluster id, revision:` — `CLUSTER_ID`, `CLUSTER_REVISION` and `name`
    #   (the class name without a trailing `Cluster`). Required before any
    #   other declaration. When the class defines no `initialize` of its own,
    #   `initialize(endpoint_id, feature_map: Feature::None)` is generated.
    # * `feature :name, bit:` — a member of the `@[Flags] enum Feature : UInt32`
    #   and the `feature_map` property (default `Feature::None`; a hand-written
    #   `initialize` takes it as `@feature_map : Feature = Feature::None`).
    #   Predicates come from the enum: `feature_map.lighting?`.
    # * `conflicts :a, :b, ...` — pairs that raise `ArgumentError` from the
    #   constructor when combined.
    # * `attribute id, :name, Type, **options` — see `ATTRIBUTE_OPTIONS`.
    #   Generates `ATTR_NAME`, the ivar (`Type?` when `nullable:`), a getter
    #   (`name?` for `Bool`), a setter that ignores equal values, bumps the data
    #   version, notifies subscribers and runs the change callback, and
    #   `on_name_changed(&block : Type, Type -> Nil)` (`(old, new)`; with
    #   `callback: :new_only` the block takes the new value only).
    #   `writable: true` implies `persist: true` unless `persist: false`.
    # * `command id, :name, **options` — see `COMMAND_OPTIONS`. Generates
    #   `CMD_NAME` and dispatches to the handler method `name` (`name(request)`
    #   when `request:` is given). A handler returns an
    #   `InteractionModel::Status`, a `CommandResponse`, or a `TLV::Serializable`
    #   struct which is wrapped as `CommandResponse.new(response_id || id, ...)`.
    #   A command without a handler fails to compile unless `optional: true`,
    #   in which case it is left out of the tables.
    # * `event id, :name, priority:` — `EVENT_NAME` and the `EventMetadata`.
    # * `before_write :name do |value| ... end` — runs on an interaction-model
    #   write after decoding and validation; returning an
    #   `InteractionModel::Status` rejects the write.
    # * `after_write :name do ... end` — runs after the value was assigned.
    #
    # `requires:` is a feature symbol (`:lighting`), a `{feature: Bool}` literal
    # (all must match) or an array of those (any may match). Unsupported
    # elements are left out of the tables and the global lists and answer
    # `UnsupportedAttribute` / `UnsupportedCommand`.
    #
    # Generated into the class (all names are reserved):
    #
    # * constants `CLUSTER_ID`, `CLUSTER_REVISION`, `Feature`, `ATTR_*`, `CMD_*`,
    #   `EVENT_*`, `ATTRIBUTES`, `ATTRIBUTES_BY_ID`, `COMMANDS`, `COMMANDS_BY_ID`,
    #   `EVENTS`, `PersistedState`; the `*_DECLS` accumulators
    # * `name`, `attributes`, `commands`, `events`, `get_attribute_metadata`,
    #   `get_command_metadata`, `feature_map`, `save_state`, `restore_state`
    # * `dsl_read_attribute`, `dsl_write_attribute`, `dsl_invoke_command` —
    #   the branches `Base` dispatches to; a hand-written `read_attribute`,
    #   `handle_write_attribute` or `handle_command` override still reaches
    #   them through `super`
    # * `dsl_features`, `dsl_validate_features`, `dsl_attribute_supported?`,
    #   `dsl_command_supported?`, `dsl_attribute_<name>_supported?`,
    #   `dsl_command_<name>_supported?`, `dsl_before_write_<name>`,
    #   `dsl_after_write_<name>`
    #
    # Declarations accumulate in the `*_DECLS` array constants that `Base`'s
    # `macro inherited` creates in every subclass, and the `macro finished`
    # it emits calls `dsl_generate` once the class body is complete.
    module DSL
      ATTRIBUTE_OPTIONS = [
        :default, :writable, :persist, :nullable, :fixed, :optional, :requires,
        :read_access, :write_access, :min, :max, :max_length, :scene,
        :omit_changes, :timed, :fabric_scoped, :callback,
      ]
      COMMAND_OPTIONS  = [:request, :response, :response_id, :requires, :timed, :access, :optional]
      PRIVILEGES       = [:view, :proxy_view, :operate, :manage, :administer]
      EVENT_PRIORITIES = [:debug, :info, :critical]

      # `AttributeMetadata#type` by Crystal type; enums, arrays and structures
      # are classified in `dsl_generate`.
      TYPE_KINDS = {
        Bool:           :bool,
        UInt8:          :uint8,
        UInt16:         :uint16,
        UInt32:         :uint32,
        UInt64:         :uint64,
        Int8:           :int8,
        Int16:          :int16,
        Int32:          :int32,
        Int64:          :int64,
        Float32:        :single,
        Float64:        :double,
        String:         :string,
        "Slice(UInt8)": :octstr,
      }

      macro cluster(id, revision)
        {% raise "#{@type}: `cluster` declared twice" unless @type.constant("CLUSTER_DECLS").empty? %}
        {% @type.constant("CLUSTER_DECLS") << {id: id, revision: revision} %}

        CLUSTER_ID       = {{ (id.is_a?(NumberLiteral) && id.kind == :i32) ? "#{id}_u32".id : "(#{id}).to_u32".id }}
        CLUSTER_REVISION = {{ (revision.is_a?(NumberLiteral) && revision.kind == :i32) ? "#{revision}_u16".id : "(#{revision}).to_u16".id }}

        def name : String
          {{ @type.name.stringify.split("::").last.gsub(/Cluster$/, "") }}
        end
      end

      macro feature(name, bit)
        {% raise "#{@type}: feature :#{name.id} declared twice" if @type.constant("FEATURE_DECLS").any? { |feature| feature[:name] == name } %}
        {% @type.constant("FEATURE_DECLS") << {name: name, bit: bit} %}
      end

      macro conflicts(*names)
        {% raise "#{@type}: `conflicts` needs at least two features" if names.size < 2 %}
        {% @type.constant("CONFLICT_DECLS") << names %}
      end

      macro attribute(id, name, type, **options)
        {% for key, _value in options %}
          {% unless ::Matter::Cluster::DSL::ATTRIBUTE_OPTIONS.includes?(key.symbolize) %}
            {% raise "#{@type}: attribute :#{name.id} has an unknown option #{key} (expected one of #{::Matter::Cluster::DSL::ATTRIBUTE_OPTIONS.join(", ").id})" %}
          {% end %}
        {% end %}
        {% nullable = options[:nullable] %}
        {% writable = options[:writable] %}
        {% callback = options[:callback] %}
        {% raise "#{@type}: attribute :#{name.id} needs a default: value (or nullable: true)" if options[:default].nil? && !nullable %}
        {% raise "#{@type}: attribute :#{name.id} is fixed: and cannot be writable:" if options[:fixed] && writable %}
        {% raise "#{@type}: attribute :#{name.id} callback: must be :new_only" if callback && callback != :new_only %}
        {% if options[:read_access] && !::Matter::Cluster::DSL::PRIVILEGES.includes?(options[:read_access]) %}
          {% raise "#{@type}: attribute :#{name.id} read_access: must be one of #{::Matter::Cluster::DSL::PRIVILEGES.join(", ").id}" %}
        {% end %}
        {% if options[:write_access] && !::Matter::Cluster::DSL::PRIVILEGES.includes?(options[:write_access]) %}
          {% raise "#{@type}: attribute :#{name.id} write_access: must be one of #{::Matter::Cluster::DSL::PRIVILEGES.join(", ").id}" %}
        {% end %}
        {% raise "#{@type}: attribute :#{name.id} declared twice" if @type.constant("ATTRIBUTE_DECLS").any? { |attribute| attribute[:name] == name } %}

        {% @type.constant("ATTRIBUTE_DECLS") << {
             id:            id,
             name:          name,
             type:          type,
             default:       options[:default],
             writable:      writable,
             persist:       options[:persist].nil? ? writable : options[:persist],
             nullable:      nullable,
             fixed:         options[:fixed],
             optional:      options[:optional],
             requires:      options[:requires],
             read_access:   options[:read_access],
             write_access:  options[:write_access],
             min:           options[:min],
             max:           options[:max],
             max_length:    options[:max_length],
             scene:         options[:scene],
             omit_changes:  options[:omit_changes],
             timed:         options[:timed],
             fabric_scoped: options[:fabric_scoped],
             callback:      callback,
           } %}

        {% value_type = nullable ? "#{type}?".id : type %}
        {% callback_types = callback == :new_only ? "#{value_type}".id : "#{value_type}, #{value_type}".id %}

        ATTR_{{ name.id.upcase }} = {{ (id.is_a?(NumberLiteral) && id.kind == :i32) ? "#{id}_u32".id : "(#{id}).to_u32".id }}

        @{{ name.id }} : {{ value_type }} = {{ options[:default] }}
        @on_{{ name.id }}_changed : Proc({{ callback_types }}, Nil)?

        def {{ name.id }}{{ "?".id if type.resolve? == Bool }} : {{ value_type }}
          @{{ name.id }}
        end

        # Assigns the attribute, bumping the data version, notifying
        # subscribers and running the change callback when the value differs.
        def {{ name.id }}=(value : {{ value_type }}) : Nil
          return if @{{ name.id }} == value
          {% unless callback == :new_only %}
            old_value = @{{ name.id }}
          {% end %}
          @{{ name.id }} = value
          increment_version_and_notify(ATTR_{{ name.id.upcase }})
          @on_{{ name.id }}_changed.try &.call({% unless callback == :new_only %}old_value, {% end %}value)
        end

        def on_{{ name.id }}_changed(&block : {{ callback_types }} -> Nil) : Nil
          @on_{{ name.id }}_changed = block
        end
      end

      macro command(id, name, **options)
        {% for key, _value in options %}
          {% unless ::Matter::Cluster::DSL::COMMAND_OPTIONS.includes?(key.symbolize) %}
            {% raise "#{@type}: command :#{name.id} has an unknown option #{key} (expected one of #{::Matter::Cluster::DSL::COMMAND_OPTIONS.join(", ").id})" %}
          {% end %}
        {% end %}
        {% if options[:access] && !::Matter::Cluster::DSL::PRIVILEGES.includes?(options[:access]) %}
          {% raise "#{@type}: command :#{name.id} access: must be one of #{::Matter::Cluster::DSL::PRIVILEGES.join(", ").id}" %}
        {% end %}
        {% raise "#{@type}: command :#{name.id} declared twice" if @type.constant("COMMAND_DECLS").any? { |command| command[:name] == name } %}

        {% @type.constant("COMMAND_DECLS") << {
             id:          id,
             name:        name,
             request:     options[:request],
             response:    options[:response],
             response_id: options[:response_id],
             requires:    options[:requires],
             timed:       options[:timed],
             access:      options[:access],
             optional:    options[:optional],
           } %}

        CMD_{{ name.id.upcase }} = {{ (id.is_a?(NumberLiteral) && id.kind == :i32) ? "#{id}_u32".id : "(#{id}).to_u32".id }}
      end

      macro event(id, name, priority = :info)
        {% unless ::Matter::Cluster::DSL::EVENT_PRIORITIES.includes?(priority) %}
          {% raise "#{@type}: event :#{name.id} priority: must be one of #{::Matter::Cluster::DSL::EVENT_PRIORITIES.join(", ").id}" %}
        {% end %}
        {% raise "#{@type}: event :#{name.id} declared twice" if @type.constant("EVENT_DECLS").any? { |event| event[:name] == name } %}
        {% @type.constant("EVENT_DECLS") << {id: id, name: name, priority: priority} %}

        EVENT_{{ name.id.upcase }} = {{ (id.is_a?(NumberLiteral) && id.kind == :i32) ? "#{id}_u32".id : "(#{id}).to_u32".id }}
      end

      macro before_write(name, &block)
        {% raise "#{@type}: before_write :#{name.id} takes a block with one argument, the new value" unless block && block.args.size == 1 %}

        private def dsl_before_write_{{ name.id }}({{ block.args.first }}) : ::Matter::InteractionModel::Status?
          %result = begin
            {{ block.body }}
          end
          %result.as?(::Matter::InteractionModel::Status)
        end
      end

      macro after_write(name, &block)
        {% raise "#{@type}: after_write :#{name.id} takes a block without arguments" unless block && block.args.empty? %}

        private def dsl_after_write_{{ name.id }} : Nil
          {{ block.body }}
        end
      end

      # Expands a `requires:` value into a feature-map expression.
      macro dsl_feature_condition(requires)
        {% if requires.is_a?(SymbolLiteral) %}
          @feature_map.{{ requires.id }}?
        {% elsif requires.is_a?(NamedTupleLiteral) %}
          ({{ requires.map { |flag, expected| "@feature_map.#{flag.id}? == #{expected}" }.join(" && ").id }})
        {% elsif requires.is_a?(ArrayLiteral) %}
          ({% for term, index in requires %}{% if index > 0 %} || {% end %}dsl_feature_condition({{ term }}){% end %})
        {% else %}
          {% raise "#{@type}: requires: must be a feature symbol, a {feature: Bool} literal or an array of those, got #{requires}" %}
        {% end %}
      end

      # Generates the tables, dispatch methods and persistence from the
      # accumulated declarations. Called from the `macro finished` that
      # `Base`'s `macro inherited` emits.
      macro dsl_generate
        {% if CLUSTER_DECLS.empty? %}
          {% unless FEATURE_DECLS.empty? && CONFLICT_DECLS.empty? && ATTRIBUTE_DECLS.empty? && COMMAND_DECLS.empty? && EVENT_DECLS.empty? %}
            {% raise "#{@type}: declare `cluster <id>, revision: <n>` before feature, attribute, command or event declarations" %}
          {% end %}
        {% else %}
          {% log = @type.has_constant?("Log") ? "Log".id : "::Matter::Cluster::Log".id %}
          {% has_features = !FEATURE_DECLS.empty? %}
          {% implemented_commands = COMMAND_DECLS.reject { |decl| decl[:optional] && !@type.has_method?(decl[:name].id.stringify) } %}
          {% persisted = ATTRIBUTE_DECLS.select { |decl| decl[:persist] } %}
          {% attribute_kinds = {} of Nil => Nil %}

          # -- compile-time checks ---------------------------------------------

          {% for decl in COMMAND_DECLS %}
            {% unless decl[:optional] || @type.has_method?(decl[:name].id.stringify) %}
              {% raise "#{@type}: command :#{decl[:name].id} has no handler method `#{decl[:name].id}`; define `def #{decl[:name].id}#{(decl[:request] ? "(request : #{decl[:request]})" : "").id}` or declare it optional: true" %}
            {% end %}
          {% end %}

          {% for method in @type.methods %}
            {% if method.name.starts_with?("dsl_before_write_") || method.name.starts_with?("dsl_after_write_") %}
              {% hook_attribute = method.name.gsub(/^dsl_(before|after)_write_/, "").stringify %}
              {% unless ATTRIBUTE_DECLS.any? { |decl| decl[:writable] && decl[:name].id.stringify == hook_attribute } %}
                {% raise "#{@type}: write hook `#{method.name}` names an attribute that is not declared writable" %}
              {% end %}
            {% end %}
          {% end %}

          {% for group in CONFLICT_DECLS %}
            {% for flag in group %}
              {% unless FEATURE_DECLS.any? { |feature| feature[:name] == flag } %}
                {% raise "#{@type}: conflicts names the undeclared feature :#{flag.id}" %}
              {% end %}
            {% end %}
          {% end %}

          {% for decl in ATTRIBUTE_DECLS + COMMAND_DECLS %}
            {% requires = decl[:requires] %}
            {% if requires %}
              {% raise "#{@type}: requires: needs feature declarations" unless has_features %}
              {% terms = requires.is_a?(ArrayLiteral) ? requires : [requires] %}
              {% for term in terms %}
                {% flags = term.is_a?(SymbolLiteral) ? [term] : (term.is_a?(NamedTupleLiteral) ? term.keys.map(&.symbolize) : nil) %}
                {% raise "#{@type}: requires: must be a feature symbol, a {feature: Bool} literal or an array of those, got #{requires}" unless flags %}
                {% for flag in flags %}
                  {% unless FEATURE_DECLS.any? { |feature| feature[:name] == flag } %}
                    {% raise "#{@type}: requires: names the undeclared feature :#{flag.id}" %}
                  {% end %}
                {% end %}
              {% end %}
            {% end %}
          {% end %}

          {% for decl in ATTRIBUTE_DECLS %}
            {% type = decl[:type].resolve %}
            {% kind = ::Matter::Cluster::DSL::TYPE_KINDS[type.stringify] %}
            {% if kind.nil? && type < ::Enum %}
              {% kind = type.annotation(::Flags) ? :bitmap : :enum %}
            {% elsif kind.nil? %}
              {% kind = type.stringify.starts_with?("Array(") ? :array : :struct %}
            {% end %}
            {% attribute_kinds[decl[:name]] = kind %}
          {% end %}

          # -- constructor -------------------------------------------------------

          {% unless @type.methods.any? { |method| method.name == "initialize" } %}
            def initialize(endpoint_id : ::Matter::DataType::EndpointNumber{% if has_features %}, @feature_map : Feature = Feature::None{% end %})
              super(endpoint_id, ::Matter::DataType::ClusterId.new(CLUSTER_ID))
            end
          {% end %}

          # -- features ----------------------------------------------------------

          {% if has_features %}
            @[Flags]
            enum Feature : UInt32
              {% for feature in FEATURE_DECLS %}
                {{ feature[:name].id.camelcase }} = 1_u32 << {{ feature[:bit] }}
              {% end %}
            end

            property feature_map : Feature = Feature::None

            protected def dsl_features : UInt32
              @feature_map.value
            end

            protected def dsl_validate_features : Nil
              {% for group in CONFLICT_DECLS %}
                {% for first, index in group %}
                  {% for other in (index + 1)...group.size %}
                    {% second = group[other] %}
                    if @feature_map.{{ first.id }}? && @feature_map.{{ second.id }}?
                      raise ArgumentError.new("#{name} cluster: {{ first.id.camelcase }} and {{ second.id.camelcase }} features cannot be combined")
                    end
                  {% end %}
                {% end %}
              {% end %}
            end
          {% end %}

          # -- feature gating ----------------------------------------------------

          {% for decl in ATTRIBUTE_DECLS %}
            {% if decl[:requires] %}
              private def dsl_attribute_{{ decl[:name].id }}_supported? : Bool
                dsl_feature_condition({{ decl[:requires] }})
              end
            {% end %}
          {% end %}

          {% for decl in implemented_commands %}
            {% if decl[:requires] %}
              private def dsl_command_{{ decl[:name].id }}_supported? : Bool
                dsl_feature_condition({{ decl[:requires] }})
              end
            {% end %}
          {% end %}

          protected def dsl_attribute_supported?(attribute_id : UInt32) : Bool
            {% if ATTRIBUTE_DECLS.empty? %}
              false
            {% else %}
              case attribute_id
              {% for decl in ATTRIBUTE_DECLS %}
                when ATTR_{{ decl[:name].id.upcase }}
                  {% if decl[:requires] %}dsl_attribute_{{ decl[:name].id }}_supported?{% else %}true{% end %}
              {% end %}
              else
                false
              end
            {% end %}
          end

          protected def dsl_command_supported?(command_id : UInt32) : Bool
            {% if implemented_commands.empty? %}
              false
            {% else %}
              case command_id
              {% for decl in implemented_commands %}
                when CMD_{{ decl[:name].id.upcase }}
                  {% if decl[:requires] %}dsl_command_{{ decl[:name].id }}_supported?{% else %}true{% end %}
              {% end %}
              else
                false
              end
            {% end %}
          end

          # -- metadata tables ---------------------------------------------------

          ATTRIBUTES = [
            {% for decl in ATTRIBUTE_DECLS %}
              {% kind = attribute_kinds[decl[:name]] %}
              {% if decl[:default].nil? %}
                {% default_value = nil %}
              {% elsif kind == :enum || kind == :bitmap %}
                {% default_value = "(#{decl[:default]}).value" %}
              {% elsif kind == :bool || kind == :string || kind == :octstr || kind == :array || kind == :struct %}
                {% default_value = "#{decl[:default]}" %}
              {% else %}
                {% default_value = "#{decl[:type]}.new(#{decl[:default]})" %}
              {% end %}
              ::Matter::Cluster::AttributeMetadata.new(
                id: ::Matter::DataType::AttributeId.new(ATTR_{{ decl[:name].id.upcase }}),
                name: {{ decl[:name].id.stringify.camelcase(lower: true) }},
                type: {{ kind }},
                writable: {{ decl[:writable] ? true : false }},
                optional: {{ decl[:optional] ? true : false }},
                fixed: {{ decl[:fixed] ? true : false }},
                default: {% if default_value %}::TLV::Serializable.serialize_value({{ default_value.id }}, nil){% else %}nil{% end %},
                min: {% if decl[:min].nil? %}nil{% else %}({{ decl[:min] }}).to_i64{% end %},
                max: {% if decl[:max].nil? %}nil{% else %}({{ decl[:max] }}).to_i64{% end %},
                access: ::Matter::Cluster::Definitions::AccessControl::EntryPrivilege::{{ (decl[:read_access] || :view).id.camelcase }},
                write_access: {% if decl[:write_access] %}::Matter::Cluster::Definitions::AccessControl::EntryPrivilege::{{ decl[:write_access].id.camelcase }}{% else %}nil{% end %},
                timed: {{ decl[:timed] ? true : false }},
                fabric_scoped: {{ decl[:fabric_scoped] ? true : false }},
                scene: {{ decl[:scene] ? true : false }},
                omit_changes: {{ decl[:omit_changes] ? true : false }},
              ),
            {% end %}
          ] of ::Matter::Cluster::AttributeMetadata
          ATTRIBUTES_BY_ID = ATTRIBUTES.to_h { |attribute| {attribute.id.id, attribute} }

          COMMANDS = [
            {% for decl in implemented_commands %}
              {% response_id = decl[:response_id] || decl[:id] %}
              ::Matter::Cluster::CommandMetadata.new(
                id: ::Matter::DataType::CommandId.new(CMD_{{ decl[:name].id.upcase }}),
                name: {{ decl[:name].id.stringify.camelcase(lower: true) }},
                optional: {{ decl[:optional] ? true : false }},
                access: ::Matter::Cluster::Definitions::AccessControl::EntryPrivilege::{{ (decl[:access] || :operate).id.camelcase }},
                response_id: {% if decl[:response] %}{{ (response_id.is_a?(NumberLiteral) && response_id.kind == :i32) ? "#{response_id}_u32".id : "(#{response_id}).to_u32".id }}{% else %}nil{% end %},
                timed: {{ decl[:timed] ? true : false }},
              ),
            {% end %}
          ] of ::Matter::Cluster::CommandMetadata
          COMMANDS_BY_ID = COMMANDS.to_h { |command| {command.id.id, command} }

          EVENTS = [
            {% for decl in EVENT_DECLS %}
              ::Matter::Cluster::EventMetadata.new(
                id: ::Matter::DataType::EventId.new(EVENT_{{ decl[:name].id.upcase }}),
                name: {{ decl[:name].id.stringify.camelcase(lower: true) }},
                priority: ::Matter::InteractionModel::EventPriority::{{ decl[:priority].id.camelcase }},
              ),
            {% end %}
          ] of ::Matter::Cluster::EventMetadata

          # The tables are shared by every instance; callers must not mutate them.
          def attributes : Array(::Matter::Cluster::AttributeMetadata)
            {% if ATTRIBUTE_DECLS.any? { |decl| decl[:requires] } %}
              ATTRIBUTES.select { |attribute| dsl_attribute_supported?(attribute.id.id) }
            {% else %}
              ATTRIBUTES
            {% end %}
          end

          def commands : Array(::Matter::Cluster::CommandMetadata)
            {% if implemented_commands.any? { |decl| decl[:requires] } %}
              COMMANDS.select { |command| dsl_command_supported?(command.id.id) }
            {% else %}
              COMMANDS
            {% end %}
          end

          def events : Array(::Matter::Cluster::EventMetadata)
            EVENTS
          end

          def get_attribute_metadata(attribute_id : UInt32) : ::Matter::Cluster::AttributeMetadata?
            ATTRIBUTES_BY_ID[attribute_id]? if dsl_attribute_supported?(attribute_id)
          end

          def get_command_metadata(command_id : UInt32) : ::Matter::Cluster::CommandMetadata?
            COMMANDS_BY_ID[command_id]? if dsl_command_supported?(command_id)
          end

          # -- reads -------------------------------------------------------------

          {% unless ATTRIBUTE_DECLS.empty? %}
            protected def dsl_read_attribute(attribute_id : UInt32, fabric_index : UInt8?) : ::Matter::InteractionModel::Status | ::TLV::Any
              case attribute_id
              {% for decl in ATTRIBUTE_DECLS %}
                {% kind = attribute_kinds[decl[:name]] %}
                when ATTR_{{ decl[:name].id.upcase }}
                  {% if decl[:requires] %}
                    return ::Matter::InteractionModel::Status.unsupported_attribute unless dsl_attribute_{{ decl[:name].id }}_supported?
                  {% end %}
                  {% if kind == :enum || kind == :bitmap %}
                    tlv(@{{ decl[:name].id }}.try(&.value))
                  {% else %}
                    tlv(@{{ decl[:name].id }})
                  {% end %}
              {% end %}
              else
                super
              end
            end
          {% end %}

          # -- writes ------------------------------------------------------------

          {% unless ATTRIBUTE_DECLS.empty? %}
            protected def dsl_write_attribute(attribute_id : UInt32, value : ::TLV::Any) : ::Matter::InteractionModel::Status
              case attribute_id
              {% for decl in ATTRIBUTE_DECLS %}
                {% kind = attribute_kinds[decl[:name]] %}
                when ATTR_{{ decl[:name].id.upcase }}
                  {% if decl[:requires] %}
                    return ::Matter::InteractionModel::Status.unsupported_attribute unless dsl_attribute_{{ decl[:name].id }}_supported?
                  {% end %}
                  {% if decl[:writable] %}
                    {% if decl[:nullable] %}
                      if value.value.nil?
                        %new_value{decl[:name]} = nil
                      else
                    {% end %}
                    {% if kind == :bool %}
                      %decoded{decl[:name]} = value.as_bool?
                    {% elsif kind == :uint8 %}
                      %decoded{decl[:name]} = narrow_u8?(value)
                    {% elsif kind == :int8 %}
                      %decoded{decl[:name]} = narrow_i8?(value)
                    {% elsif kind == :int16 || kind == :int32 || kind == :int64 %}
                      %decoded{decl[:name]} = signed?(value, {{ decl[:type] }})
                    {% elsif kind == :enum || kind == :bitmap %}
                      %raw{decl[:name]} = value.as_u64?
                      return ::Matter::InteractionModel::Status.invalid_data_type if %raw{decl[:name]}.nil?
                      %decoded{decl[:name]} = {{ decl[:type] }}.from_value?(%raw{decl[:name]})
                      return ::Matter::InteractionModel::Status.constraint_error if %decoded{decl[:name]}.nil?
                    {% else %}
                      %decoded{decl[:name]} = decode?(value, {{ decl[:type] }})
                    {% end %}
                    {% unless kind == :enum || kind == :bitmap %}
                      return ::Matter::InteractionModel::Status.invalid_data_type if %decoded{decl[:name]}.nil?
                    {% end %}
                    {% unless decl[:min].nil? %}
                      return ::Matter::InteractionModel::Status.constraint_error if %decoded{decl[:name]} < ({{ decl[:min] }})
                    {% end %}
                    {% unless decl[:max].nil? %}
                      return ::Matter::InteractionModel::Status.constraint_error if %decoded{decl[:name]} > ({{ decl[:max] }})
                    {% end %}
                    {% unless decl[:max_length].nil? %}
                      return ::Matter::InteractionModel::Status.constraint_error if %decoded{decl[:name]}.bytesize > ({{ decl[:max_length] }})
                    {% end %}
                    %new_value{decl[:name]} = %decoded{decl[:name]}
                    {% if decl[:nullable] %}
                      end
                    {% end %}
                    {% if @type.has_method?("dsl_before_write_#{decl[:name].id}") %}
                      if %rejection{decl[:name]} = dsl_before_write_{{ decl[:name].id }}(%new_value{decl[:name]})
                        return %rejection{decl[:name]}
                      end
                    {% end %}
                    self.{{ decl[:name].id }} = %new_value{decl[:name]}
                    {% if @type.has_method?("dsl_after_write_#{decl[:name].id}") %}
                      dsl_after_write_{{ decl[:name].id }}
                    {% end %}
                    ::Matter::InteractionModel::Status.success
                  {% else %}
                    ::Matter::InteractionModel::Status.unsupported_write
                  {% end %}
              {% end %}
              else
                super
              end
            end
          {% end %}

          # -- commands ----------------------------------------------------------

          {% unless implemented_commands.empty? %}
            protected def dsl_invoke_command(command_id : UInt32, fields : ::TLV::Any?) : ::Matter::InteractionModel::Status | ::Matter::Cluster::CommandResponse
              case command_id
              {% for decl in implemented_commands %}
                {% response_id = decl[:response_id] || decl[:id] %}
                when CMD_{{ decl[:name].id.upcase }}
                  {% if decl[:requires] %}
                    return ::Matter::InteractionModel::Status.unsupported_command unless dsl_command_{{ decl[:name].id }}_supported?
                  {% end %}
                  dsl_command_result(
                    {% if decl[:request] %}
                      {{ decl[:name].id }}(decode(fields, {{ decl[:request] }})),
                    {% else %}
                      {{ decl[:name].id }},
                    {% end %}
                    {{ (response_id.is_a?(NumberLiteral) && response_id.kind == :i32) ? "#{response_id}_u32".id : "(#{response_id}).to_u32".id }}
                  )
              {% end %}
              else
                super
              end
            end
          {% end %}

          # -- persistence -------------------------------------------------------

          {% unless persisted.empty? %}
            private struct PersistedState
              include ::Matter::Storage::Record

              {% for decl in persisted %}
                getter {{ decl[:name].id }} : {{ decl[:type] }}{{ "?".id if decl[:nullable] }}
              {% end %}
              getter data_version : UInt32
              # FeatureMap the state was saved under; absent in documents that
              # predate the stamp.
              getter features : UInt32?

              def initialize(
                {% for decl in persisted %}
                  @{{ decl[:name].id }} : {{ decl[:type] }}{{ "?".id if decl[:nullable] }},
                {% end %}
                @data_version : UInt32,
                @features : UInt32?,
              )
              end
            end

            def save_state : ::Matter::Storage::Document?
              PersistedState.new(
                {% for decl in persisted %}
                  {{ decl[:name].id }}: @{{ decl[:name].id }},
                {% end %}
                data_version: @data_version,
                features: dsl_features,
              ).to_document
            end

            # Restores the persisted attributes, ignoring a document saved under
            # a different FeatureMap or one that no longer decodes.
            def restore_state(document : ::Matter::Storage::Document) : Nil
              state = PersistedState.from_document(document)
              if (saved_features = state.features) && saved_features != dsl_features
                {{ log }}.info { "#{name}: persisted state was saved with FeatureMap 0x#{saved_features.to_s(16)}, now 0x#{dsl_features.to_s(16)}; starting fresh" }
                return
              end
              {% for decl in persisted %}
                @{{ decl[:name].id }} = state.{{ decl[:name].id }}
              {% end %}
              @data_version = state.data_version
            rescue ex
              {{ log }}.warn(exception: ex) { "#{name} restore_state failed; starting fresh" }
            end
          {% end %}
        {% end %}
      end
    end
  end
end
