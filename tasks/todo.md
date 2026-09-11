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
- [x] Step 2: Fabric/session/subscription/cluster records; `Device::Persistence` (dirty tracking, debounce,
      identity, app documents, orphan cleanup, `reset!`); `Device::Base.new(storage:)`; examples on YAML;
      controller state on a backend; old storage classes deleted
- [x] Step 3: `storage/legacy/` importer + fixture spec; restart spec + e2e restart; README storage section;
      manual import of a real device file
- [x] `./test` green at the end (2268 unit + 63 e2e incl. two device restarts)

## Phase 4: Wire codec and cluster boundary
Detailed implementation and verification plan: [phase4-plan.md](phase4-plan.md).
- [x] Recover and review detailed phase 4 plan; inspect existing matter.js reference
- [x] `Session::SecureMessage.encode/decode`; single AAD definition; single `PacketHeader` representation
- [x] One message counter implementation
- [x] Cluster contract on `TLV::Any`; delete raw-bytes helpers and per-cluster encode_* helpers
- [x] Replace manual TLV tag indexing with serializable structs
- [x] Fix groups/scenes/color_control/window_covering raw binary handling
- [x] `DERCodec` keep-or-delete decision
- [x] `./test`
- [x] Review follow-up commit 1: fixes (enum mismatch → InvalidCommand, UDP guard on replay spec, decode
      refuses missing header bytes, LevelControl null writes, Groups constraint errors, secure message trace
      logs, MRP stale doc comment)
- [x] Review follow-up commit 2: nits (MessageType enum, read_attribute spec sweep, nonce helper, dead
      counter accessors, Scenes TLV::Any field sets, literal → constant, replace_acl rescue narrowing,
      colour typo, counter specs moved, signed→unsigned width assertion)

## Phase 5: Cluster DSL
Detailed plan: [phase5-plan.md](phase5-plan.md).
- [x] Step 1: DSL core (`cluster`/`feature`/`conflicts`/`attribute`/`command`/`event` macros, generated
      accessors, tables, dispatch, global lists, validation, persistence) proven on boolean_state, on_off,
      level_control; `spec/cluster/dsl_spec.cr` (boolean_state 64→31, on_off 563→184, level_control
      720→173 lines; `AttributeMetadata#write_access` split from the read privilege)
- [x] Step 2: migrate the remaining 33 clusters smallest first (facade clusters: declarations only)
- [x] Step 2b: close the DSL gaps the migration reported and delete the cluster workarounds
      - [x] `computed: true` attributes (reader `name`/`name(fabric_index)`; writable ones call `name=`)
      - [x] `present_if:` presence-gated attributes (predicate method, or `!@ivar.nil?` for a nullable attribute)
      - [x] `event ... requires:`; `before_write` may return a replacement value; `cluster ... name:`
      - [x] `CMD_<NAME>_RESPONSE` constants; `persist_state: false`; `command ... handler:`
      - [x] `Base#invoke_command` sets `request_*` (duck typing removed); `requires:` accepts a constant
      - [x] DSL rules documented at the top of `dsl.cr`; legacy user_label key `label_list`
      - [x] workarounds removed from the 20 clusters; full suite, builds, format, ameba green
- [x] Step 3: definitions folded into clusters, `EntryPrivilege` to interaction_model, class/file rename
      (`Cluster::OnOff`), `Cluster::Registry`, global-list ordering re-baselined
- [x] `./test` green at the end (2026-09-12: 2394 unit + 66 e2e incl. restarts and the new Groups/Colour/
      WindowCovering cases, device validation 20/20); iOS smoke test by the user still outstanding

## Phase 6: Device model and protocol decomposition
Detailed plan: [phase6-plan.md](phase6-plan.md).
- [ ] Step 1: `Node`/`Endpoint` own the clusters (flat index, device-type validation, descriptor + scene
      wiring moved off `Device::Base`, dead second IM path deleted)
- [ ] Step 2: decompose `MessageHandler` (`MrpCache`, `SessionRegistry` owning the lock,
      `SubscriptionManager` with one chunk ladder, `SecureChannel` keyed by exchange, `InteractionRouter`);
      target <= 600 lines
- [ ] Step 3: `commissioning/` module (cycle broken) + Failsafe/Window/Credential services; facade clusters
      become thin DSL fronts
