# Phase 6 sub-plan: device model and protocol decomposition

The seven-phase plan is in `tasks/todo.md`. Phases 0-5 are done on `refactor/cleanup` (2394 unit examples
green). Status: **complete 2026-09-12; all gates green**.

## Context

`Protocol::MessageHandler` is 2618 lines and owns the data model: the cluster registry, both handshake state
machines (one slot each, keyed by nothing, never cleared), the session and subscription registries with
three cleanup fibers, the MRP response cache, two near-duplicate chunk ladders, and IM routing. One mutex
guards inbound messages only; subscription reports from cluster callbacks, the cleanup fibers, the
persistence debounce, the fabric-removal delay and the commissioning-window timeout all mutate shared state
without it. `Endpoint`/`MatterNode` (243 lines, 830 spec lines) implement device-type validation that
production never runs. `Device::Base` (696 lines) hand-constructs 12 root clusters, wires seven cross-cluster
callbacks, and forces every example through six identity hooks, a `device_clusters` array with `.as(T)`
casts, and copy-pasted console plumbing (the four sensor examples are one file with a cluster swapped). The
failsafe context requires two clusters that require it back. CASE duplicates certificate validation between
initiator and responder, and the initiator's key derivation is not spec-conformant. Events are declared by
the DSL but nothing emits or reads them.

Goal: a `Node`/`Endpoint` model that owns clusters and validates device types at boot; a message handler
under 600 lines with sessions, subscriptions, secure channel and IM routing as separate objects sharing one
lock; a `commissioning/` module without cycles; facade clusters that are thin fronts over services; a
device DSL that makes an example read like a Rails model; the examples rewritten on it; an event path.

Rules carried forward: no magic numbers; every behaviour change gets a spec; no `puts` in specs; ameba at
zero; `./test` green at each step end.

## Step 1: `Node` and `Endpoint` own the clusters

- `src/matter/node.cr` (`Matter::Node`, absorbs `MatterNode`) and `src/matter/endpoint.cr` trimmed: `Node`
  owns `Hash(UInt16, Endpoint)` plus a flat `{endpoint, cluster_id} → Cluster::Base` index maintained on
  add/remove, so `IMHandler`'s point lookups are unchanged; `Endpoint#add_cluster` validates the endpoint id
  (replacing the open-coded check in `Device::Base#add_endpoint`), `Endpoint#validate` runs
  `DeviceType#required_server_clusters` at `add_endpoint` time (raise `ConfigurationError`, a new
  `Matter::Error` subclass, on a missing mandatory cluster), and `device_type_revision` comes from
  `DeviceType#revision` instead of the hard-coded `1_u16`. Descriptor injection and population
  (`inject_and_populate_descriptors`) move onto `Endpoint`/`Node`; scene-extension chaining
  (`wire_scenes_management_extensions`) becomes `Endpoint#wire_scene_extensions`. `Node#on_attribute_changed=`
  and `#on_version_changed=` apply on insert, removing the "call `setup_cluster_notifications` again"
  footgun. Delete `Endpoint`'s fabric-less `read_attribute`/`write_attribute`/`invoke_command` and
  `MatterNode`'s wrappers (a second, weaker IM path); keep the typed `get_cluster(T)`.
- `MessageHandler#clusters` delegates to `node.index`; `Device::Base` builds through `node.endpoint(0)`;
  `add_endpoint`/`remove_endpoint` become thin, symmetric (`remove_endpoint` gains `notify_subscribers:` and
  forgets the descriptor). `spec/endpoint_spec.cr` (mislabelled `describe Matter::DeviceType`) and
  `endpoint_ergonomics_spec.cr` are rewritten against the real API and moved under `spec/node/`.

## Step 2: decompose `MessageHandler`

Cut along the survey's coupling map, each extraction a commit with the moved specs:

