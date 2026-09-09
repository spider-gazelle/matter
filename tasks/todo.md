# End-to-end test harness (docker compose + chip-tool)

## Plan
- [x] Research: official chip-tool docker image (multi-arch), crystal base image tag
- [x] `e2e/Dockerfile` (multi-stage): builder compiles all examples + device_validation; `device` target runs an example; `tests` target = crystal + chip-tool + repo
- [x] `docker-compose.yml` at repo root: one service per example device (shared log volume, healthcheck on pairing-code line) + `tests` service depending on all devices
- [x] `e2e/device-entrypoint.sh`: runs example, tees output to `/e2e/logs/<name>.log`, forwards SIGTERM
- [x] `e2e/run.sh` (container entry): unit specs (`crystal spec`) then e2e specs (`crystal spec e2e/spec`), env toggles to skip either
- [x] `e2e/spec/e2e_helper.cr`: ChipTool wrapper, Device helper (pairing code from log, hostname), commissioning helper, output parsers
- [x] `e2e/spec/*_spec.cr`: one per example; commission + read + write/command per relevant cluster; switch spec also runs `device_validation` (multi-fabric/ACL)
- [x] Add pairing-code print to sensor examples that lack it (contact, motion, humidity, ambient light)
- [x] `./test` script (bash 3.2 compatible, linux+macOS): detect compose, build, up with `--exit-code-from tests`, save logs, tear down, PASS/FAIL + exit code
- [x] `.dockerignore`, `.gitignore` updates, README section
- [x] Verify: `./test` passes locally end-to-end; `crystal tool format` clean; ameba clean on new files (examples have pre-existing findings)

## Review
- `./test` runs 2133 unit examples + 61 e2e examples across all 10 example devices, all passing.
- The e2e suite found a real regression: since 65bbc58 the IM handler passes raw value bytes to
  `write_attribute`, but identify/door lock/bridged+basic information/occupancy/on-off/... clusters
  still parsed TLV or assumed fixed integer widths, so official chip-tool writes failed with
  INVALID_DATA_TYPE. Fixed with width-tolerant decode helpers in `Cluster::Base` and a reproducing
  spec (`spec/cluster/write_attribute_raw_value_spec.cr`).
- Example changes: the four sensor examples now print their pairing code; the bridge starts with
  1..2 bridged lights instead of 0..2 so it always has something to test.
- Not changed: `.github/workflows/ci.yml` (still uses the crystal chip-tool as requested).

## Notes
- chip-tool image: `ghcr.io/matter-js/chip` (multi-arch, IPv6 only, needs avahi+dbus running). The
  `ghcr.io/project-chip/*` images are not pullable and `connectedhomeip/chip-cert-bins` is arm64 only.
- Compose network has an IPv6 ULA subnet so devices advertise AAAA records (verified: `pairing code`
  via mDNS across the bridge commissions, reads and toggles work).
- Crystal apt repo only ships amd64 packages -> crystal installed from the official release tarball
  (x86_64 + aarch64) on top of the chip-tool image.
