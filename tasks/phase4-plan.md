# Phase 4 sub-plan: wire codec and the cluster boundary

The seven-phase plan is in `tasks/todo.md`. Phases 0-3 are done on `refactor/cleanup` (2268 unit + 63 e2e
green). Status: **complete; all verification gates passed**.

## Progress

- [x] Inspect codec and cluster boundaries against the existing matter.js reference clone
- [x] Reproduce full-header authentication and counter defects with regression specs
- [x] Step 1 implementation and byte-exact codec/certificate/session verification
- [x] Step 2 complete typed cluster migration and focused unit verification
- [x] Step 3 Groups/Colour/Window Covering and scene wire regressions
- [x] Replace manual Pake3, StatusResponse, TimedRequest and RemoveFabric parsing
- [x] Add color/window endpoints and official chip-tool regression cases
- [x] Format, lint, all unit specs, build all examples/controller/CLI
- [x] Full `./test`, including restarts and new cluster e2e cases
- [x] Final review and results in `tasks/todo.md`

## Context

Two boundaries are inconsistent today and both hide real defects.

**Secure messages.** Eight hand-rolled copies of "build header, encode, nonce, encrypt, send" exist across
`protocol/message_handler.cr`, `controller/client.cr` and `transport/udp_transport.cr`. `PacketHeader` stores
both derived fields and the raw flag bytes, so the two can disagree. The encrypt path uses the full encoded
header as authenticated data (correct per Matter Core §4.7.2) but `SecureMessage.decrypt` builds a fixed
8-byte AAD; they agree only when no node ids are present, which is why the controller hardcodes "omit node
ids". Message counters are checked three times per packet by two algorithms, and the session-level one
(strict monotonic) wrongly drops reordered UDP datagrams.

**Cluster boundary.** Reads return TLV-encoded `Bytes` that the interaction-model handler decodes and
re-encodes; writes receive the raw value bytes with the TLV header stripped, so every cluster carries
width-tolerant `decode_*` helpers (66 call sites) and a `Bytes[0x14]` null sentinel; commands receive the
full TLV encoding. Three clusters index command bytes directly and are broken on the wire: Groups (all
commands and all responses), Colour Control (10 handlers; the 19 request structs already exist and are
unused) and Window Covering (`go-to-lift-percentage`). Unit specs hand-build the same wrong bytes and no
e2e spec covers those clusters.

Goal: one `SecureMessage.encode/decode`, a single-representation `PacketHeader`, one message counter,
`TLV::Any` across the cluster boundary, and the three broken clusters fixed with e2e coverage.
Rules: no magic numbers; every behaviour change gets a spec; no `puts` in specs; ameba at zero; byte-exact
compatibility specs stay green.

## Step 1: packet header, secure message codec, counters

- `PacketHeader` (`codec/message_codec.cr`) holds derived fields only; `flags` and `security_flags` are
  computed (`HEADER_VERSION << VERSION_SHIFT`, presence bits from nil-ness, session type + control/privacy/
  extension bits). `compute_flags` is deleted; the constructor loses the two raw-byte params (~8 src and
  ~30 spec constructions drop them). `decode_packet` keeps the received header slice on the packet
  (`header_bytes`) so decrypt authenticates exactly what arrived. All vectors in
  `spec/compatibility/message_codec_compatibility_spec.cr` and `pase_packet_encoding_spec.cr` already match
  derivation.
- `Session::SecureMessage.encode(session, payload_header, payload, source_node_id:, destination_node_id:,
  message_counter:) : {Bytes, UInt32}` and `.decode(session, packet) : Message`. AAD is the encoded header
  bytes in both directions; the four 8-byte AAD builders, `build_aad`, `encrypt_with_params`/
  `decrypt_with_params` go. `MessageCodec.encode_message(packet_header, payload_header, payload)` is the
  unencrypted twin. Replace the copies: `send_subscription_update`, `send_encrypted_ack`, `send_im_response`
  (keep MRP caching using the returned counter), `send_secure_channel_response`, `decrypt_message` in the
  message handler; `send_encrypted_request`, `send_standalone_ack`, `send_unsecured_on_exchange`,
  `decrypt_message` in the client; `send_request`, `send_acknowledgment` in the transport. The client stops
  forcing "no node ids" (`client.cr:161-163`); a spec encrypts with source and destination node ids present
  and the device decrypts it.
