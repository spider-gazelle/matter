# Phase 7 sub-plan: close out

The seven-phase plan is in `tasks/todo.md`. Phase 6 detail is in `tasks/phase6-plan.md`.
Status: **approved 2026-09-12**.

## Context

97 commits and a 450-file diff separate the branch from `develop`. The spec tree mirrors `src/` but the
`endpoint(n)` helper was adopted 63 times against 715 direct constructions, eleven specs exceed 600 lines,
and 830 lines test dead code (fixed by Phase 6 Step 1). Docs are accurate but incomplete (no controller
section, no changelog, `CLAUDE.md` and `AGENTS.md` are byte-identical copies, the chip-tool README says
`controller.json`). CI compiles only one example; nine examples, the storage CLI and the e2e specs are never
compiled in CI, which is how a 450-file refactor could have broken them silently.

## Step 1: spec tranche 2

- `spec/support/cluster_helpers.cr` gains `build(Klass, endpoint = 1, **kwargs)`; mechanical sweep of the 715
  `EndpointNumber.new` sites to `endpoint(n)`/`build`; per-file shared setup for the eight worst offenders.
- Split the eleven specs over 600 lines along `describe` boundaries (`operational_credentials` 1868 →
  attestation / csr-noc / fabric-management; `administrator_commissioning` 1459 → window / pake / advertising;
  `network_commissioning`, `general_commissioning`, `group_key_management`, `access_control`,
  `message_handler_session_cleanup`, `dsl`, `responder`, `commissioning_flow`).
- Rename the `pending` local in `message_handler_session_cleanup_spec.cr`; dedicated specs for the Phase 6
  objects (`MrpCache`, `SessionRegistry`, `SubscriptionManager`, `SecureChannel`, `InteractionRouter`,
  `Node`, `EventJournal`, `Device` DSL); `spec/compatibility/` and `spec/regression/` split as planned in
  Phase 1; the one true pending (`report_data_matterjs_vector_spec.cr`) either fixed by encoding attribute
  paths with minimal-width ints behind a `fixed_size:` flag that iOS needs, or documented as intentional in
  the spec text.

## Step 2: docs and changelog

- `CHANGELOG.md` (Keep a Changelog format, `## [Unreleased]`): every breaking change the survey listed under
  Storage, Device API, Clusters, Device types/datatypes/mDNS/controller, Errors/IM, Logging/misc, plus the
  wire fixes (group id width, AAD, Groups/Colour/WindowCovering command decoding) and the new features
  (DSL, storage backends, migrator CLI, events, device DSL); a "Migrating from 0.1" section pointing at
  `bin/matter-storage migrate --from legacy:`.
- `README.md`: architecture overview (layers and the require tree), a Controller section
  (`require "matter/controller"`, the crystal chip-tool), the device DSL as the primary example, error
  handling and status factories, logging sources. `examples/chip-tool/README.md`: `controller.yml`.
  `docs/`: an `architecture.md` diagram of node/endpoint/cluster and the protocol objects; version-history
  note in the Apple Home doc. `AGENTS.md` becomes a one-line pointer to `CLAUDE.md`; `CLAUDE.md` gains the
  conventions list from `tasks/todo.md` and drops instructions the refactor made obsolete. Bump `shard.yml`
  to `0.2.0`.

## Step 3: CI and release

- `.github/workflows/ci.yml`: a `build` job compiling every `examples/matter_*_device.cr`, `examples/chip-tool.cr`,
  `src/matter/storage/cli.cr` (`shards build matter-storage`) and `e2e/spec/*_spec.cr` with `--no-codegen`;
  `run_validation.sh` runs against the switch as today; `continue-on-error` nightly leg kept but reported.
- Final gates on the branch: full `./test`, `./bin/ameba`, `crystal tool format --check`, all builds; the
  user's iOS smoke test; `tasks/todo.md` review with the before/after table for the whole refactor.
- Delete `tasks/phase*-plan.md` into a `docs/refactor-2026-09.md` summary (or keep them; user's call), open
  the PR `refactor/cleanup` → `develop` with the changelog as the description, squash nothing (history is the
  audit trail).

## Verification

| Gate | When |
|---|---|
| `crystal spec --error-trace` via subagent; `grep -c "EndpointNumber.new" spec` near zero | Step 1 |
| README/CHANGELOG links and code samples compile (`crystal build --no-codegen` a doc-samples spec) | Step 2 |
| CI green on the PR incl. the new build job | Step 3 |
| `./test` green; iOS smoke test | Step 3 |
