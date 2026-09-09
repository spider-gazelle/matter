#!/usr/bin/env bash
#
# Entrypoint of the `tests` container: runs the standard crystal specs and then
# the chip-tool driven end-to-end specs. Exit code is non-zero if either fails.
#
#   E2E_RUN_UNIT=0   skip the unit specs (spec/)
#   E2E_RUN_E2E=0    skip the end-to-end specs (e2e/spec/)
#   E2E_SPEC_ARGS    extra arguments for the e2e `crystal spec` invocation
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

RUN_UNIT="${E2E_RUN_UNIT:-1}"
RUN_E2E="${E2E_RUN_E2E:-1}"
SPEC_ARGS="${E2E_SPEC_ARGS:-}"

unit_status="skipped"
e2e_status="skipped"
failed=0

banner() {
  echo ""
  echo "=================================================================="
  echo "  $1"
  echo "=================================================================="
  echo ""
}

# The official chip-tool uses avahi for mDNS, which in turn needs the system
# dbus. Neither is running in a fresh container.
if command -v avahi-daemon >/dev/null 2>&1 && ! avahi-daemon --check 2>/dev/null; then
  banner "Starting dbus + avahi for chip-tool"
  mkdir -p /run/dbus && rm -f /run/dbus/pid
  dbus-daemon --system --fork
  avahi-daemon -D
  sleep 1
fi

if [[ ! -d lib ]]; then
  banner "Installing shards"
  shards install --skip-postinstall --skip-executables || exit 1
fi

if [[ "$RUN_UNIT" == "1" ]]; then
  banner "Unit specs (spec/)"
  if crystal spec --error-trace; then
    unit_status="passed"
  else
    unit_status="failed"
    failed=1
  fi
fi

if [[ "$RUN_E2E" == "1" ]]; then
  banner "End-to-end specs (e2e/spec/) using $(command -v chip-tool)"
  # Run the whole e2e/spec directory unless specific spec files were given.
  spec_target="e2e/spec"
  case " $SPEC_ARGS " in
    *" e2e/spec"*) spec_target="" ;;
  esac
  # shellcheck disable=SC2086
  if crystal spec $spec_target -v --error-trace $SPEC_ARGS; then
    e2e_status="passed"
  else
    e2e_status="failed"
    failed=1
  fi
fi

banner "Summary"
echo "  unit specs : $unit_status"
echo "  e2e specs  : $e2e_status"
echo ""
if [[ "$failed" -eq 0 ]]; then
  echo "  RESULT: PASS"
else
  echo "  RESULT: FAIL"
fi
echo ""
exit "$failed"
