<#
  start-gateway.ps1 — launches the whole iMessage gateway.

  Auto-detects the connected iPhone, then opens 3 windows:
    1) tidevice wdaproxy  (launches WebDriverAgent on the phone + forwards port 8100)
    2) appium             (the automation server on port 4723)
    3) the Flask gateway  (the web UI + POST /send on port 5000)

  Usage:
      .\start-gateway.ps1 -ApiKey "your-secret"

  Requires: setup.ps1 already run, WebDriverAgent installed on the iPhone,
  and the iPhone plugged in + trusted.
#>

param(
    [string]$ApiKey = "change-me",
    [string]$WdaBundleId = "com.facebook.WebDriverAgentRunner.xctrunner",
    [int]$WdaPort = 8100
)

$ErrorActionPreference = "Stop"

# --- 0. Use the venv setup.ps1 built ------------------------------------------
# Python + tidevice live in windows\.venv, not on the system PATH. Call them by full
# path so this works in a fresh shell with no activation step.
$VenvPython = Join-Path $PSScriptRoot ".venv\Scripts\python.exe"
$Tidevice   = Join-Path $PSScriptRoot ".venv\Scripts\tidevice.exe"

if (-not (Test-Path $VenvPython) -or -not (Test-Path $Tidevice)) {
    Write-Host "The Python environment is missing. Run setup.ps1 first:" -ForegroundColor Red
    Write-Host "    powershell -ExecutionPolicy Bypass -File .\setup.ps1" -ForegroundColor Yellow
    exit 1
}

if (-not (Get-Command appium -ErrorAction SilentlyContinue)) {
    Write-Host "Appium isn't on PATH. Run setup.ps1, then open a NEW PowerShell window." -ForegroundColor Red
    exit 1
}

# --- 1. Is the Apple driver present? -----------------------------------------
if (-not (Get-Service -Name "Apple Mobile Device Service" -ErrorAction SilentlyContinue)) {
    Write-Host "Apple Mobile Device Service not found. Install iTunes (run setup.ps1) and reboot." -ForegroundColor Red
    exit 1
}

# --- 2. Auto-detect the iPhone UDID ------------------------------------------
Write-Host "Detecting iPhone..." -ForegroundColor Cyan
$udid = (& $Tidevice list --usb --one 2>$null | Select-Object -First 1)
if (-not $udid) {
    Write-Host "No iPhone detected over USB." -ForegroundColor Red
    Write-Host "  - Plug it in with a cable, tap 'Trust This Computer', enter the passcode." -ForegroundColor Yellow
    Write-Host "  - The cable must be a DATA cable, not charge-only." -ForegroundColor Yellow
    Write-Host "  - Then re-run this script." -ForegroundColor Yellow
    exit 1
}
$udid = $udid.Trim()
Write-Host "Found iPhone: $udid" -ForegroundColor Green

# --- 3. Confirm WebDriverAgent is installed on the phone ---------------------
$apps = & $Tidevice -u $udid applist 2>$null
if ($apps -notmatch "WebDriverAgentRunner") {
    Write-Host "WebDriverAgent is NOT installed on this iPhone." -ForegroundColor Red
    Write-Host "  Install WebDriverAgent.ipa with Sideloadly first (see SETUP.md)." -ForegroundColor Yellow
    exit 1
}

# --- 4. Launch the three services in their own windows -----------------------
Write-Host "`nLaunching services in separate windows..." -ForegroundColor Cyan

# (A) WDA proxy — launches WebDriverAgent on the phone and forwards its port.
Start-Process powershell -ArgumentList @(
    "-NoExit", "-Command",
    "Write-Host 'WDA PROXY (keep open)' -ForegroundColor Cyan; " +
    "& '$Tidevice' -u $udid wdaproxy -B $WdaBundleId --port $WdaPort"
)

# (B) Appium server.
Start-Process powershell -ArgumentList @(
    "-NoExit", "-Command",
    "Write-Host 'APPIUM SERVER (keep open)' -ForegroundColor Cyan; appium"
)

Start-Sleep -Seconds 3  # give them a moment to bind their ports

# (C) The Flask gateway — this window holds the UDID + API key in its env.
Start-Process powershell -ArgumentList @(
    "-NoExit", "-Command",
    "`$env:IPHONE_UDID='$udid'; `$env:API_KEY='$ApiKey'; " +
    "`$env:WDA_URL='http://127.0.0.1:$WdaPort'; " +
    "Write-Host 'GATEWAY SERVER (keep open)' -ForegroundColor Cyan; " +
    "Set-Location '$PSScriptRoot'; & '$VenvPython' server.py"
)

Write-Host @"

All three windows launched. Give it ~15-20 seconds, then:

  -> Open  http://localhost:5000  in your browser
  -> API key is: $ApiKey

If sending fails, check the WDA PROXY window first (it must show WDA is up on port $WdaPort).
"@ -ForegroundColor Gray
