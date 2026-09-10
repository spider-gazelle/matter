# Refactor: `refactor/cleanup`

High-level plan (full detail in the session plan; each phase gets a sub-plan when started).
Gates for every phase: `crystal tool format --check`, `./bin/ameba`, `crystal spec` (via subagent).
`./test` (docker e2e) at the end of phases 0, 1, 3, 4, 5, 6, 7.

## Decisions
- SQL: interface + memory/JSON/YAML backends here; SQL adapter is a later `matter-storage-sql` shard.
- Legacy JSON storage: one-shot importer isolated in `src/matter/storage/legacy/` (to be deleted later);
  permanent `Storage::Migrator` + CLI for moving data between backends.
- Controller stays in-repo behind explicit `require "matter/controller"`.
- Delete all dead code.

## Conventions
- Singular dirs; classes named for the thing (`Cluster::OnOff`, `Fabric::Table`).
- Explicit require tree, no `**` globs. `require "matter"` = device library only.
- `Matter::Error` hierarchy; no bare string raises; every rescue logs or re-raises.
- `InteractionModel::Status` factory methods.
- Log sources mirror paths (`matter.session.pase`).
- `ATTR_`/`CMD_`/`EVENT_`; `CLUSTER_REVISION` is always the revision value.
- TLV via `@[TLV::Field]` structs only; persistence via `Storage::Document` only; wire values cross the
  cluster boundary as `TLV::Any`.

## Phase 0: Branch and safety net
- [x] Create branch, add this file
- [x] Byte-exact assertions: `spec/interaction_model/report_data_matterjs_vector_spec.cr` (merged the two
      "exact" specs; encode match stays pending because AttributePath uses fixed-size ints for iOS),
      `spec/message_codec_compatibility_spec.cr` re-encodes both matter.js vectors byte-for-byte
- [x] `spec/support/cluster_helpers.cr` + `boolean_state_spec.cr` converted as the demonstration
- [x] Bug found by the new specs and fixed: destination group id was encoded as 4 bytes (`message_codec.cr:166`)
- [x] e2e harness: build the device image once, lock the compiler cache mount (parallel build race)
- [x] Baseline `./test` green on branch tip (2026-09-10: 2133 unit + 61 e2e examples, 0 failures)

## Phase 1: Prune, explicit requires, naming collisions
Rule (user, applies to all phases): no magic numbers; named constants/enums, enums preferred.
- [x] Step 1: explicit require tree (per-subsystem aggregators), `src/matter/controller.cr` entrypoint
- [x] Step 2: delete dead code (managers, utilities, logger, schema, empty stubs, 32 unused definitions,
      legacy Scenes 0x0005, dead methods, failsafe rollback params)
- [x] Step 3: one device-type registry (`Matter::DeviceType`, u32); drop `DeviceTypes`
- [x] Step 4: mDNS on `Responder` only: CommissioningMode move, legacy branch out of AdministratorCommissioning,
      subtype PTR query answers + announcement burst in Responder, basic-window discriminator fix,
      port legacy spec assertions, delete legacy stack, scanner → `Controller::Scanner`
- [x] Step 5a: collisions (`CLUSTER_REVISION` = revision value + base macro, `PendingCredentials`)
- [x] Step 5b: bugs (redaction regex, node id ranges, storage backend consistency, fabric table load,
      duplicate `window_open?`, enum aliases) each with a spec
- [x] Step 5c: `./bin/ameba` exits 0 repo-wide (307 files, 0 findings; was 250)
- [x] Step 6: spec reorg tranche 1 (mirror src, `spec/compatibility/`, deletions, merges, splits)
- [x] `./test` green after step 4 and at the end; line-count report in Review

## Phase 2: Foundations
- [x] Step A: `to_s(io)` fixes, `Status` factory macro + rewrite of 338 sites, local shorthands removed,
      interaction-model/codec constants, shared TLV null marker, `Matter::Hex`
- [x] Step B: datatype wrappers as structs via one macro (equality, TLV, `to_s`), dead ids deleted,
      NodeId/CAT/FabricIndex constants
- [x] Step C: `Matter::Error` hierarchy; all bare-string raises converted; invoke/write backstop maps
      exceptions to statuses; wire-reachable raises become statuses
- [x] Step D: silent rescues log; corrupt storage file renamed not wiped; CASE test-compat fallback removed;
      hot-path log levels; `Network.local_ip_addresses`
