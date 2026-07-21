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
#   --port N          web UI / server port                 (default: 5001)
#   --device NAME     simulator name for --target sim      (default: iPhone 17)
#   --udid UDID       device UDID for --target device      (default: auto-detect)
#   --team-id ID      Apple Team ID so Appium can sign WDA on a real device
#   --wda-url URL     use an already-running WDA (e.g. http://127.0.0.1:8100)
#   --wda-bundle-id B unique bundle id to build WDA under on a real device
#                     (default: com.imessagegateway.WebDriverAgentRunner — the stock
#                      com.facebook.* id is already registered to another team)
#
# NOTE: the default port is 5001, not 5000 — on macOS, port 5000 is taken by the
# AirPlay Receiver (System Settings > General > AirDrop & Handoff), which otherwise
# answers your browser with a 403.
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
PORT="5001"
DEVICE="iPhone 17"
UDID=""
TEAM_ID="${XCODE_TEAM_ID:-}"
WDA_URL_OPT=""
WDA_BUNDLE_ID=""

while [ $# -gt 0 ]; do
  case "$1" in
    --target)  TARGET="$2"; shift 2 ;;
    --api-key) API_KEY="$2"; shift 2 ;;
    --port)    PORT="$2"; shift 2 ;;
    --device)  DEVICE="$2"; shift 2 ;;
    --udid)    UDID="$2"; shift 2 ;;
    --team-id) TEAM_ID="$2"; shift 2 ;;
    --wda-url) WDA_URL_OPT="$2"; shift 2 ;;
    --wda-bundle-id) WDA_BUNDLE_ID="$2"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//' | head -32; exit 0 ;;
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
    # Only sign under a unique WDA bundle id when Appium builds WDA itself.
    if [ "$WDA_URL" = "auto" ]; then
      WDA_BUNDLE_ID="${WDA_BUNDLE_ID:-com.imessagegateway.WebDriverAgentRunner}"
    fi
    ;;
  *) die "--target must be 'sim' or 'device'." ;;
esac

ensure_appium

# --- make sure the web port is actually free (catches the AirPlay-on-5000 trap) --
if lsof -iTCP:"$PORT" -sTCP:LISTEN -n -P >/dev/null 2>&1; then
  holder="$(lsof -iTCP:"$PORT" -sTCP:LISTEN -n -P 2>/dev/null | awk 'NR==2{print $1}')"
  warn "Port $PORT is already in use by '${holder:-another process}'."
  [ "$PORT" = "5000" ] && warn "On macOS that's usually AirPlay Receiver — use --port 5001, or turn AirPlay Receiver off."
  die "Pick a free port with --port N (e.g. --port 5001)."
fi

# --- launch the Flask gateway (foreground; Ctrl-C stops it, trap stops Appium) --
msg "Starting the gateway server on http://localhost:$PORT  (api key: $API_KEY)"
echo ""
cd "$REPO_DIR/windows"
IPHONE_UDID="$UDID" \
API_KEY="$API_KEY" \
PORT="$PORT" \
APPIUM_SERVER="$APPIUM_URL" \
WDA_URL="$WDA_URL" \
XCODE_TEAM_ID="$TEAM_ID" \
WDA_BUNDLE_ID="$WDA_BUNDLE_ID" \
  "$VENV_PY" server.py