- One counter: `SecureContext` owns two `Transport::MessageCounter`s (local/peer); `next_message_counter`
  delegates, `check_peer_message_counter` returns `CheckResult` (Accept → decrypt, Duplicate → MRP resend,
  Stale → drop). Delete `would_accept_message_counter?`/`validate_message_counter`, the check inside
  `SecureMessage.decrypt`, and the transport's per-session `@session_counters` (it keeps the `session_id == 0`
  map). `message_handler.cr:~740` is the single decision point. `local_message_counter`/`peer_message_counter`
  stay as record accessors for persistence and the legacy importer. Re-baseline
  `spec/session/context_spec.cr:49-76` to the windowed rule (`validate(50)` after 101 is Accept inside the
  64-wide window) and the off-by-one in `:30-47`.
- `codec/der_codec.cr`: keep only the live surface (`encode`, `encode_length_bytes`, `encode_sequence`,
  `encode_octet_string`, `ObjectId`/`encode_oid`, the three OID lambdas used by the certification
  declaration); delete the decoder, the unused X.509 lambdas, `Pkcs7SignedData`, `ContextTaggedSlice` and
  their spec fragments. Switch the two attestation-manager uses to OpenSSL's `subjectKeyIdentifier=hash` /
  `authorityKeyIdentifier=keyid:always` shorthands so DER is scoped to the CD builder; a spec asserts the
  produced DAC/PAI still parse and carry those extensions with the same values.

## Step 2: `TLV::Any` across the cluster boundary

Contract (`cluster/cluster.cr`):
```
read_attribute(id, fabric_index = nil) : Status | TLV::Any
write_attribute(id, value : TLV::Any) : Status        # → handle_write_attribute(id, value : TLV::Any)
invoke_command(id, request : TLV::Any? = nil, ...) : Status | CommandResponse
handle_command(id, request : TLV::Any?)
CommandResponse(command_id, response : TLV::Any?)     # nil = status-only
AttributeMetadata#default : TLV::Any?; @attribute_values : Hash(UInt32, TLV::Any)
```
- Base helpers replacing the `decode_*` block: `decode(value, T)` / `decode?(value, T)` over
  `TLV::Serializable.deserialize_value` (scalars, enums, structs, arrays, nilables); `narrow_u8?`/`narrow_i8?`
  and `signed?(value, T)` shims preserving today's leniency for over-wide unsigned encodings and
  unsigned-encoded positive values into signed attributes (thermostat/temperature paths); `tlv(value)` →
  `TLV::Serializable.serialize_value(value, nil)` so the 322 `.to_tlv` sites are a substitution; null is
  `value.value.nil?`. Delete `tlv_null?`, `decode_uint..decode_string`, `TLV_NULL_MARKER`.
- IM handler: delete `tlv_value_bytes`; `write_attributes` passes `AttributeDataIB#data` straight through;
  `build_attribute_report` uses the cluster's `TLV::Any` directly (no re-parse, no empty-bytes branch);
  `invoke_commands` passes `command_fields` and uses `result.response`; `safe_*` signatures follow. Same in
  the subscription path (`message_handler.cr:~589-605`) and `endpoint.cr` (drop the response unwrap).
- Clusters, in this order, each with its spec updated in the same commit: trivial read-only clusters
  (fixed_label, boolean_state, user_label, the measurement clusters, descriptor, diagnostics, power_source,
  icd_management, ota_requestor, diagnostic_logs; delete their one-line `encode_*` wrappers, ~20); then
  write-handler clusters smallest first (identify, window_covering, on_off, time_format_localization,
  general_commissioning, bridged_device_basic_information, basic_information, fan_control,
  occupancy_sensing, thermostat, level_control, door_lock); then the facade clusters (access_control:
  `value.as_list.map { AccessControlEntry.from_tlv }` replaces `decode_acl_list`/`extract_acl_array`/
  `decode_extension_list` re-encode; operational_credentials, administrator_commissioning,
  network_commissioning, group_key_management, scenes_management, groups). `Struct.from_slice(fields)`
  becomes `Struct.from_tlv(request)` 1:1; `CommandResponse.new(id, struct.to_tlv(nil))`.