- [ ] Step 4: CASE deduplicated; event journal, emission, read and subscription path
- [ ] Step 5: `Matter::Device` DSL + `examples/support/`; all ten examples rewritten
- [ ] `./test` green at steps 1, 2, 3, 5; iOS smoke test by the user

## Phase 7: Close out
Detailed plan: [phase7-plan.md](phase7-plan.md).
- [ ] Step 1: spec tranche 2 (`build` helper + `endpoint(n)` sweep, split the eleven 600+ line specs,
      specs for the Phase 6 objects, resolve the one true pending)
- [ ] Step 2: `CHANGELOG.md`, README architecture/controller/DSL sections, `docs/architecture.md`,
      `AGENTS.md` pointer, `shard.yml` 0.2.0
- [ ] Step 3: CI build job for every example + storage CLI + e2e specs; final gates; PR to develop

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

### Phase 3 (2026-09-10)
- `src/matter/storage/` depends on nothing: `Backend` (collections → ids → documents, transactions,
  `destroy!`), `Memory`, `YamlFile`, `JsonFile` over one `FileBackend` (atomic write, fsync, mutex, corrupt
  file preserved, schema version), `Record` macro (`to_document`/`from_document` from ivars), `Migrator` and
  `bin/matter-storage migrate|inspect`. Human-readable files; `Bytes` and `Time` first-class; `UInt64`
  above `Int64::MAX` survives (the old loader silently factory-reset on such fabric ids).
- Fabrics, sessions, subscriptions, every cluster state, device identity, bridge documents and controller
  state are `Record`s; one document per fabric/session/subscription; hand-rolled `to_h`, `PersistedState`
  JSON structs, the scenes shadow-field hack, `Persistence.redact` and `Storage::Manager` are gone.
- `Device::Persistence` owns the backend, fabric table, protocol persistence, identity, app documents,
  orphan cleanup and `reset!`; `Device::Base.new(storage:)` replaces `build_storage_manager`. Writes are
  debounced (250 ms) through `Debouncer` into one transaction; `increment_version` is the dirty chokepoint
  (GroupKeyManagement now bumps it). Cluster state survives a crash, not just a clean shutdown.
- Legacy importer isolated in `storage/legacy/` (`--from legacy:<file>`), verified against a real device
  file; fixture-based import + boot spec caught an integer-vs-name enum mismatch and fixed it.
- Restart coverage that never existed: unit restart spec (crash and flush paths, `reset!`) and in-place
  container restarts in e2e (marker file on the shared log volume) for the switch and door lock.

| Metric | after Phase 2 | after Phase 3 |
|---|---|---|
| unit examples | 2140 | 2268 |
| e2e examples | 61 | 63 |
| storage formats | JSON-in-JSON KV | YAML / JSON / memory documents |

### Phase 4 (2026-09-10)
- `Session::SecureMessage.encode/decode` centralizes encryption, nonce construction and framing;
  authenticated data is the complete received/encoded header, including optional node IDs.
  `PacketHeader` computes flag bytes from its fields; plain messages use `encode_message`.
- `SecureContext` owns the shared counter implementation. Reordered authenticated datagrams are
  accepted within the receive window; failed authentication cannot advance counters or cancel
  cleanup. Counter zero, exhaustion, persisted watermarks and cached duplicate ACKs have regressions.
- Cluster reads, writes, commands, defaults and responses use `TLV::Any`; IM/endpoint/subscription
  routing no longer strips scalar types or reparses cluster output. Raw width helpers, the null
  sentinel and per-cluster encoders are removed. Width compatibility and UTF-8 validation remain.
  CASE WriteRequest regressions cover fabric-scoped ACL/extension replacement, including assigning
  fabric indices back into value-type records after deserialization.
- Groups, ColorControl and WindowCovering consume annotated request structs. The real TLV requests
  fail against phase 3 and pass here. Scene extension fields survive Add/View/Recall and persistence,
  including numeric OnOff scene booleans. Fan Step and signed Thermostat commands now reach handlers
  through the same IM dispatch path as other clusters.
- Pake3, StatusResponse, TimedRequest and RemoveFabric parsing use structs. DER is limited to the
  certification declaration encoder; dead decoding/X.509 helpers are gone. DAC/PAI identifiers use
  OpenSSL's extension generation with a version-aware context binding and byte-value assertions.
- The level-control example adds color-light and window-covering endpoints. New official chip-tool
  cases cover group membership, hue/temperature and lift commands plus attribute reads/writes.
  The test harness builds image targets sequentially after a shared-layer Docker export race was
  reproduced; no cache pruning was needed.