- [x] Step E: log sources mirror paths; namespace `Log` fallbacks; examples read `MATTER_LOG`
- [x] `./test` green at the end (2140 unit + 61 e2e, device validation 20/20)

## Phase 3: Storage
Document model: `Type = Nil | Bool | Int64 | UInt64 | Float64 | String | Bytes | Time | Array | Hash`;
collections `fabrics`, `sessions`, `subscriptions`, `device`, `clusters`, `app`, `meta` (schema in plan).
- [x] Step 1: dependency-free core: `Backend` interface, Memory/YamlFile/JsonFile over `FileBackend`,
      `Record` macro, `Migrator` + `bin/matter-storage` CLI, shared backend contract spec
- [ ] Step 2: Fabric/session/subscription/cluster records; `Device::Persistence` (dirty tracking, debounce,
      identity, app documents, orphan cleanup, `reset!`); `Device::Base.new(storage:)`; examples on YAML;
      controller state on a backend; old storage classes deleted
- [ ] Step 3: `storage/legacy/` importer + fixture spec; restart spec + e2e restart; README storage section;
      manual import of a real device file
- [ ] `./test` green at the end

## Phase 4: Wire codec and cluster boundary
- [ ] `SecureMessageCodec` encode/decode; single AAD definition; single `PacketHeader` representation
- [ ] One message counter implementation
- [ ] Cluster contract on `TLV::Any`; delete raw-bytes helpers and per-cluster encode_* helpers
- [ ] Replace manual TLV tag indexing with serializable structs
- [ ] Fix groups/scenes/color_control/window_covering raw binary handling
- [ ] `DERCodec` keep-or-delete decision
- [ ] `./test`

## Phase 5: Cluster DSL
- [ ] Macros on `Cluster::Base` (cluster/feature/attribute/command/event, persist)
- [ ] Fold definitions into clusters; migrate smallest first
- [ ] Fill stubbed handlers
- [ ] `./test`

## Phase 6: Device model and protocol decomposition
- [ ] Endpoint/Node model + `ClusterRegistry`
- [ ] Split `MessageHandler` (SessionRegistry, SubscriptionManager, SecureChannelHandler, InteractionRouter, MRP)
- [ ] `commissioning/` module; `FailsafeParticipant`; facade clusters over services
- [ ] Device DSL; rewrite examples and `device_validation.cr`
- [ ] Deduplicate CASE
- [ ] `./test`; iOS smoke test

## Phase 7: Close out
- [ ] Spec reorg tranche 2
- [ ] Docs, changelog, CLAUDE.md
- [ ] Full gates; PR to develop

## Phase 3 Step 2: consumers onto `Storage::Backend`, delete the legacy layer
- [x] `Matter::Debouncer` (single fiber, trigger/flush/cancel) shared by cluster/fabric/session writes
- [x] `Fabric` is a `Record` (Time fields, `cats` as `[u32]`, key split into private/public Bytes, key rebuilt lazily);
      `FabricTable.new(backend)` one document per fabric; `mark_fabric_used` debounced when a debouncer is attached
- [x] `SessionRecord` / `SubscriptionRecord` (+ `AttributePathRecord`); `Protocol::Persistence::StorageBackend`
      per-document `sessions`/`subscriptions`, `device/counters`; redaction helpers deleted
- [x] `Cluster::Base#save_state : Document?` / `restore_state(Document)`, `persistence_key` = `"<ep>-<cluster>"`,
      `on_version_changed`, `increment_version` the only bump; every `PersistedState` a `Record`;
      `GroupKeyManagementCluster` bumps the version on every mutation
- [x] `Device::Persistence` (identity, clusters, app documents, flush/close/reset!, debounced dirty writes)
- [x] `Device::Base.new(storage, ...)`, `persistence` getter, `remove_endpoint` forgets clusters, examples on
      `YamlFile` with `persistence.reset!`; sensors gain the reset command; bridge state as app documents
- [x] `Controller::State` records; `StateStore.new(backend)`; chip-tool context owns the store
- [x] Delete `Storage::Base`/`MemoryBackend`/`JsonFileBackend`/`Manager`/`LegacyType` and their specs
- [x] Gates: full spec (2234 examples, 0 failures, 1 pending), `--no-codegen` builds (library, controller, chip-tool, storage CLI, ten examples),
      format, ameba on touched files

