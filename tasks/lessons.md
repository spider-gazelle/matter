# Lessons

- 2026-09-12: `examples/run_validation.sh` defaults to the *system* chip-tool; only
  `--chip-tool ./bin/chip-tool` exercises the in-repo Crystal controller, which is what CI runs. A
  local pass without that flag says nothing about the controller. Run it the way CI does before
  claiming the controller works.
- 2026-09-12: OpenSSL's two entry points spell the curve differently. `generate_by_curve_name` wants
  `prime256v1`; `from_private_bytes` and `from_public_bytes` want the NIST name `P-256` and raise
  "unknown NIST curve" otherwise. `Key#private_bits=` passed the short name inside a `rescue` that only
  logged at debug, so deriving a public key from a stored private key silently produced nothing and
  every caller failed later at the point of use. A rescue that swallows a configuration error turns a
  one-line bug into a mystery: rescue the case you can actually handle, and assert what you expect.

- 2026-09-12: Crystal keeps only the **ten** most recently used program directories in a cache root and
  deletes the rest at the *start* of every compile (`codegen/cache_dir.cr#cleanup`). The e2e builder
  compiled eleven programs in parallel into one root, so a starting build deleted a sibling's directory
  mid-codegen (`Error renaming file: ... No such file or directory`, then a link failure). Fixed by giving
  each build its own `CRYSTAL_CACHE_DIR`; nothing is lost, the cache is per program either way. When
  parallel compiles share a cache, count the programs against that limit. See the earlier BuildKit
  cache-mount race below: same directory, different mechanism.

- 2026-09-12: A custom type used as a TLV field must work in both directions, and the two were not
  symmetric. The tlv shard's `serialize_value` dispatches on a registered overload, so any
  `define_id` type encoded; but its union branch matched a closed member set with no `else`, so a
  *nilable* custom type (`NodeId?`) encoded and then failed to decode. Only `FabricIndex` broke
  encoding, because it never registered an overload. Fixed upstream in tlv 1.1.0 (the union branch now
  falls back to the registered overload) and the guard spec discovers both sets from the shard rather
  than listing them. Test a new field type by round-trip, nilable and non-nilable, not by encode alone.
- 2026-09-12: `DataType::FabricIndex` wrapped a `UInt8` that is bare on the wire, so it could not be a
  TLV field and every call site unwrapped it. Deleted; `DataType::NO_FABRIC` remains as the constant for
  the spec's reserved index 0. A value struct earns its keep only when it carries behaviour the
  primitive cannot.

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
