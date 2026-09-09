#!/bin/sh
# Runs an example device binary, mirroring its output to a log file that the
# test runner (and the compose healthcheck) can read to obtain the pairing code.
#
# Usage: E2E_DEVICE=matter_switch device-entrypoint.sh [args...]
set -eu

name="${E2E_DEVICE:?E2E_DEVICE must name an example binary, e.g. matter_switch}"

log_dir="${E2E_LOG_DIR:-/e2e/logs}"
mkdir -p "$log_dir"
log="$log_dir/$name.log"
: > "$log"

# Each device keeps its storage in its own working directory so a fresh
# container always starts un-commissioned.
mkdir -p "/e2e/state/$name"
cd "/e2e/state/$name"

"/app/bin/$name" --no-interactive "$@" </dev/null 2>&1 | tee "$log" &
pid=$!

term() {
  # `tee` is the last process in the pipeline; stopping the device flushes it.
  pkill -TERM -P $$ 2>/dev/null || true
  kill -TERM "$pid" 2>/dev/null || true
}
trap term TERM INT

wait "$pid"
