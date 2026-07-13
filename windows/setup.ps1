<#
  setup.ps1 — one-shot installer for the iMessage gateway (Windows 11).

  Installs: Node.js, Python, iTunes (Apple device drivers), Appium + iOS driver,
  and the Python packages. Run it ONCE in a normal PowerShell window:

      cd <repo>\windows
      powershell -ExecutionPolicy Bypass -File .\setup.ps1

  Some installs (iTunes) may pop a UAC prompt — click Yes.
#>

$ErrorActionPreference = "Stop"

function Have($cmd) { [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }

function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [Environment]::GetEnvironmentVariable("Path", "User")
}

Write-Host "`n=== iMessage gateway setup ===`n" -ForegroundColor Cyan

# --- 0. winget must exist (built into Windows 11) ----------------------------
if (-not (Have winget)) {
    Write-Host "winget not found. Update 'App Installer' from the Microsoft Store, then re-run." -ForegroundColor Red
    exit 1
}

# --- 1. Node.js --------------------------------------------------------------
if (Have node) {
    Write-Host "[ok] Node.js already installed ($(node -v))" -ForegroundColor Green
} else {
    Write-Host "[..] Installing Node.js LTS" -ForegroundColor Yellow
    winget install --id OpenJS.NodeJS.LTS -e --accept-package-agreements --accept-source-agreements
    Refresh-Path
}

# --- 2. Python ---------------------------------------------------------------
if (Have python) {
    Write-Host "[ok] Python already installed ($(python --version))" -ForegroundColor Green
} else {
    Write-Host "[..] Installing Python 3.12" -ForegroundColor Yellow
    winget install --id Python.Python.3.12 -e --accept-package-agreements --accept-source-agreements
    Refresh-Path
}

# --- 3. iTunes (Apple Mobile Device drivers / usbmuxd) -----------------------
$appleSvc = Get-Service -Name "Apple Mobile Device Service" -ErrorAction SilentlyContinue
if ($appleSvc) {
    Write-Host "[ok] Apple Mobile Device Service present" -ForegroundColor Green
} else {
    Write-Host "[..] Installing iTunes (Apple device drivers) — accept the UAC prompt" -ForegroundColor Yellow
    winget install --id Apple.iTunes -e --accept-package-agreements --accept-source-agreements
    Write-Host "    NOTE: a REBOOT is recommended after iTunes installs." -ForegroundColor Yellow
}

# --- 4. Python packages ------------------------------------------------------
Write-Host "[..] Installing Python packages (Appium client, Flask, tidevice)" -ForegroundColor Yellow
python -m pip install --upgrade pip | Out-Null
python -m pip install -r "$PSScriptRoot\requirements.txt"

# --- 5. Appium + iOS driver --------------------------------------------------
if (Have appium) {
    Write-Host "[ok] Appium already installed ($(appium -v))" -ForegroundColor Green
} else {
    Write-Host "[..] Installing Appium globally" -ForegroundColor Yellow
    npm install -g appium
    # npm's global bin often isn't on PATH — add it permanently.
    $npmBin = "$env:APPDATA\npm"
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -notlike "*$npmBin*") {
        [Environment]::SetEnvironmentVariable("Path", "$userPath;$npmBin", "User")
    }
    Refresh-Path
}

Write-Host "[..] Ensuring the XCUITest driver is installed" -ForegroundColor Yellow
& "$env:APPDATA\npm\appium.cmd" driver install xcuitest 2>$null
if (-not $?) { & "$env:APPDATA\npm\appium.cmd" driver update xcuitest 2>$null }

Write-Host "`n=== Setup complete ===" -ForegroundColor Cyan
Write-Host @"

NEXT STEPS:
  1. If iTunes was just installed, REBOOT the PC.
  2. Get WebDriverAgent.ipa (GitHub Actions artifact) and install it on the iPhone
     with Sideloadly  ->  see SETUP.md 'iPhone' section.
  3. Plug in the iPhone, tap 'Trust', then run:
        .\start-gateway.ps1
  4. Open http://localhost:5000 in a browser and send a message.

"@ -ForegroundColor Gray
