# Phase 5 sub-plan: the cluster DSL

The seven-phase plan is in `tasks/todo.md`. Phases 0-4 are done on `refactor/cleanup` (2305 unit + 66 e2e
green). Status: **complete 2026-09-12; all gates green**.

## Context

Every concrete cluster repeats the same boilerplate by hand: constants, a `Feature` flags enum, a
`def attributes` array of metadata (291 `AttributeMetadata.new` sites), `def commands` (103), a
`read_attribute` case that feature-gates and encodes each field, a `handle_write_attribute` case that
decodes, range-checks, assigns and notifies, a `handle_command` dispatch, hand-built global attribute
lists in three competing styles, and a `PersistedState` record plus `save_state`/`restore_state` that
name every field three times. Measured: about 6,400 of the 17,800 cluster lines (36%) are mechanical.

The metadata is also mostly decorative: of ten `AttributeMetadata` fields only `id` and `access` drive
protocol behaviour, `writable?` and `default` drive a rarely reached fallback, and `name`, `type`, `min`,
`max`, `fixed`, `optional` are read by nothing. Constraints live as constructor raises rather than
declarations. `attributes` is rebuilt as a fresh array on every read, write and invoke.

matter.js (reference clone at `../spider-gazelle/claude-matter/matter.js`) generates its cluster files
from a spec model; its declaration vocabulary (`Attribute(id, schema, {persistent, writable, fixed,
scene, omitChanges, readAcl, writeAcl})`, `Command(id, request, responseId, response, {timed,
invokeAcl})`, feature components with `mandatoryIf`/`optionalIf`, global lists derived from the
declaration plus what is actually implemented) is the target semantics. The Crystal port can do one
thing matter.js cannot: check "mandatory command has a handler" at compile time.

Goal: one declarative DSL on `Cluster::Base` from which constants, typed accessors with change
notification, metadata tables, feature gating, read/write/command dispatch, global attribute lists,
validation and persistence are generated; every cluster migrated; definitions folded into their cluster;
the redundant `Cluster` suffix dropped from class names.

Rules carried forward: no magic numbers; every behaviour change gets a spec; no `puts` in specs; ameba
at zero; chip-tool e2e green at the end. Decisions to confirm are listed at the end.

## The DSL (target shape)

```crystal
class Matter::Cluster::OnOff < Matter::Cluster::Base
  cluster 0x0006, revision: 6

  feature :lighting,            bit: 0
  feature :dead_front_behavior, bit: 1
  feature :off_only,            bit: 2
  conflicts :lighting, :off_only
  conflicts :dead_front_behavior, :off_only

  enum StartUpOnOff : UInt8
    Off = 0; On = 1; Toggle = 2
  end

  struct OnWithTimedOffRequest
    include TLV::Serializable
    @[TLV::Field(tag: 0)] property on_off_control : UInt8
    @[TLV::Field(tag: 1)] property on_time : UInt16
    @[TLV::Field(tag: 2)] property off_wait_time : UInt16
  end

  attribute 0x0000, :on_off, Bool, default: false, persist: true, scene: true
  attribute 0x4000, :global_scene_control, Bool, default: true, requires: :lighting
  attribute 0x4001, :on_time, UInt16, default: 0, writable: true, requires: :lighting
  attribute 0x4002, :off_wait_time, UInt16, default: 0, writable: true, requires: :lighting
  attribute 0x4003, :start_up_on_off, StartUpOnOff, nullable: true, writable: true, persist: true,
    write_access: :manage, requires: :lighting

  command 0x00, :off
  command 0x01, :on, requires: {off_only: false}
  command 0x02, :toggle, requires: {off_only: false}
  command 0x40, :off_with_effect, request: OffWithEffectRequest, requires: :lighting
  command 0x42, :on_with_timed_off, request: OnWithTimedOffRequest, requires: :lighting

  def off : InteractionModel::Status
    self.on_off = false
    InteractionModel::Status.success
  end
  # ...
end
```

Vocabulary and what each generates:

- `cluster id, revision:` → `CLUSTER_ID`, `CLUSTER_REVISION`, `name` (from the class name), `self.cluster_id`.
- `feature :name, bit:` → `Feature` flags enum, `feature_map` property/constructor keyword, `feature_map_tlv`,
  `lighting?`-style predicates; `conflicts` → validated in `initialize` (raises `ArgumentError`, as
  `validate_features!` does today).