- Spec support: `spec/support/cluster_helpers.cr` `read_tlv`/`write`/`invoke`/`invoke_response` adapt (the
  file was written for this); `error_mapping_spec.cr` uses `TLV::Any.new(1_u8)`;
  `write_attribute_raw_value_spec.cr` keeps its cases (they already go through a real WriteRequest) and is
  renamed `write_attribute_width_spec.cr`; `im_handler_tlv_value_bytes_spec.cr` is deleted with its two
  FanControl cases folded into the former. Mechanical sweep: route the ~100 direct `write_attribute`, ~230
  `read_attribute` and ~270 `invoke_command` spec calls through the helpers (each loses a
  `from_slice`/`to_slice`).

## Step 3: wire-format fixes and manual TLV sites

- Groups: restore `src/matter/cluster/definitions/groups.cr` from `35220dc^` (AddGroup/Response, ViewGroup/
  Response, GetGroupMembership/Response with nullable capacity, RemoveGroup/Response, RemoveAllGroups,
  AddGroupIfIdentifying); `handle_command` decodes with `from_tlv`, responses are structs; delete the five
  little-endian encoders; rewrite `spec/cluster/groups_spec.cr` against the structs (its 25 invoke calls
  currently encode the broken layout).
- Colour Control: the 10 raw-slicing handlers (`~545-670`) decode the existing
  `Definitions::ColorControl::*Request` structs.
- Window Covering: add `GoToLiftPercentageRequest`/`GoToTiltPercentageRequest` (u16 at tag 0, plus the
  optional fields the spec defines) in `definitions/window_covering.cr`; decode in the handlers.
- Manual TLV indexing → structs: Pake3 (`Session::Pase::Definitions::Pake3`), StatusResponse
  (`InteractionModel::StatusResponseMessage`), TimedRequest (new `TimedRequestMessage {timeout u16 @0,
  interaction_model_revision @0xFF}` in `tlv_messages.cr`), RemoveFabric
  (`Definitions::OperationalCredentials::RemoveFabricRequest`); delete `operational_credentials_cluster.cr`'s
  `find_tlv_field` if unreferenced. The CAT scan in `case.cr:651-691` stays (repeated tags) but uses
  `as_u32?` instead of the widening case.
- e2e coverage for the three fixed clusters: the level-control device gains Groups (add/view/remove via
  chip-tool `groups add-group`), the air-conditioner or a new colour-light example gets Colour Control
  (`colorcontrol move-to-hue`, `move-to-color-temperature`, read `current-hue`), and window covering
  (`windowcovering go-to-lift-percentage`, read `target-position-lift-percent100ths`) on whichever example
  hosts it (add `WindowCoveringCluster` to the level-control device on a new endpoint if none does). These
  are the regression net the surveys said was missing.

## Execution

Step 1 and Step 2 touch disjoint files except `message_handler.cr`; run them in parallel worktrees with Step 1
owning `codec/`, `session/secure_message.cr`, `session/context.cr`, `transport/`, `controller/client.cr`,
`certificate/`, `codec/der_codec.cr`, and the send/decrypt/counter regions of `message_handler.cr`, while
Step 2 owns `cluster/`, `im_handler.cr`, `endpoint.cr`, the subscription-notify region of
`message_handler.cr` (`~589-605`), and spec support. Step 3 follows Step 2 (it needs the `TLV::Any`
contract) and can start on Groups/Colour/Window Covering while Step 2's facade clusters finish, but lands
after it. Merge order: 1, 2, 3.

| Gate | When |
|---|---|
| format, ameba exit 0 | every commit |
| `crystal spec --error-trace` via subagent; build all examples + chip-tool | after each merge |
| byte-exact compatibility specs (`spec/compatibility/*`) and iPhone/matter.js vectors | Step 1 |
| `./test` (unit + e2e incl. restarts + new Groups/Colour/WindowCovering cases) | after Step 2 merge and at the end |
| `grep -rn "decode_u\|tlv_null?\|TLV_NULL_MARKER\|tlv_value_bytes\|compute_flags\|encrypt_with_params" src` empty | end |

## Results

Completed with `./test` exit 0: 2287 unit examples (zero failures/errors, one unchanged pending
vector assertion), 66 official chip-tool e2e examples, and device validation 20/20. The host
`crystal spec -v --error-trace` run also passes through a subagent. All example binaries, chip-tool,
and storage CLI compile; formatting and ameba pass (344 files, zero findings).
See the phase 4 review in `tasks/todo.md` for the changes and verification logs.
