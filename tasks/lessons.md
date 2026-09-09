# Lessons

- 2026-09-10: For docker based e2e tooling, base the test-runner image on the official chip-tool image
  (`ghcr.io/matter-js/chip`) and add crystal on top, rather than copying chip-tool into a crystal image.
  Keep the GitHub CI using the in-repo crystal `chip-tool` (examples/chip-tool.cr); docker e2e is additive.
- chip-tool CLI gotchas: string arguments are passed verbatim (no JSON quoting), some attribute
  names collapse acronyms (`piroccupied-to-unoccupied-delay`, `require-pinfor-remote-operation`),
  list entries/enum values are annotated (`256 (On/Off Light)`), and `--help` exits non-zero.
- Official chip-tool docker image (`ghcr.io/matter-js/chip`) is IPv6-only and needs dbus+avahi
  running inside the container; give the compose network an IPv6 ULA subnet.
