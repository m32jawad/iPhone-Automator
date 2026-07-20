#!/usr/bin/env bash
#
# setup.sh — idempotent installer + verifier for the iMessage gateway on macOS.
#
# The macOS counterpart of windows/setup.ps1. On a Mac you already have Xcode, so
# WebDriverAgent is built locally (by Appium, or by build-wda-sim.sh) instead of in
# the cloud — no Sideloadly, no iTunes drivers.
#
# Installs + verifies:
#   * Xcode + command-line tools   (builds WebDriverAgent for the sim / a device)
#   * Node.js                      (runs Appium)          — via Homebrew if missing
#   * Appium + the XCUITest driver (the automation server)
#   * Python venv at macos/.venv   (Flask gateway + Appium client)
#   * at least one iOS simulator   (so you can test in the sim)
#
# Usage:
#   ./macos/setup.sh              # install anything missing, then verify
#   ./macos/setup.sh --verify-only # check only, install nothing
#
# Safe to re-run: every step checks first and skips what is already good.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="$HERE/.venv"
VENV_PY="$VENV/bin/python"
REQ="$HERE/requirements.txt"

VERIFY_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --verify-only) VERIFY_ONLY=1 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//' | head -30; exit 0 ;;
    *) echo "Unknown flag: $arg (try --help)"; exit 2 ;;
  esac
done

# --- pretty output -----------------------------------------------------------
if [ -t 1 ]; then
  C_Y=$'\033[33m'; C_G=$'\033[32m'; C_R=$'\033[31m'; C_DIM=$'\033[2m'; C_C=$'\033[36m'; C_0=$'\033[0m'
else
  C_Y=""; C_G=""; C_R=""; C_DIM=""; C_C=""; C_0=""
fi
step() { echo "${C_Y}[..]${C_0} $*"; }
good() { echo "${C_G}[ok]${C_0} $*"; }
bad()  { echo "${C_R}[!!]${C_0} $*"; FAILED=1; }
note() { echo "${C_DIM}     $*${C_0}"; }
have() { command -v "$1" >/dev/null 2>&1; }

FAILED=0
declare -a RESULT_NAME RESULT_STATUS RESULT_DETAIL
record() { RESULT_NAME+=("$1"); RESULT_STATUS+=("$2"); RESULT_DETAIL+=("$3"); }

echo ""
echo "${C_C}=== iMessage gateway setup (macOS) ===${C_0}"
[ "$VERIFY_ONLY" = 1 ] && note "(verify-only: nothing will be installed)"
echo ""

# --- 0. Preflight: this must be macOS ---------------------------------------
if [ "$(uname -s)" != "Darwin" ]; then
  bad "This script is for macOS. On Windows use windows\\setup.ps1."
  exit 1
fi
if [ ! -f "$REQ" ]; then
  bad "requirements.txt not found next to this script — run it from the repo's macos/ folder."
  exit 1
fi

# --- 1. Xcode + command-line tools ------------------------------------------
# Building WDA for the simulator needs the FULL Xcode, not just the CLT shim.
XCODE_OK=0
if have xcodebuild && xcodebuild -version >/dev/null 2>&1; then
  XVER="$(xcodebuild -version | head -1)"
  DEV_DIR="$(xcode-select -p 2>/dev/null)"
  if echo "$DEV_DIR" | grep -q "Xcode.app"; then
    good "Xcode present ($XVER) at $DEV_DIR"
    XCODE_OK=1
  else
    bad "Only the Command Line Tools are selected ($DEV_DIR) — the full Xcode is required."
    note "Install Xcode from the App Store, then: sudo xcode-select -s /Applications/Xcode.app"
  fi
else
  bad "Xcode not found. Install it from the Mac App Store (free), then re-run."
  note "After install: sudo xcode-select -s /Applications/Xcode.app && sudo xcodebuild -license accept"
fi
record "Xcode" "$XCODE_OK" "$( [ "$XCODE_OK" = 1 ] && echo "$XVER" || echo 'install full Xcode' )"

# --- 2. Homebrew (only needed to install Node if it's missing) --------------
if have brew; then
  good "Homebrew available ($(brew --version | head -1))"
fi

# --- 3. Node.js --------------------------------------------------------------
NODE_OK=0
if have node; then
  good "Node.js already installed ($(node -v))"
  NODE_OK=1
elif [ "$VERIFY_ONLY" = 1 ]; then
  bad "Node.js missing"
elif have brew; then
  step "Installing Node.js via Homebrew"
  if brew install node; then good "Node.js installed ($(node -v))"; NODE_OK=1; else bad "Node.js install failed"; fi
else
  bad "Node.js missing and Homebrew isn't installed."
  note "Install Homebrew (https://brew.sh) or Node (https://nodejs.org), then re-run."
fi
record "Node.js" "$NODE_OK" "$( have node && node -v || echo 'not on PATH' )"

# --- 4. Appium + XCUITest driver --------------------------------------------
APPIUM_OK=0
if [ "$NODE_OK" = 0 ]; then
  bad "Skipping Appium — Node.js is missing"