- Final gates: `crystal tool format --check`, `./bin/ameba` (344 files, zero findings),
  `crystal spec -v --error-trace` via subagent (2287 examples, zero failures/errors, one pre-existing
  pending vector assertion), and ordinary `./test` exit 0 (2287 unit + 66 e2e, including two restarts
  and device validation 20/20). All ten devices + validation helper, in-repo chip-tool and storage CLI
  compile. `git diff --check` is clean.
- Verification logs: `tmp/phase4-unit.log`, `tmp/phase4-e2e.log`, `tmp/phase4-ameba.log`;
  final container logs: `tmp/e2e/logs/compose-20260910-233725.log`.

| Metric | after Phase 3 | after Phase 4 |
|---|---|---|
| unit examples | 2268 | 2287 |
| e2e examples | 63 | 66 |
| cluster wire boundary | encoded/raw Bytes | TLV::Any |
| ameba findings | 0 | 0 |

### Phase 5 (2026-09-11)
- `src/matter/cluster/dsl.cr`: `cluster`, `feature`/`conflicts`, `attribute`, `command`, `event`,
  `before_write`/`after_write` macros generate constants, typed accessors with change notification and
  callbacks, memoised metadata tables, feature-gated read/write/command dispatch, validation to
  `ConstraintError`/`InvalidDataType`, the unified global attribute lists, and persistence records with a
  feature-map stamp. Keywords added after migration feedback: `computed:`, `present_if:`, `event requires:`,
  `before_write` value replacement, `name:`, `handler:`, generated `CMD_*_RESPONSE`, `persist_state: false`,
  constant `requires:`. A mandatory command without a handler, or a computed attribute without a reader,
  is a compile error.
- All 35 clusters migrated; no `read_attribute` override remains, one intentional `handle_write_attribute`
  override (OTA). Definitions folded into their cluster classes (large ones under `cluster/<name>/types.cr`;
  wire structs that collide with domain types live in a nested `Tlv` module); `EntryPrivilege` moved to
  `interaction_model/access.cr`; `cluster/definitions/` deleted.
- Classes and files renamed `Matter::Cluster::OnOff` / `cluster/on_off.cr` (35 classes, ~4,100 refs);
  `Cluster::Registry` maps ids to classes at compile time.
- Every cluster now declares its real spec revision; enums use `UInt8` bases so they encode as enum8;
  CO2 reports a real feature map; GKM commands became wire-reachable; ACL/Extension reads require Administer.

| Metric | after Phase 4 | after Phase 5 |
|---|---|---|
| cluster implementation lines (excl. dsl/base/registry/utils) | ~17,750 | ~14,000 (types files included) |
| `AttributeMetadata.new` / `CommandMetadata.new` outside dsl.cr | 291 / 103 | 0 / 0 |
| unit examples | 2305 | 2394 |

### Phase 5 Step 2b (2026-09-11)
- DSL: `computed:` (reader `name` / `name(fabric_index)`, writer `name=` when writable),
  `present_if:`, `event ... requires:`, `before_write` value replacement, `cluster ... name:` /
  `persist_state: false`, `command ... handler:`, generated `CMD_<NAME>_RESPONSE`, `requires:`
  constants, `Base#invoke_command` populating `request_*` (duck typing gone); 20 new
  `dsl_spec` examples plus a missing-reader compile fixture.
- Workarounds removed from 21 cluster files (+196/-485 lines): every `read_attribute` override,
  the ACL/GKM/basic_information `handle_write_attribute` overrides, the bridged/power_source
  `macro finished` redefinitions and `attribute_present?` tables, the per-attribute
  `persist: false` on hand-persisted clusters, OTA's `name`, the door_lock/general_commissioning
  ameba disables, GKM's ad-hoc `fabric_index`, OC's `session_id` / `session_fabric_index`.
- Behaviour normalised: an optional attribute without a value is absent from AttributeList and
  rejects writes (five sensor specs now construct with the value); undecodable ACL/Extension
  writes answer InvalidDataType like every other DSL write; CurrentFabricIndex has no setter.
- Legacy import writes user labels under `label_list`; the boot spec restores them.
- Gates: full suite 2356 examples / 0 failures / 1 pre-existing pending; controller, chip-tool
  and all ten example devices compile; `crystal tool format --check` and `./bin/ameba`
  (348 files, 0 findings) clean.