- `Protocol::MrpCache` (S2+S10): `@mrp_response_cache`, prune/resend/cache/clear, TTL and size constants.
- `Protocol::SessionRegistry` (S32–S37 + `@sessions`, `@active_subscriptions`, `@pending_session_cleanups`,
  limits, the two cleanup fibers, `persist_all_sessions`): owns the `Mutex`; exposes `synchronize`, lookup,
  insert with `enforce_session_limit` and supersession cleanup, deferred removal with `CleanupReason`,
  subscription migration, expiry, and the `on_session_removed`/`on_subscription_removed` callbacks. The two
  guard flags become one fiber per registry started in `start` and stopped in `close`; dead
  `get_session_subscriptions`, `delete_subscription`, `@session_cleanup_fiber_running` go.
- `Protocol::SubscriptionManager` (S3/S4/S6/S13/S19/S28 + `ActiveSubscription`, `PendingSubscription`,
  `PendingReadResponse`): one chunk ladder (`handle_status_response` and `handle_standalone_ack` share it),
  `notify` and batched reports, `send_subscription_update`; always runs inside `registry.synchronize` so
  cluster callbacks from any fiber take the same lock as inbound messages.
- `Protocol::SecureChannel` (S12/S26/S27/S29/S30/S31/S38 + PASE/CASE ivars): handshake state keyed by
  exchange id in `Hash(UInt16, PaseExchange | CaseExchange)`, cleared on completion or timeout
  (`HANDSHAKE_TIMEOUT` constant), so two commissioners no longer collide and stale responders are not
  reused; the hand-rolled PBKDF exchange uses `PaseResponder#process_pbkdf_param_request`; PASE
  configuration (`configure_pase_server`/`configure_pase_pin`/`reset_pase_server`) lives here and is
  called under the lock from the commissioning-window timeout.
- `Protocol::InteractionRouter` (S17/S18/S21–S25): IM dispatch, timed requests, read/subscribe/write/invoke,
  `send_im_response`; `IMHandler`'s module functions stay as they are.
- `MessageHandler` keeps: construction, `handle_message` (decrypt, counter classification, MRP replay, route
  to secure channel or IM router), `setup_cluster_notifications` delegation, and the device callbacks. Target
  ≤ 600 lines. Transport MRP: `process_retransmissions` has no caller; either drive it from the transport's
  receive loop with a `RETRANSMIT_TICK` or delete the retransmit engine and keep the duplicate window and
  auto-ACK (decide in the sub-step; the survey shows it is inert today).
- `Persistence::Base` callbacks take the registry, not the handler; `LifecycleManager` takes the registry.

## Step 3: `commissioning/` module and the facade clusters

- `src/matter/commissioning/{failsafe_context,failsafe_timer,window}.cr`; `FailsafeContext#rollback` takes a
  `RollbackTargets` interface (or procs) instead of the two cluster types, which breaks the
  `general_commissioning ↔ failsafe_context` require cycle and drops the `network_commissioning` require.
  `CommissioningWindow` either becomes the state `AdministratorCommissioning` actually uses or is deleted.
- Services: `Commissioning::FailsafeService` (owns the context, arm/disarm/expiry, the three unwired
  `GeneralCommissioning` procs become real calls), `Commissioning::WindowService` (window state + timeout
  fiber + PASE/mDNS side effects via the secure channel and responder), `Commissioning::CredentialService`
  (the `OperationalCredentials` domain: attestation manager, CSR/NOC/root-cert flow, fabric add/update/
  remove against `FabricTable`, `PendingCredentials`). The four facade clusters become thin DSL fronts:
  handlers decode the request, call the service, encode the response. `Device::Base`'s seven hand-wired
  callbacks collapse into service construction in one place (`Device::Runtime` or inside `Node`).
- Delete the five declared-but-never-wired callbacks the survey found.

## Step 4: CASE, events

- CASE: one `validate_certificate_chain`, one `derive_session_keys(salt, length, role)`; the initiator uses
  the responder's spec constants (`KDFSR2_INFO`, `TBE_DATA2_NONCE`, …) and the TLV certificate helpers move
  to `Crypto::MatterCertificate` so both sides share them; `Case.establish_session` stays spec-only or is
  deleted if the controller's `CasePairing` already covers it.
