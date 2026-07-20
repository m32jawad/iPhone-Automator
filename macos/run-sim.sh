#!/usr/bin/env bash
#
# run-sim.sh — the fast "test the app in the simulator" path.
#
# Boots an iPhone simulator, starts Appium, and runs the Messages automation smoke
# test (sim_smoke.py). Appium builds & launches a *simulator* WebDriverAgent for you,
# so the first run compiles WDA and can take a few minutes.
#
# This proves the WebDriverAgent -> UI-driving chain works in the sim. It does NOT
# send a real iMessage — the simulator can't (no account / no cellular). For real
# sending you need a physical iPhone (see start-gateway.sh --target device).
#
# Usage:
#   ./macos/run-sim.sh                 # default device "iPhone 17"
#   ./macos/run-sim.sh --device "iPhone 17 Pro"

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

DEVICE="iPhone 17"
while [ $# -gt 0 ]; do
  case "$1" in
    --device) DEVICE="$2"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//' | head -20; exit 0 ;;
    *) die "Unknown flag: $1 (try --help)" ;;
  esac
done

require_env
trap cleanup_appium EXIT

UDID="$(boot_sim "$DEVICE")"
ensure_appium

msg "Running the Messages automation smoke test in the simulator…"
SIM_UDID="$UDID" APPIUM_SERVER="$APPIUM_URL" "$VENV_PY" "$MAC_DIR/sim_smoke.py"
