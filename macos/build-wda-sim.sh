#!/usr/bin/env bash
#
# build-wda-sim.sh — build WebDriverAgent for the iOS SIMULATOR.
#
# The prebuilt Payload/WebDriverAgentRunner-Runner.app (and the WebDriverAgent*.zip)
# in this repo are DEVICE builds (iphoneos, arm64) — they install onto the simulator
# but refuse to launch ("denied by SBMainWorkspace"). This script produces the
# missing simulator counterpart, the same way the GitHub workflow builds the device
# one, just with an "iOS Simulator" destination and no code signing.
#
# Output:  macos/build/sim/WebDriverAgentRunner-Runner.app
#
# Usage:
#   ./macos/build-wda-sim.sh            # build only
#   ./macos/build-wda-sim.sh --install  # also install onto the booted simulator
#
# Note: you rarely need this — run-sim.sh / start-gateway.sh let Appium build and
# launch WDA for you. Use this when you want a standalone .app to inspect or install.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/.wda-src"          # WebDriverAgent checkout (gitignored)
BUILD="$HERE/build/wda"        # derived data (gitignored)
OUT="$HERE/build/sim"          # where we drop the finished .app
WDA_REF="${WDA_REF:-master}"

INSTALL=0
[ "${1:-}" = "--install" ] && INSTALL=1

command -v xcodebuild >/dev/null || { echo "xcodebuild not found — install Xcode."; exit 1; }

# 1. Get the WebDriverAgent source (same repo the cloud workflow checks out).
if [ ! -d "$SRC/.git" ]; then
  echo "==> Cloning appium/WebDriverAgent ($WDA_REF)…"
  git clone --depth 1 --branch "$WDA_REF" https://github.com/appium/WebDriverAgent.git "$SRC"
else
  echo "==> Reusing existing WebDriverAgent checkout at $SRC"
fi

# 2. Build the runner for the simulator SDK. Simulator apps need no signing.
echo "==> Building WebDriverAgentRunner for the iOS Simulator (first build takes a few minutes)…"
xcodebuild build-for-testing \
  -project "$SRC/WebDriverAgent.xcodeproj" \
  -scheme WebDriverAgentRunner \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$BUILD" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  | { command -v xcbeautify >/dev/null && xcbeautify || cat; }

# 3. Copy the finished .app out to a stable, easy-to-find location.
APP_PATH="$(find "$BUILD/Build/Products" -name 'WebDriverAgentRunner-Runner.app' -type d | head -n1)"
[ -n "$APP_PATH" ] || { echo "::error:: Runner app not found after build"; exit 1; }
mkdir -p "$OUT"
rm -rf "$OUT/WebDriverAgentRunner-Runner.app"
cp -R "$APP_PATH" "$OUT/"
echo ""
echo "==> Built: $OUT/WebDriverAgentRunner-Runner.app"
otool -l "$OUT/WebDriverAgentRunner-Runner.app/WebDriverAgentRunner-Runner" 2>/dev/null \
  | grep -A1 LC_BUILD_VERSION | grep platform | sed 's/^/    (platform check) /' || true

# 4. Optionally install onto the booted simulator.
if [ "$INSTALL" = 1 ]; then
  if ! xcrun simctl list devices | grep -q "(Booted)"; then
    echo "==> No simulator booted. Boot one first, e.g.:  xcrun simctl boot 'iPhone 17' && open -a Simulator"
    exit 1
  fi
  echo "==> Installing onto the booted simulator…"
  xcrun simctl install booted "$OUT/WebDriverAgentRunner-Runner.app"
  echo "==> Installed. (WDA is an XCTest runner — it's driven by Appium / xcodebuild test,"
  echo "    not by tapping it. run-sim.sh does that for you.)"
fi