- Events: `Matter::EventJournal` on `Node` (node-wide monotonic event number, per-priority ring buffers with
  named size constants, fabric-scoped records), `Cluster::Base#emit_event(id, data, fabric_index = nil)`
  with `on_event_emitted`, `EventDataIB`/`EventStatusIB`/`EventReportIB` in `tlv_messages.cr`,
  `IMHandler.read_events` beside `read_attributes` sharing the chunk budget, `ActiveSubscription` gains event
  paths and `last_event_number` (persisted), urgent events bypass min-interval damping. Door lock, basic
  information and bridged basic information emit their declared events. e2e: `chip-tool doorlock read-event
  lock-operation` after a lock command.

## Step 5: device DSL and examples

```crystal
class Switch < Matter::Device
  identity vendor: "Spider-Gazelle", product: "Crystal Switch",
           vendor_id: Matter::SetupPayload.test_vendor_id, product_id: 0x8001_u16,
           discriminator: 3840_u16, pin: 20202021_u32, appearance: :satin
  storage yaml: "matter_switch_storage.yml"

  endpoint 1, device_type: Matter::DeviceType::ON_OFF_LIGHT do
    cluster OnOff, feature_map: OnOff::Feature::Lighting, as: :switch
    cluster FixedLabel, labels: {"name" => "Example Switch"}
    cluster Identify, identify_type: :visible_light
    cluster Groups
    cluster ScenesManagement
  end

  endpoint_template :bridged_light, device_type: Matter::DeviceType::ON_OFF_LIGHT do
    cluster OnOff, as: :on_off
    cluster BridgedDeviceBasicInformation, as: :info
    cluster Identify
  end

  on(:switch, :state_changed) { |state| ... }
end
```

- `Matter::Device` (new; `Device::Base` becomes the runtime it wraps): `identity` (every identity hook becomes
  a declaration; `configure_attestation`, `commissioning_info_for`, `operational_info_for`,
  `default_ip_addresses` stay overridable), `storage yaml:|json:|memory`, `network ethernet|wifi|thread`,
  `endpoint n, device_type: do cluster X, **kwargs, as: :name end` generating typed non-nil accessors and
  building `endpoint_device_types`, `endpoint_template` for runtime endpoints with
  `add_endpoint(:template, **params)` returning the endpoint instance (persisted template parameters as an
  `app` record so the bridge's hand-rolled config records disappear), `on(:accessor, :event) { }` evaluated
  after all endpoints exist (fixes the air conditioner's cross-endpoint closure ordering). Root clusters and
  services are framework-owned. Lifecycle hooks stay as overridable methods.
- `examples/support/console.cr` (interactive loop, `status`/`reset`/`quit`/`help`, prompt repaint, QR and
  pairing-code printing, mode banners) and `examples/support/main.cr` (`MATTER_LOG`, `Process.on_terminate`,
  `--no-interactive`) so each example is the device class plus its own commands and simulation. The console
  output that e2e and `run_validation.sh` scrape (`chip-tool pairing code 1 <code>`, the mode banners,
  `--no-interactive`, clean SIGTERM, `Example*` fixed labels) stays byte-compatible; the air conditioner's
  label gains the `Example` prefix; `run_validation.sh`'s stale `.json` storage path is fixed. All ten
  examples rewritten; the bridge uses `endpoint_template` and sets `AGGREGATOR`/`BRIDGED_NODE` device types.
  `device_validation.cr` is untouched (it uses no library API).

## Verification

| Gate | When |
|---|---|
| format, ameba exit 0 | every commit |
| `crystal spec --error-trace` via subagent; build all examples + chip-tool | after each step |
| `./test` (unit + e2e incl. restarts, Groups/Colour/WindowCovering, new event read) | end of Steps 1, 2, 3, 5 |
| `wc -l src/matter/protocol/message_handler.cr` ≤ 600; no `spawn` outside registry/transport/timers | end of Step 2 |
| concurrency spec: subscription report from a non-handler fiber while a message is being handled | Step 2 |
| iOS pairing smoke test by the user (multi-admin window, subscriptions) | end |

Execution: Step 1 alone; Step 2 as up to four worktree agents (cache, registry, subscriptions, secure
channel) merged in that order with the router last; Step 3 and Step 4 in parallel; Step 5 alone (examples
touch everything).
