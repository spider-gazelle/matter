## Working on this project

This is a Crystal lang Matter protocol library. Format and lint with `crystal tool format` and
`./bin/ameba`; both must be clean before anything is done.

Run specs with `crystal spec -v --error-trace`, **via a subagent** so the output stays out of the
main context. Individual spec files and `focus: true` work as usual; `MATTER_SPEC_LOG` sets the
spec log level (default `warn`).

`./test` runs everything inside docker compose: the unit specs plus the end-to-end specs that
commission every example device with the official `chip-tool`. `./test --unit-only`,
`./test --e2e-only` and `./test -- e2e/spec/<file>_spec.cr` narrow it down. Example code must
compile *and* pass e2e: a device has to commission, and chip-tool has to read and write the
relevant cluster attributes. Container logs land in `tmp/e2e/logs/`.

Clone https://github.com/matter-js/matter.js and use it as a reference implementation.

Documentation lives in `README.md`, `CHANGELOG.md` and `docs/` — `docs/architecture.md` is the map
of how a datagram reaches a cluster and where persistence, events and commissioning sit.

## Conventions

- Singular directory names; classes named for the thing (`Cluster::OnOff`, `Fabric::Table`).
  No `Cluster` suffix on cluster classes.
- Explicit require tree, no `**` globs. `require "matter"` is the device library only; the
  controller is behind `require "matter/controller"`, and `matter/storage/legacy` and
  `matter/storage/cli` are required explicitly.
- Layers only reach downwards (see the stack in `docs/architecture.md`). `Matter::Storage` depends
  on nothing else in the library — keep it that way.
- No magic numbers. Every meaningful literal gets a named constant or an enum member; enums are
  preferred.
- `Matter::Error` hierarchy; no bare string raises; every rescue either logs with context or
  re-raises.
- `InteractionModel::Status` factory methods (`Status.success`, `Status.constraint_error`,
  `Status.cluster_failure(code)`), never `Status.new(StatusCode::…)`.
- Log sources mirror the file tree (`matter.session.pase`); `spec/log_sources_spec.cr` fails on
  drift.
- Cluster constants are `ATTR_`, `CMD_` and `EVENT_` prefixed; `CLUSTER_REVISION` is always the
  revision value, never an attribute id.
- Clusters are written on the cluster DSL (`src/matter/cluster/dsl.cr`) and devices on the device
  DSL (`src/matter/device/dsl.cr`); the rules are documented at the top of each. Reach for a new
  DSL keyword before a workaround in a cluster.
- TLV via `@[TLV::Field]` structs only — no manual tag indexing, no raw little-endian slices.
  Values cross the cluster boundary as `TLV::Any`; wire encoding stays in the protocol layer.
- Persistence via `Storage::Document` / `Storage::Record` only.

## 1. Plan Node Default
- Enter plan mode for ANY non-trivial task (3+ steps or architectural decisions)
- If something goes sideways, STOP and re-plan immediately, don’t keep pushing
- Use plan mode for verification steps, not just building
- Write detailed specs upfront to reduce ambiguity

## 2. Subagent Strategy
- Use subagents liberally to keep main context window clean
- Offload research, exploration, and parallel analysis to subagents
- For complex problems, throw more compute at it via subagents
- One task per subagent for focused execution

## 3. Self-Improvement Loop
- After ANY correction from the user, update `tasks/lessons.md` with the pattern
- Write rules for yourself that prevent the same mistake
- Ruthlessly iterate on these lessons until mistake rate drops
- Review lessons at session start for relevant project

## 4. Verification Before Done
- Never mark a task complete without proving it works
- Diff behavior between main and your changes when relevant
- Ask yourself: "Would a staff engineer approve this?"
- Run tests, check logs, demonstrate correctness

## 5. Demand Elegance (Balanced)
- For non-trivial changes, pause and ask: "Is there a more elegant way?"
- If a fix feels hacky: "Knowing everything I know now, implement the elegant solution"
- Skip this for simple, obvious fixes, don’t over-engineer
- Challenge your own work before presenting it

## 6. Autonomous Bug Fixing
- When given a bug report, don’t ask for hand-holding
- Don’t start by trying to fix it. Instead, start by writing a test that reproduces the bug. Then, have subagents try to fix the bug and prove it by passing that test.
- Point at logs, errors, failing tests, then resolve them
- Zero context switching required from the user

---

## Task Management

`tasks/` is gitignored working notes, local to whoever is doing the work. Nothing in it is committed,
so anything a reader of the repository needs belongs in `CHANGELOG.md`, `README.md` or `docs/`.

1. **Plan First**: Write plan to `tasks/todo.md` with checkable items  
2. **Verify Plan**: Check in before starting implementation  
3. **Track Progress**: Mark items complete as you go  
4. **Explain Changes**: High-level summary at each step  
5. **Document Results**: Add review section to `tasks/todo.md`  
6. **Capture Lessons**: Update `tasks/lessons.md` after corrections  

---

## Core Principles

- **Simplicity First**: Make every change as simple as possible. Impact minimal code.  
- **No Laziness**: Find root causes. No temporary fixes. Senior developer standards.
