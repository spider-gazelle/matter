# Matter

[![CI](https://github.com/Crystal-Matter/matter/actions/workflows/ci.yml/badge.svg)](https://github.com/Crystal-Matter/matter/actions/workflows/ci.yml)

Matter protocol implemented in pure Crystal Lang.

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     matter:
       github: Crystal-Matter/matter
   ```

2. Run `shards install`

## Examples

An example OnOff device is provided in the `./examples` directory.

* Build using: `crystal build examples/matter_switch_device.cr -o bin/matter_switch`
* Validate with [chip-tool](https://project-chip.github.io/connectedhomeip-doc/development_controllers/chip-tool/chip_tool_guide.html)
  * Launch `bin/matter_switch`, grab the chip-tool command line in the output
  * Clear any previous sessions: `chip-tool storage clear-all`
  * Commission using chip-tool

Confirmed working with iOS.

`examples/matter_level_control_device.cr` exposes a dimmable light with Groups on
endpoint 1, an extended color light on endpoint 2, and a window covering on endpoint 3.
The Docker e2e suite commissions it with the official chip-tool and exercises group
membership, hue, color temperature, and lift position commands.

Cluster reads return `TLV::Any` or an Interaction Model status. Attribute writes
take `TLV::Any`; command requests and `CommandResponse#response` use `TLV::Any?`.
For example, pass `TLV::Any.new(50_u8)` to write a scalar or `request.to_tlv(nil)`
for a `TLV::Serializable` command struct. Wire encoding stays in the protocol layer.

Examples log at `info` by default; set `MATTER_LOG` to change the level (specs use
`MATTER_SPEC_LOG` the same way, defaulting to `warn`):

```
MATTER_LOG=debug bin/matter_switch
MATTER_SPEC_LOG=trace crystal spec
```

### Example projects

These projects show off how custom matter interfaces can be built for almost any device.

* Control a [Home Connect oven](https://github.com/Crystal-Matter/homeconnect-oven-matter) using siri
* [Control a rangehood](https://github.com/Crystal-Matter/elica-rangehood-matter)
* Control a [Windows media center PC](https://github.com/Crystal-Matter/matter_media), plugged into your TV, from your phone

## Storage

Device state (fabrics, sessions, subscriptions, cluster state, identity) is persisted
through `Matter::Storage::Backend`. Three backends ship with the library:

* `Matter::Storage::YamlFile` - one human readable YAML file (recommended)
* `Matter::Storage::JsonFile` - the same layout as JSON
* `Matter::Storage::Memory` - nothing persisted; state is rebuilt on every start

A store is a set of *collections* (`fabrics`, `sessions`, `subscriptions`, `device`,
`clusters`, `app`, `meta`), each holding *documents* keyed by id, so a file looks like
`{collection: {id: document}}`. Documents hold 64-bit integers, floats, booleans,
strings, byte strings, timestamps, arrays and nested maps. Bytes are written as
`!!binary` base64 in YAML and `{"$bytes": "<base64>"}` in JSON; timestamps as
`!!timestamp` / `{"$time": "<RFC 3339 UTC>"}`. `meta/schema` records the layout version.

`bin/matter-storage` (built with `shards build matter-storage`) copies and prints stores.
Store URIs are `memory:`, `yaml:<path>`, `json:<path>`:

```shell
bin/matter-storage migrate --from json:matter_storage.json --to yaml:matter_storage.yml
bin/matter-storage inspect yaml:matter_storage.yml   # keys, certs and byte strings are redacted
```

Devices that ran a release before the storage refactor wrote a different flat JSON file
(`{"<context>": {"<key>": <json string>}}`). Convert it once with the `legacy:` scheme:

```shell
bin/matter-storage migrate --from legacy:matter_storage.json --to yaml:matter_storage.yml
```

Unrecognised entries are kept under `app/legacy-<context>-<key>` and each is reported with
a warning, so nothing is dropped silently. The importer lives in `src/matter/storage/legacy/`
and is only loaded by `require "matter/storage/legacy"` (the CLI does this); it is a
temporary module that will be removed once deployed devices have migrated.

## End to end tests

The full suite (unit specs + chip-tool driven end-to-end specs against every example
device) runs inside docker compose, so the only requirement is Docker with compose v2
(Docker Desktop on macOS, or docker engine 27+ on Linux):

```shell
./test                 # build images, run everything, tear down, exit 0/1
./test --e2e-only      # skip the unit specs
./test --unit-only     # only the unit specs
./test -- e2e/spec/switch_spec.cr   # a single e2e spec file
```

* `docker-compose.yml` starts one container per `examples/matter_*_device.cr` and a
  `tests` container built from the official [chip-tool](https://github.com/matter-js/matter.js-chip)
  image with crystal added.
* `e2e/spec/*_spec.cr` are regular crystal specs that commission each device with
  `chip-tool pairing code` (mDNS discovery over the compose network) and then read
  and write the relevant cluster attributes.
* Container logs (device output, pairing codes, protocol debug logs) are saved to
  `tmp/e2e/logs/` after every run.

Persistence is checked by restarting devices in place. The `tests` container has no
docker socket, so `E2E::Device#restart!` creates a marker file
`/e2e/logs/<example>.restart` on the shared log volume; `e2e/device-entrypoint.sh`
(a small supervisor loop) removes it, sends `SIGTERM` to the device for a clean
shutdown, appends `=== e2e restart <n> ===` to `<example>.log` and starts the binary
again in the same working directory, where its storage lives. The spec then waits for
the operational-mode banner after that line and checks that no new pairing code was
printed before reading the persisted state back with chip-tool. A device that exits
without a restart having been requested takes its container down with its exit code.

The same validation can be run directly on the host against a locally installed
chip-tool:

```shell
./examples/run_validation.sh
```

We have our own implementation of chip-tool for running end-to-end tests too (used in the CI)
Aiming to be compatible with the official tool

```shell
crystal build ./examples/chip-tool.cr -o ./bin/chip-tool --error-trace
./examples/run_validation.sh --chip-tool ./bin/chip-tool
```

## Contributing

1. Fork it (<https://github.com/Crystal-Matter/matter/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Stephen von Takach](https://github.com/stakach) - creator and maintainer
