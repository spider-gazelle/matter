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

### Example projects

These projects show off how custom matter interfaces can be built for almost any device.

* Control a [Home Connect oven](https://github.com/Crystal-Matter/homeconnect-oven-matter) using siri
* [Control a rangehood](https://github.com/Crystal-Matter/elica-rangehood-matter)
* Control a [Windows media center PC](https://github.com/Crystal-Matter/matter_media), plugged into your TV, from your phone

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
