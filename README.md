# Matter

Matter protocol implemented in pure Crystal Lang.

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     matter:
       github: spider-gazelle/matter
   ```

2. Run `shards install`

## Example Device

An example OnOff device is provided in the `./examples` directory.

* Build using: `crystal build examples/matter_switch_device.cr -o bin/matter_switch`
* Validate with [chip-tool](https://project-chip.github.io/connectedhomeip-doc/development_controllers/chip-tool/chip_tool_guide.html)
  * Launch `bin/matter_switch`, grab the chip-tool command line in the output
  * Clear any previous sessions: `chip-tool storage clear-all`
  * Commission using chip-tool
  * Run: `crystal run examples/device_validation.cr`

Confirmed working with iOS.

## Contributing

1. Fork it (<https://github.com/spider-gazelle/matter/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Stephen von Takach](https://github.com/stakach) - creator and maintainer
