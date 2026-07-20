#!/usr/bin/env bash
#
# start-gateway.sh — the full iMessage gateway on macOS (the port of start-gateway.ps1).
#
# Starts Appium + the Flask web UI / POST /send server. Unlike Windows, macOS builds
# WebDriverAgent locally, so there's no tidevice/wdaproxy step — Appium handles WDA.
#
#   --target sim      (default) boot a simulator and run against it
#   --target device   run against a connected, trusted iPhone
#   --api-key KEY     shared secret for POST /send        (default: change-me)
#   --device NAME     simulator name for --target sim      (default: iPhone 17)
#   --udid UDID       device UDID for --target device      (default: auto-detect)
#   --team-id ID      Apple Team ID so Appium can sign WDA on a real device
#   --wda-url URL     use an already-running WDA (e.g. http://127.0.0.1:8100)
#
# Examples:
#   ./macos/start-gateway.sh --api-key "s3cret"
#   ./macos/start-gateway.sh --target device --team-id ABCDE12345 --api-key "s3cret"
#
# Then open http://localhost:5000  (the web UI). Ctrl-C stops everything this started.
#
# NOTE: the SIMULATOR can't actually send an iMessage (no account / cellular). Use it
# to exercise the UI and the gateway plumbing; real sending needs --target device.

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

TARGET="sim"
API_KEY="change-me"
DEVICE="iPhone 17"
UDID=""
TEAM_ID="${XCODE_TEAM_ID:-}"
WDA_URL_OPT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --target)  TARGET="$2"; shift 2 ;;
    --api-key) API_KEY="$2"; shift 2 ;;
    --device)  DEVICE="$2"; shift 2 ;;
    --udid)    UDID="$2"; shift 2 ;;
    --team-id) TEAM_ID="$2"; shift 2 ;;
    --wda-url) WDA_URL_OPT="$2"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//' | head -28; exit 0 ;;
    *) die "Unknown flag: $1 (try --help)" ;;
  esac
done

require_env
[ -f "$REPO_DIR/windows/server.py" ] || die "windows/server.py not found — run from the repo."
trap cleanup_appium EXIT

# --- resolve the target device ----------------------------------------------
case "$TARGET" in
  sim)
    UDID="$(boot_sim "$DEVICE")"
    # No prebuilt WDA on the sim -> let Appium build one, unless the user forced a URL.
    WDA_URL="${WDA_URL_OPT:-auto}"
    ;;
  device)
    if [ -z "$UDID" ]; then
      msg "Auto-detecting a connected iPhone…"
      UDID="$(xcrun xctrace list devices 2>/dev/null \
              | sed -n '/== Devices ==/,/== Simulators ==/p' \
              | grep -iE 'iphone|ipad' \
              | grep -oE '\([0-9A-Fa-f-]{25,}\)$' | tr -d '()' | head -1)"
    fi
    [ -n "$UDID" ] || die "No connected iPhone found. Plug it in, tap 'Trust', or pass --udid."
    msg "Using device $UDID"
    WDA_URL="${WDA_URL_OPT:-auto}"
    [ -z "$TEAM_ID" ] && [ "$WDA_URL" = "auto" ] && \
      warn "No --team-id and no --wda-url: Appium may fail to sign WDA. Pass one of them if it does."
    ;;
  *) die "--target must be 'sim' or 'device'." ;;
esac

ensure_appium

# --- launch the Flask gateway (foreground; Ctrl-C stops it, trap stops Appium) --
msg "Starting the gateway server on http://localhost:5000  (api key: $API_KEY)"
echo ""
cd "$REPO_DIR/windows"
IPHONE_UDID="$UDID" \
API_KEY="$API_KEY" \
APPIUM_SERVER="$APPIUM_URL" \
WDA_URL="$WDA_URL" \
XCODE_TEAM_ID="$TEAM_ID" \
  "$VENV_PY" server.py
