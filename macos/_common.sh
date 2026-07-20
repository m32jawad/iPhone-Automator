#!/usr/bin/env bash
#
# _common.sh — shared helpers for run-sim.sh and start-gateway.sh.
# Sourced, not executed. Assumes `set -euo pipefail` in the caller.

MAC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$MAC_DIR/.." && pwd)"
VENV_PY="$MAC_DIR/.venv/bin/python"
LOG_DIR="$MAC_DIR/.logs"
APPIUM_URL="http://127.0.0.1:4723"

# tracks whether WE started Appium (so we only kill what we launched)
APPIUM_PID=""

msg()  { echo $'\033[36m'"==> $*"$'\033[0m'; }
warn() { echo $'\033[33m'"    $*"$'\033[0m'; }
die()  { echo $'\033[31m'"!! $*"$'\033[0m' >&2; exit 1; }

require_env() {
  [ -x "$VENV_PY" ] || die "Python env missing. Run ./macos/setup.sh first."
  command -v appium >/dev/null || die "Appium not on PATH. Run ./macos/setup.sh, then open a new shell."
  command -v xcrun  >/dev/null || die "xcrun not found — install Xcode."
}

# Resolve a simulator UDID from its device name (exact match, avoids "iPhone 17" vs "17 Pro").
resolve_sim_udid() {
  local name="$1"
  xcrun simctl list devices available \
    | grep -E "^[[:space:]]+${name} \(" \
    | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' \
    | head -1
}

# Return 0 if the given simulator UDID is currently Booted.
sim_is_booted() { xcrun simctl list devices | grep "$1" | grep -q "Booted"; }

# Boot the named simulator, open the Simulator UI, and echo its UDID.
boot_sim() {
  local name="$1" udid
  udid="$(resolve_sim_udid "$name")"
  [ -n "$udid" ] || die "No simulator named '$name'. List them with: xcrun simctl list devices available"
  msg "Booting simulator '$name' ($udid)" >&2
  open -a Simulator >/dev/null 2>&1 || true
  # bootstatus -b boots the device if needed and blocks until it finishes booting.
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
  sim_is_booted "$udid" || die "Simulator '$name' did not reach Booted state."
  echo "$udid"
}

appium_up() { curl -s -o /dev/null "$APPIUM_URL/status"; }

# Start Appium in the background if it isn't already listening. Logs to .logs/appium.log.
ensure_appium() {
  if appium_up; then
    msg "Appium already running at $APPIUM_URL" >&2
    return
  fi
  mkdir -p "$LOG_DIR"
  msg "Starting Appium (logs -> ${LOG_DIR#$REPO_DIR/}/appium.log)" >&2
  appium --log-timestamp >"$LOG_DIR/appium.log" 2>&1 &
  APPIUM_PID=$!
  local i
  for i in $(seq 1 30); do
    appium_up && { msg "Appium is up (pid $APPIUM_PID)" >&2; return; }
    kill -0 "$APPIUM_PID" 2>/dev/null || die "Appium exited early — see $LOG_DIR/appium.log"
    sleep 1
  done
  die "Appium did not become ready — see $LOG_DIR/appium.log"
}

# Kill Appium only if this script started it.
cleanup_appium() {
  if [ -n "$APPIUM_PID" ] && kill -0 "$APPIUM_PID" 2>/dev/null; then
    msg "Stopping Appium (pid $APPIUM_PID)" >&2
    kill "$APPIUM_PID" 2>/dev/null || true
  fi
}