- `attribute id, :name, Type, ...` with `default:`, `writable:` (implies `persist:` unless overridden, per
  matter.js), `persist:`, `nullable:` (Crystal type `T?`, TLV null), `fixed:`, `optional:`, `requires:`
  (feature conformance: a symbol, a hash of flag → bool, or an array of such hashes ORed), `read_access:` /
  `write_access:` (`:view | :operate | :manage | :administer`), `min:`/`max:`, `max_length:`, `scene:`,
  `omit_changes:`, `timed:`, `fabric_scoped:`. Generates: `ATTR_NAME` constant (spec compatibility), a
  getter and a setter that skips no-op writes, bumps the version and notifies (`increment_version_and_notify`),
  an `on_name_changed(&block : Old, New -> Nil)` registrar, the `AttributeMetadata` entry (memoised once per
  class into a constant table, not rebuilt per call), the `read_attribute` branch (feature-gated, nullable
  aware, enums by value), the `handle_write_attribute` branch (decode via `decode?`/`narrow_*`/`signed?` per
  type, null handling, `min:`/`max:`/`max_length:` → `ConstraintError`, enum membership → `ConstraintError`,
  assign through the setter), and the persistence field.
- `command id, :name, request:, response:, response_id:, requires:, timed:, access:, optional:` → `CMD_NAME`,
  the `CommandMetadata` entry, and the `handle_command` branch that feature-gates, decodes `request:` with
  `decode(fields, Request)`, calls the handler method named `name` (`def off`, `def move_to_level(request)`),
  and wraps a returned struct as `CommandResponse` (status-only when `response:` is nil). A mandatory command
  without a handler method is a compile-time `{% raise %}` in `macro finished`.
- `event id, :name, priority:` → `EVENT_NAME`, `EventMetadata`. No emission path exists yet (Phase 6/7);
  keep the declaration so the metadata is real when it arrives.
- Global lists: `attribute_list_tlv`, `accepted_command_list_tlv`, `generated_command_list_tlv` derived from
  the tables filtered by the instance's feature map (and `optional:` elements only when implemented); the
  three hand-built styles (base auto-derive, `read_attribute` `when GLOBAL_*` + `build_*`, `*_tlv` overrides)
  collapse into this one.
- Persistence: `persist: true` fields generate a nested `PersistedState` `Storage::Record` struct (with
  `data_version`) and the `save_state`/`restore_state` pair including the existing "restore failed, start
  fresh" warning; the feature map is stamped into the document so a feature change invalidates stale state
  (matter.js `FEATURES_KEY`).
- Escape hatches: `before_write :name { |new| ... }` / `after_write :name { ... }` blocks for cross-attribute
  side effects (fan mode ↔ percent sync, on/off global scene control); a hand-written `read_attribute`/
  `handle_write_attribute`/`handle_command` override still works and falls through to `super` for the
  generated branches (descriptor's computed lists, operational credentials' fabric-scoped reads).
- Internals: declarations accumulate into class-level `{% %}` arrays inside the class body; a `macro finished`
  emitted by `Base`'s `macro inherited` generates the methods (the `cluster.cr:111` lazy-constant pattern
  and `storage/record.cr`'s `{% verbatim %}`/annotation style are the house precedents). Constants defined
  by the macros keep the existing `ATTR_*`/`CMD_*` names and values so specs and examples keep compiling.

## Step 1: DSL core on `Cluster::Base`, proven on three clusters

- `src/matter/cluster/dsl.cr` (required by `cluster.cr`): the macros above; `Cluster::Base` keeps its
  runtime contract (`read_attribute`/`write_attribute`/`invoke_command`, decode helpers, versioning,
  persistence hooks) and gains the generated-table lookups (`ATTRIBUTES`, `COMMANDS`, `EVENTS` constants;
  `attributes`/`commands`/`events` return them filtered by feature map; `get_attribute_metadata` is a hash
  lookup).
- Migrate `boolean_state`, `on_off`, `level_control` (floor, features + persistence, constraints + nullables)
  and keep every existing spec for them green unchanged, then delete the code the DSL replaced. On/Off's
  writes switch from `increment_version` to `increment_version_and_notify` (a fix; update the subscription
  count in its spec).