## Review

### Phase 0 (2026-09-10)
- Byte-exact codec specs found a real bug: destination group id encoded as 4 bytes. Fixed.
- Shared cluster spec helpers; e2e harness build race fixed.

### Phase 1 (2026-09-10)
- `src/matter.cr` is an explicit layered require tree with one aggregator per subsystem;
  `require "matter/controller"` is a separate entrypoint (the device library is controller-free).
- Deleted: dead managers/stubs/utilities/logger/schema, 32 unused cluster definitions, legacy Scenes
  cluster (0x0005), legacy mDNS stack (advertiser/server/socket/service_description), the u16
  `DeviceTypes` registry, uncalled `FabricTable#export/#import`, dead storage/persistence methods.
- mDNS: `Responder` now answers subtype PTR queries (`_L`, `_S`, `_T`, `_V`, `_CM`) and instance
  queries, sends a 3-packet announcement burst, and a basic commissioning window advertises the device
  discriminator (was 0). Scanner is `Controller::Scanner`.
- Collisions: `CLUSTER_REVISION` is the revision value everywhere (base macro generates
  `cluster_revision`); `PendingCredentials` replaces the nested `FailsafeContext`; one `DeviceType`.
- Bugs fixed with specs: persistence redaction regex (keys were logged unredacted), node id range check
  and group node id byte order, memory backend leaking its live hash, fabric table load wiping the table on
  one bad entry, duplicate `window_open?`, enum alias conflicts.
- `spec/` mirrors `src/`; `spec/compatibility/` holds the matter.js/iPhone golden-vector specs; 6 scratch
  specs deleted, 2 duplicate pairs merged, no `puts` left in specs; `MATTER_SPEC_LOG` controls spec logging.
- Lint: ameba clean repo-wide.

| Metric | develop | after Phase 1 |
|---|---|---|
| `src/` lines / files | 46,886 / 176 | 40,897 / 139 |
| `spec/` lines / files | 40,208 / 138 | 38,102 / 132 |
| top-level spec files | 62 | 10 |
| unit examples | 2133 | 2034 (duplicates removed, ~60 added) |
| e2e examples | 61 | 61 |
| ameba findings | 250 | 0 |

### Phase 2 (2026-09-10)
- `Matter::Error` hierarchy (`error.cr`): Codec, Crypto/Authentication, Certificate, Storage, Session,
  Protocol/Timeout, Commissioning, Transport, Cluster(status). No bare-string raises remain in `src/`.
- Exceptions are mapped to IM statuses at the cluster boundary (`invoke_command`, `write_attribute`,
  `IMHandler.safe_invoke_command`); a hostile payload can no longer make the device drop the exchange.
  Cluster-specific status codes now reach the wire (`StatusIB.cluster_status`).
- Wire-reachable raises became statuses: network commissioning OutOfRange, group key management
  ResourceExhausted/NotFound/ConstraintError, admin commissioning ConstraintError/Busy/PAKE codes.
- Silent rescues log with context; a corrupt storage file is renamed `.corrupt-<ts>` instead of wiped;
  identity loads log storage failures; the CASE Sigma3 "test compatibility" fallback is gone (handshake
  fails closed on decrypt/signature failure); hot-path logs are debug without payload dumps.
- `Status` factories (`Status.success`, `.unsupported_attribute`, `.cluster_failure(code)`), 338 literal
  constructions rewritten, four local shorthand sets deleted; `to_s(io)` on statuses and paths (were dead);
  protocol constants (IM revision/tag, codec shifts/masks/offsets, TLV null marker); `Matter::Hex`.
- Datatype wrappers are value structs from one `define_id` macro (equality, hash, TLV, `to_s`); `brand`
  gone; `FabricId`/`VendorId`/`SubjectId` deleted; NodeId/CAT/FabricIndex constants.
- Log sources mirror the file tree with namespace fallbacks; `spec/log_sources_spec.cr` fails on drift;
  `MATTER_LOG` for examples; `Matter::Network.local_ip_addresses` replaces ten copies in the examples.

| Metric | after Phase 1 | after Phase 2 |
|---|---|---|
| `src/` lines / files | 40,897 / 139 | 41,275 / 140 |
| unit examples | 2034 | 2140 |
| bare-string raises in src | 66 | 0 |
