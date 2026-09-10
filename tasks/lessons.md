# Lessons

- 2026-09-11: The tlv shard should raise `TLV::DeserializationError` for enum/union mismatches; today it
  uses `raise "Cannot deserialize ..."` (a bare `Exception`, not `RuntimeError`) and `deserialize_field`
  only re-wraps `TypeCastError`. Until the shard is fixed, `Cluster::Base#decode` normalises every
  deserialization failure to `TLV::DeserializationError` so peers get InvalidCommand/InvalidDataType,
  never Failure. Probe what a dependency actually raises before writing a rescue clause for it.

- 2026-09-10: If a referenced task plan is missing, check the local planning directory before
  proposing to reconstruct it. This phase's approved detail was in `~/.claude/plans/`.
- 2026-09-10: A locked compiler cache does not serialize Docker image exports. Shared builder
  layers can still fail with a missing parent snapshot; build the device and test images
  sequentially before considering cache cleanup.
- 2026-09-10: Crystal structs are copied by `Array#each`. When normalizing decoded records,
  use `map!` and return the modified struct; otherwise fabric indices and similar changes are lost.
- 2026-09-10: Verbose spec output repeats example labels for failures too. Report success only
  from the failure summary/exit status, and use chip-tool's generated log field names for assertions.

- 2026-09-10: For docker based e2e tooling, base the test-runner image on the official chip-tool image
  (`ghcr.io/matter-js/chip`) and add crystal on top, rather than copying chip-tool into a crystal image.
  Keep the GitHub CI using the in-repo crystal `chip-tool` (examples/chip-tool.cr); docker e2e is additive.
- chip-tool CLI gotchas: string arguments are passed verbatim (no JSON quoting), some attribute
  names collapse acronyms (`piroccupied-to-unoccupied-delay`, `require-pinfor-remote-operation`),
  list entries/enum values are annotated (`256 (On/Off Light)`), and `--help` exits non-zero.
- Official chip-tool docker image (`ghcr.io/matter-js/chip`) is IPv6-only and needs dbus+avahi
  running inside the container; give the compose network an IPv6 ULA subnet.
- 2026-09-10: `docker compose build` builds every service that declares `build:` concurrently. Ten device
  services sharing one Dockerfile target raced on the BuildKit crystal cache mount (object-file rename
  failures, ld errors). Declare `build:` on one service, give the rest `image:` only, and use
  `sharing=locked` on compiler cache mounts.
- 2026-09-10 (user rule): no magic numbers. Every meaningful literal (ids, tags, flag bits, offsets,
  timeouts, sizes) is a named constant or an enum member; prefer an enum wherever both would work.
  Apply when writing new code and when touching existing code.