- `spec/cluster/dsl_spec.cr`: a spec-local cluster exercising every keyword: generated constants, setter
  no-op/notify/callback, nullable round trip, `requires:` gating of reads/writes/commands/lists, `conflicts`,
  `min`/`max`/`max_length`/enum → `ConstraintError`, wrong type → `InvalidDataType`, `write_access` reaching
  `AttributeMetadata#access`, persistence round trip with feature-map stamp, `optional:` element excluded
  from lists when unimplemented, mandatory command without a handler fails to compile (a `crystal build`
  of a fixture file asserted to fail, as `spec/storage/record_spec.cr` does for unsupported types).

## Step 2: migrate the remaining clusters

Smallest first, each in its own commit with its spec kept green: `fixed_label`, `user_label`,
`identify`, the six measurement clusters, `time_format_localization`, `descriptor` (computed lists via the
override escape hatch), `power_source`, `diagnostics` clusters, `icd_management`, `ota_requestor`,
`diagnostic_logs`, `bridged_device_basic_information`, `basic_information`, `occupancy_sensing`,
`fan_control` (`after_write` sync), `thermostat`, `window_covering`, `color_control`, `groups`,
`scenes_management`, `group_key_management`, `access_control`, `door_lock`. The four facade clusters
(`general_commissioning`, `operational_credentials`, `administrator_commissioning`, `network_commissioning`)
migrate their attribute/command declarations but keep their hand-written handlers; Phase 6 restructures
them. Along the way: named setters the examples call (`update_temperature`, `update_state`) stay as thin
aliases; the 27 `on_*_changed` registrars keep their current arity via an explicit `callback:` arity option
where the generated `(old, new)` form would break an example; `CLUSTER_REVISION` becomes explicit in every
cluster (`cluster_revision_spec.cr` updated with the real spec revisions).

## Step 3: definitions folded in, names, registry

- Each `definitions/<x>.cr` moves into its cluster class (`Matter::Cluster::OnOff::StartUpOnOff`); files over
  ~300 lines split into `cluster/<name>/types.cr` required by the cluster file. `definitions/access_control.cr`'s
  `EntryPrivilege` moves to `interaction_model/access.cr` (Base and the IM handler depend on it; folding it
  into the cluster would form a require cycle). External references (`controller/commissioning/commissioner.cr`,
  `examples/chip-tool/commands/operationalcredentials.cr`, five specs) updated. `cluster/definitions/` deleted.
- Rename `Matter::Cluster::XCluster` → `Matter::Cluster::X` (36 classes, ~4,000 references, mechanical per
  class; the spec-local fakes `RaisingCluster`, `UnsupportedCluster` (also a status code), `BrokenTlvCluster`
  must not be touched). File names drop the `_cluster` suffix. Old names are not kept.
- `Cluster::Registry`: `macro inherited` registers `CLUSTER_ID → class` lazily so `Cluster.for(id)` exists for
  Phase 6's endpoint model and the controller; the 36 hand-maintained `require` lines in `cluster.cr` remain
  (explicit requires are a Phase 1 decision).
- Wire compatibility: the unified global lists change attribute-list ordering for on_off, descriptor and
  level_control; `descriptor_cluster_encoding_spec.cr`, `on_off_composition_spec.cr`,
  `cluster_composition_spec.cr` re-baselined, and `./test` plus the iOS notes in
  `docs/matter_requirements_for_apple_home.md` checked for ordering assumptions.

## Verification

| Gate | When |
|---|---|
| format, ameba exit 0 | every commit |
| the migrated cluster's specs + `dsl_spec` | every cluster commit |
| `crystal spec --error-trace` via subagent; build all examples + chip-tool | after each step |
| `./test` (unit + e2e incl. restarts, Groups/Colour/WindowCovering) | end of Steps 1, 2, 3 |
| line count of `src/matter/cluster/` before/after; `grep -rn "AttributeMetadata.new\|CommandMetadata.new" src/matter/cluster` returns only `dsl.cr` | end |
| iOS pairing smoke test by the user (attribute-list ordering changed) | end |

## Decisions to confirm

1. `writable:` implies `persist:` (matter.js rule) unless `persist: false` is given.
2. `CLUSTER_REVISION` becomes mandatory in every cluster with the real spec value (25 clusters currently
   inherit 1).
3. Class rename to `Matter::Cluster::OnOff` with file rename, no aliases for the old names.
4. `EntryPrivilege` moves to `interaction_model/`.