else
  if have appium; then
    good "Appium already installed ($(appium -v))"
  elif [ "$VERIFY_ONLY" = 1 ]; then
    bad "Appium missing"
  else
    step "Installing Appium globally (npm i -g appium)"
    if npm install -g appium; then good "Appium installed ($(appium -v))"; else bad "Appium install failed"; fi
  fi

  if have appium; then
    if appium driver list --installed 2>&1 | grep -q "xcuitest"; then
      good "Appium XCUITest driver present"
      APPIUM_OK=1
    elif [ "$VERIFY_ONLY" = 1 ]; then
      bad "Appium XCUITest driver missing"
    else
      step "Installing the Appium XCUITest driver"
      appium driver install xcuitest || true
      if appium driver list --installed 2>&1 | grep -q "xcuitest"; then
        good "XCUITest driver installed"
        APPIUM_OK=1
      else
        bad "XCUITest driver install failed — try: appium driver install xcuitest"
      fi
    fi
  fi
fi
record "Appium + XCUITest" "$APPIUM_OK" "$( have appium && appium -v || echo 'see errors above' )"

# --- 5. Python venv + packages ----------------------------------------------
# A venv, not a global pip install: keeps Flask + the Appium client isolated.
PY=""
for cand in python3.12 python3.11 python3.10 python3 python3.13 python3.9; do
  if have "$cand"; then
    ver="$("$cand" -c 'import sys;print("%d.%d"%sys.version_info[:2])' 2>/dev/null)"
    case "$ver" in
      3.9|3.10|3.11|3.12|3.13) PY="$cand"; break ;;
    esac
  fi
done

VENV_OK=0
if [ -z "$PY" ]; then
  bad "No Python 3.9–3.13 found. Install one (brew install python@3.12) and re-run."
elif [ "$VERIFY_ONLY" = 1 ]; then
  if [ -x "$VENV_PY" ] && "$VENV_PY" -c 'import flask, appium' 2>/dev/null; then
    good "venv packages present"; VENV_OK=1
  else
    bad "venv missing or incomplete — run setup.sh without --verify-only"
  fi
else
  if [ ! -x "$VENV_PY" ]; then
    step "Creating virtual environment at macos/.venv (using $PY)"
    "$PY" -m venv "$VENV" || bad "Failed to create the venv"
  else
    good "venv already exists"
  fi
  if [ -x "$VENV_PY" ]; then
    step "Installing Python packages (Flask, Appium client)"
    "$VENV_PY" -m pip install --upgrade pip --quiet
    if "$VENV_PY" -m pip install -r "$REQ" --quiet; then
      if "$VENV_PY" -c 'import flask, appium' 2>/dev/null; then
        good "Python packages installed and importable"; VENV_OK=1
      else
        bad "Packages installed but failed to import"
      fi
    else
      bad "pip install failed"
    fi
  fi
fi
record "Python packages" "$VENV_OK" "$( [ "$VENV_OK" = 1 ] && echo 'flask + appium in .venv' || echo 're-run setup.sh' )"

# --- 6. iOS simulator available ---------------------------------------------
SIM_OK=0
if have xcrun && xcrun simctl list runtimes 2>/dev/null | grep -qi "iOS"; then
  RT="$(xcrun simctl list runtimes 2>/dev/null | grep -i 'iOS' | head -1 | sed 's/ (.*//')"
  good "iOS simulator runtime available ($RT)"
  SIM_OK=1
else
  bad "No iOS simulator runtime found."
  note "Open Xcode ▸ Settings ▸ Components and download an iOS simulator."
fi
record "iOS simulator" "$SIM_OK" "$( [ "$SIM_OK" = 1 ] && echo "$RT" || echo 'download in Xcode' )"

# --- 7. Summary --------------------------------------------------------------
echo ""
echo "${C_C}=== Summary ===${C_0}"
printf "%-20s %-9s %s\n" "Component" "Status" "Detail"
printf "%-20s %-9s %s\n" "---------" "------" "------"
MISSING=0
for i in "${!RESULT_NAME[@]}"; do
  if [ "${RESULT_STATUS[$i]}" = 1 ]; then st="${C_G}OK${C_0}     "; else st="${C_R}MISSING${C_0}"; MISSING=1; fi
  printf "%-20s %b %s\n" "${RESULT_NAME[$i]}" "$st" "${RESULT_DETAIL[$i]}"
done
echo ""

if [ "$VERIFY_ONLY" = 1 ]; then
  if [ "$MISSING" = 1 ]; then
    echo "${C_Y}Some components are missing. Re-run ./macos/setup.sh without --verify-only.${C_0}"; exit 1
  fi
  echo "${C_G}Everything checks out.${C_0}"; exit 0
fi

cat <<EOF
${C_DIM}NEXT STEPS:
  1. Test WebDriverAgent in the simulator (builds a sim WDA the first time):
        ./macos/run-sim.sh
  2. Or run the full gateway (Appium + Flask web UI) against the simulator:
        ./macos/start-gateway.sh --api-key "pick-a-secret"
        -> open http://localhost:5000

  Full details + troubleshooting:  macos/SETUP.md${C_0}
EOF

[ "$FAILED" = 1 ] && exit 1 || exit 0
