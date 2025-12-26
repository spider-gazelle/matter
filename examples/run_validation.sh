#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

mkdir -p ./bin/

usage() {
  cat <<'EOF'
Run end-to-end commissioning + device validation against the local example device.

Defaults:
  - Builds `./bin/matter_switch` and `./bin/chip-tool-crystal`
  - Starts the device locally (UDP 5540)
  - Commissions Node 1 using the printed manual pairing code
  - Runs `examples/device_validation.cr` using `./bin/chip-tool-crystal`

Env vars:
  CRYSTAL_CACHE_DIR   Crystal cache directory (default: ./tmp/.crystal_cache)
  CHIP_TOOL           chip-tool binary for validation (default: ./bin/chip-tool-crystal)
  MATTER_PEER_ADDRESS Device address (default: 127.0.0.1:5540)

Options:
  --address ADDR      Device address ip[:port] (overrides MATTER_PEER_ADDRESS)
  --chip-tool PATH    chip-tool binary for validation (overrides CHIP_TOOL)
  --storage-a DIR     Storage directory for Fabric A (default: tmp/device_validation/chip-tool-a-<timestamp>)
  --skip-build        Skip building binaries
  --keep-device-state Don't delete `matter_switch_storage.json` before starting
  --log PATH          Device stdout/stderr log path (default: ./bin/matter_switch_run.log)
  -h, --help          Show this help
EOF
}

ADDRESS="${MATTER_PEER_ADDRESS:-127.0.0.1:5540}"
CHIP_TOOL_BIN="${CHIP_TOOL:-./bin/chip-tool-crystal}"
STORAGE_A=""
SKIP_BUILD=0
KEEP_DEVICE_STATE=0
DEVICE_LOG="./bin/matter_switch_run.log"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --address)
      ADDRESS="${2:-}"; shift 2
      ;;
    --chip-tool)
      CHIP_TOOL_BIN="${2:-}"; shift 2
      ;;
    --storage-a)
      STORAGE_A="${2:-}"; shift 2
      ;;
    --skip-build)
      SKIP_BUILD=1; shift
      ;;
    --keep-device-state)
      KEEP_DEVICE_STATE=1; shift
      ;;
    --log)
      DEVICE_LOG="${2:-}"; shift 2
      ;;
    -h|--help)
      usage; exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

export CRYSTAL_CACHE_DIR="${CRYSTAL_CACHE_DIR:-./tmp/.crystal_cache}"
mkdir -p "$CRYSTAL_CACHE_DIR"

if [[ -z "$STORAGE_A" ]]; then
  STORAGE_A="./tmp/device_validation/chip-tool-a-$(date +%s)"
fi
mkdir -p "$STORAGE_A"

if [[ "$SKIP_BUILD" -ne 1 ]]; then
  echo "==> Building binaries"
  crystal build ./examples/chip-tool.cr -o ./bin/chip-tool-crystal --error-trace
  crystal build ./examples/matter_switch_device.cr -o ./bin/matter_switch --error-trace
fi

if [[ "$KEEP_DEVICE_STATE" -ne 1 ]]; then
  rm -f ./matter_switch_storage.json
fi

echo "==> Starting device (log: $DEVICE_LOG)"
rm -f "$DEVICE_LOG"
./bin/matter_switch --no-interactive >"$DEVICE_LOG" 2>&1 &
DEV_PID=$!

cleanup() {
  kill "$DEV_PID" 2>/dev/null || true
  wait "$DEV_PID" 2>/dev/null || true
}
trap cleanup EXIT

echo "==> Waiting for pairing code..."
for _ in $(seq 1 400); do
  if grep -q "chip-tool pairing code 1" "$DEVICE_LOG"; then
    break
  fi
  sleep 0.05
done

PAIR_LINE="$(grep "chip-tool pairing code 1" "$DEVICE_LOG" | head -n 1 || true)"
MANUAL_CODE="$(echo "$PAIR_LINE" | sed -n 's/.*chip-tool pairing code 1 \([0-9-]*\).*/\1/p')"

if [[ -z "$MANUAL_CODE" ]]; then
  echo "ERROR: failed to extract manual pairing code from log" >&2
  tail -n 120 "$DEVICE_LOG" >&2 || true
  exit 1
fi

echo "==> Pairing code: $MANUAL_CODE"
echo "==> Commissioning with ./bin/chip-tool-crystal (storage: $STORAGE_A, address: $ADDRESS)"
./bin/chip-tool-crystal pairing code 1 "$MANUAL_CODE" --address "$ADDRESS" --storage-directory "$STORAGE_A"

echo "==> Running device validation (chip-tool: $CHIP_TOOL_BIN)"
export CHIP_TOOL="$CHIP_TOOL_BIN"
export MATTER_PEER_ADDRESS="$ADDRESS"
crystal run ./examples/device_validation.cr -- --chip-tool "$CHIP_TOOL_BIN" --storage-a "$STORAGE_A"

echo "==> PASS"

