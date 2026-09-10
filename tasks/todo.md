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
- [ ] Explicit require tree; `src/matter/controller.cr` entrypoint
- [ ] Delete dead islands (managers, utilities, logger, schema, empty classes, 30 unused definitions)
- [ ] Consolidate mDNS on `Responder`; delete legacy stack; scanner under controller
- [ ] Fix collisions (`CLUSTER_REVISION`, `FailsafeContext`, `SessionManager`, `DeviceType`)
- [ ] Fix bugs (on_off duplicate tags, redaction regex, node_id bounds, memory backend live hash)
- [ ] Spec reorg tranche 1
- [ ] `./bin/ameba` clean repo-wide (250 pre-existing findings on develop)

## Phase 2: Foundations
- [ ] `Matter::Error` hierarchy
- [ ] `Status` factory methods
- [ ] Log source normalisation
- [ ] `datatype/*` as structs, `NodeId` serializable, `to_s` overrides
- [ ] Silent rescues log or re-raise

## Phase 3: Storage
- [ ] `Storage::Backend` interface (collections, documents, transactions, schema_version)
- [ ] Memory / JsonFile / YamlFile backends over shared `FileBackend`; contract spec
- [ ] `Storage::Record` macro mixin; replace all hand-rolled to_h/PersistedState
- [ ] Layering: storage depends on nothing; persistence services in protocol/device
- [ ] Dirty tracking + debounced save; `Device::Base.new(storage:)`
- [ ] Controller state on the same backend
- [ ] `storage/legacy/json_import.cr`; `Storage::Migrator` + CLI
- [ ] `./test` with YAML examples; manual legacy import + reconnect

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

## Review
(filled in as phases complete)
