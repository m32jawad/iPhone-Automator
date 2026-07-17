<#
  setup.ps1 — complete, idempotent installer for the iMessage gateway (Windows 11).

  Run it ONCE after cloning the repo, in a normal PowerShell window:

      cd <repo>\windows
      powershell -ExecutionPolicy Bypass -File .\setup.ps1

  It installs and VERIFIES:
    * Node.js LTS               (runs Appium)
    * Python 3.9-3.13           (runs the gateway; only installed if missing)
    * iTunes                    (the Apple USB drivers — nothing else needs iTunes)
    * .venv + Python packages   (Flask, Appium client, tidevice)
    * Appium + the XCUITest driver
    * Sideloadly                (opens the download page — it has no silent installer)

  Safe to re-run: every step checks first and skips what is already good.

  Flags:
    -VerifyOnly      check what's installed, change nothing
    -SkipITunes      don't touch iTunes (use if the Apple drivers already work)
    -SkipSideloadly  don't open the Sideloadly download page

  Some installs (iTunes) pop a UAC prompt — click Yes.
#>

[CmdletBinding()]
param(
    [switch]$VerifyOnly,
    [switch]$SkipITunes,
    [switch]$SkipSideloadly
)

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"   # makes Invoke-WebRequest much faster

# Any Python in [3.9, 3.14) works — flask, the Appium client and tidevice all ship
# wheels for those. If a usable one is already here we use it as-is and install nothing;
# 3.12 is only the version we fetch when the machine has no suitable Python at all.
$PY_TARGET = "3.12"
$PY_WINGET = "Python.Python.3.12"
$PY_MIN    = [version]"3.9"
$PY_MAX    = [version]"3.14"   # exclusive upper bound

$VenvPath         = Join-Path $PSScriptRoot ".venv"
$VenvPython       = Join-Path $VenvPath "Scripts\python.exe"
$RequirementsFile = Join-Path $PSScriptRoot "requirements.txt"

$script:Results     = [ordered]@{}
$script:NeedsReboot = $false
$script:Failed      = $false

function Have($cmd) { [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }

function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [Environment]::GetEnvironmentVariable("Path", "User")
}

function Add-ToUserPath($dir) {
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -notlike "*$dir*") {
        [Environment]::SetEnvironmentVariable("Path", "$userPath;$dir", "User")
    }
    Refresh-Path
}

function Step($msg) { Write-Host "[..] $msg" -ForegroundColor Yellow }
function Good($msg) { Write-Host "[ok] $msg" -ForegroundColor Green }
function Bad($msg)  { Write-Host "[!!] $msg" -ForegroundColor Red; $script:Failed = $true }
function Note($msg) { Write-Host "     $msg" -ForegroundColor DarkGray }

function Set-Result($name, $ok, $detail) {
    $script:Results[$name] = [pscustomobject]@{
        Component = $name
        Status    = $(if ($ok) { "OK" } else { "MISSING" })
        Detail    = $detail
    }
}

# Every native command below goes through this.
#
# Why: in PowerShell 5.1, redirecting a native exe's stderr (2>&1 / 2>$null) wraps each
# stderr line in an ErrorRecord. With $ErrorActionPreference='Stop' that becomes a fatal
# NativeCommandError — so a probe like `py -3.11` on a machine without 3.11 doesn't just
# report "not found", it kills the whole script. Demote errors for the call and report
# the exit code as plain data instead.
function Invoke-Native {
    param([string]$Exe, [string[]]$Arguments = @())

    $old = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $out  = & $Exe @Arguments 2>&1 | Out-String
        $code = $LASTEXITCODE
        return [pscustomobject]@{ Ok = ($code -eq 0); Code = $code; Output = $out.Trim() }
    } catch {
        return [pscustomobject]@{ Ok = $false; Code = -1; Output = "$_" }
    } finally {
        $ErrorActionPreference = $old
    }
}

# winget returns non-zero for harmless outcomes ("already installed", "no upgrade").
# Treat those as success; anything else is a real failure worth surfacing.
function Invoke-Winget {
    param([string]$Id, [switch]$Silent)

    $wgArgs = @("install", "--id", $Id, "-e",
                "--accept-package-agreements", "--accept-source-agreements")
    if ($Silent) { $wgArgs += "--silent" }

    $r    = Invoke-Native "winget" $wgArgs
    $out  = $r.Output
    $code = $r.Code

    $okCodes = @(
        0,
        -1978335189,  # 0x8A15002B  no applicable upgrade / already installed
        -1978335216,  # 0x8A150010  package already installed
        -1978334967   # 0x8A150109  reboot required to finish
    )
    if ($code -eq -1978334967) { $script:NeedsReboot = $true }
    if ($okCodes -contains $code) { return $true }

    Write-Host $out -ForegroundColor DarkGray
    Note "winget exited with code $code for $Id"
    return $false
}

# Finds a REAL python.exe, deliberately ignoring the Microsoft Store alias stub in
# WindowsApps. That stub answers `Get-Command python` on a fresh Windows 11 but is not
# Python — it just opens the Store. A bare `if (Have python)` therefore reports success
# on a machine with no Python at all, and the pip step then fails.
function Find-RealPython {
    $cands = New-Object System.Collections.Generic.List[string]

    # 1. the py launcher, asked for our exact target version
    if (Have py) {
        $r = Invoke-Native "py" @("-$PY_TARGET", "-c", "import sys; print(sys.executable)")
        if ($r.Ok -and $r.Output) { $cands.Add($r.Output) }
    }
    # 2. anything named python on PATH that is NOT the Store stub
    foreach ($c in (Get-Command python -All -ErrorAction SilentlyContinue)) {
        if ($c.Source -and $c.Source -notlike "*WindowsApps*") { $cands.Add($c.Source) }
    }
    # 3. the usual install locations
    $globs = @(
        "$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe",
        "$env:ProgramFiles\Python3*\python.exe",
        "C:\Python3*\python.exe"
    )
    foreach ($g in $globs) {
        foreach ($f in (Get-ChildItem $g -ErrorAction SilentlyContinue)) { $cands.Add($f.FullName) }
    }

    $found = @()
    foreach ($c in ($cands | Select-Object -Unique)) {
        if (-not (Test-Path $c)) { continue }
        $r = Invoke-Native $c @("-c", "import sys; print('%d.%d' % sys.version_info[:2])")
        if ($r.Ok -and $r.Output -match '^\d+\.\d+$') {
            $found += [pscustomobject]@{ Path = $c; Version = [version]$r.Output }
        }
    }
    if (-not $found) { return $null }

    # prefer the exact target, then any supported version, newest first
    $exact = $found | Where-Object { $_.Version -eq [version]$PY_TARGET } | Select-Object -First 1
    if ($exact) { return $exact }
    return $found |
        Where-Object { $_.Version -ge $PY_MIN -and $_.Version -lt $PY_MAX } |
        Sort-Object Version -Descending |
        Select-Object -First 1
}

function Get-NpmPrefix {
    if (-not (Have npm)) { return $null }
    $r = Invoke-Native "npm" @("config", "get", "prefix")
    if ($r.Ok -and $r.Output) {
        $p = ($r.Output -split "`r?`n" | Select-Object -First 1).Trim()
        if ($p -and (Test-Path $p)) { return $p }
    }
    return "$env:APPDATA\npm"
}

Write-Host "`n=== iMessage gateway setup ===`n" -ForegroundColor Cyan
if ($VerifyOnly) { Write-Host "(verify-only: nothing will be installed)`n" -ForegroundColor DarkGray }

# --- 0. Preflight ------------------------------------------------------------
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Bad "PowerShell 5+ required (found $($PSVersionTable.PSVersion))."
    exit 1
}
if (-not (Test-Path $RequirementsFile)) {
    Bad "requirements.txt not found next to this script — run it from the repo's windows\ folder."
    exit 1
}
# -VerifyOnly installs nothing, so it doesn't need winget — don't block on it there.
if (Have winget) {
    Good "winget available"
} elseif ($VerifyOnly) {
    Note "winget not found (fine for -VerifyOnly; you'd need it to actually install)."
} else {
    Bad "winget not found."
    Note "Install/update 'App Installer' from the Microsoft Store, reopen PowerShell, re-run."
    exit 1
}

# --- 1. Node.js --------------------------------------------------------------
if (Have node) {
    Good "Node.js already installed ($(node -v))"
} elseif ($VerifyOnly) {
    Bad "Node.js missing"
} else {
    Step "Installing Node.js LTS"
    if (Invoke-Winget -Id "OpenJS.NodeJS.LTS" -Silent) { Refresh-Path }
    if (-not (Have node)) {
        # winget puts node under Program Files; PATH sometimes only lands next session
        $nodeDir = "$env:ProgramFiles\nodejs"
        if (Test-Path "$nodeDir\node.exe") { Add-ToUserPath $nodeDir }
    }
    if (Have node) { Good "Node.js installed ($(node -v))" } else { Bad "Node.js install failed" }
}
Set-Result "Node.js" (Have node) $(if (Have node) { (node -v) } else { "not on PATH" })

# --- 2. Python ---------------------------------------------------------------
$py = Find-RealPython
if ($py) {
    Good "Python already installed ($($py.Version) at $($py.Path))"
} elseif ($VerifyOnly) {
    Bad "No Python in the supported range ($PY_MIN - $PY_MAX exclusive)"
} else {
    Step "Installing Python $PY_TARGET"
    Note "Any existing Python is left alone — this installs alongside it."
    if (Invoke-Winget -Id $PY_WINGET -Silent) { Refresh-Path }
    $py = Find-RealPython
    if ($py) {
        Good "Python installed ($($py.Version) at $($py.Path))"
    } else {
        Bad "Python install failed — install $PY_TARGET from python.org, tick 'Add to PATH', re-run"
    }
}
Set-Result "Python" ($null -ne $py) $(if ($py) { "$($py.Version) — $($py.Path)" } else { "need $PY_MIN-$PY_MAX" })

# --- 3. iTunes (Apple Mobile Device drivers / usbmuxd) -----------------------
# Only the USB driver matters. Without it tidevice cannot see the iPhone at all.
$appleSvc = Get-Service -Name "Apple Mobile Device Service" -ErrorAction SilentlyContinue
if ($appleSvc) {
    Good "Apple Mobile Device Service present (status: $($appleSvc.Status))"
    if ($appleSvc.Status -ne "Running") {
        Note "Service isn't running — a reboot usually fixes it."
        $script:NeedsReboot = $true
    }
} elseif ($SkipITunes) {
    Note "Skipping iTunes (-SkipITunes), but no Apple driver is present — the phone won't be detected."
} elseif ($VerifyOnly) {
    Bad "Apple Mobile Device Service missing (install iTunes)"
} else {
    Step "Installing iTunes for the Apple USB drivers — accept the UAC prompt"
    Note "Slowest step (~2-5 min). Nothing else needs iTunes itself."
    if (Invoke-Winget -Id "Apple.iTunes") {
        $script:NeedsReboot = $true
        Start-Sleep -Seconds 2
        if (Get-Service -Name "Apple Mobile Device Service" -ErrorAction SilentlyContinue) {
            Good "Apple drivers installed"
        } else {
            Note "Drivers register on reboot — that's expected."
        }
    } else {
        Bad "iTunes install failed — install it manually from apple.com/itunes, then reboot"
    }
}
$appleOk = [bool](Get-Service -Name "Apple Mobile Device Service" -ErrorAction SilentlyContinue)
Set-Result "Apple drivers" $appleOk $(if ($appleOk) { "Apple Mobile Device Service found" } else { "install iTunes + reboot" })

# --- 4. Python venv + packages ----------------------------------------------
# A venv, not a global pip install: global installs hit permission errors, collide with
# other projects, and leave tidevice.exe off PATH — which is exactly what start-gateway.ps1
# needs to find the phone. Everything lives in windows\.venv now.
$venvOk = $false
if (-not $py) {
    Bad "Skipping Python packages — no usable Python"
} elseif ($VerifyOnly) {
    if (Test-Path $VenvPython) {
        $mods = Invoke-Native $VenvPython @("-c", "import flask, appium, tidevice; print('ok')")
        if ($mods.Ok -and $mods.Output -eq "ok") { Good "venv packages present"; $venvOk = $true }
        else { Bad "venv exists but packages are incomplete" }
    } else { Bad "venv missing" }
} else {
    if (-not (Test-Path $VenvPython)) {
        Step "Creating virtual environment at .venv"
        $mk = Invoke-Native $py.Path @("-m", "venv", $VenvPath)
        if (-not (Test-Path $VenvPython)) {
            Bad "Failed to create the venv"
            if ($mk.Output) { Note $mk.Output }
        }
    } else {
        Good "venv already exists"
    }

    if (Test-Path $VenvPython) {
        Step "Installing Python packages (Flask, Appium client, tidevice)"
        Invoke-Native $VenvPython @("-m", "pip", "install", "--upgrade", "pip", "--quiet") | Out-Null
        $pip = Invoke-Native $VenvPython @("-m", "pip", "install", "-r", $RequirementsFile)
        if (-not $pip.Ok) {
            Bad "pip install failed:"
            Write-Host $pip.Output -ForegroundColor DarkGray
        } else {
            # Importing is the real test — pip can 'succeed' and still leave a broken env.
            $mods = Invoke-Native $VenvPython @("-c", "import flask, appium, tidevice; print('ok')")
            if ($mods.Ok -and $mods.Output -eq "ok") {
                Good "Python packages installed and importable"
                $venvOk = $true
            } else {
                Bad "Packages installed but failed to import:"
                Write-Host $mods.Output -ForegroundColor DarkGray
            }
        }
    }
}
Set-Result "Python packages" $venvOk $(if ($venvOk) { "flask + appium + tidevice in .venv" } else { "re-run setup.ps1" })

# --- 5. Appium + XCUITest driver --------------------------------------------
$appiumOk = $false
if (-not (Have node)) {
    Bad "Skipping Appium — Node.js is missing"
} else {
    $npmPrefix = Get-NpmPrefix
    if ($npmPrefix) { Add-ToUserPath $npmPrefix }   # npm's global bin is often off PATH

    if (Have appium) {
        Good "Appium already installed ($(appium -v))"
    } elseif ($VerifyOnly) {
        Bad "Appium missing"
    } else {
        Step "Installing Appium globally (npm)"
        $npmR = Invoke-Native "npm" @("install", "-g", "appium")
        Refresh-Path
        if (Have appium) {
            Good "Appium installed ($(appium -v))"
        } else {
            Bad "Appium install failed:"
            Write-Host $npmR.Output -ForegroundColor DarkGray
        }
    }

    if (Have appium) {
        # The iOS driver is a separate install and is the piece most often missed —
        # Appium starts fine without it and only fails at the first send.
        # (appium logs to stderr, so this must go through Invoke-Native.)
        $drivers = (Invoke-Native "appium" @("driver", "list", "--installed")).Output
        if ($drivers -match "xcuitest") {
            Good "Appium XCUITest driver present"
            $appiumOk = $true
        } elseif ($VerifyOnly) {
            Bad "Appium XCUITest driver missing"
        } else {
            Step "Installing the Appium XCUITest driver"
            $inst = Invoke-Native "appium" @("driver", "install", "xcuitest")
            $drivers = (Invoke-Native "appium" @("driver", "list", "--installed")).Output
            if ($drivers -match "xcuitest") {
                Good "XCUITest driver installed"
                $appiumOk = $true
            } else {
                Bad "XCUITest driver install failed — try: appium driver install xcuitest"
                Write-Host $inst.Output -ForegroundColor DarkGray
            }
        }
    }
}
Set-Result "Appium + XCUITest" $appiumOk $(if ($appiumOk) { (appium -v) } else { "see errors above" })

# --- 6. Sideloadly (manual — not in winget, no silent installer) -------------
$sideloadly = @(
    "$env:LOCALAPPDATA\Programs\Sideloadly\sideloadly.exe",
    "$env:ProgramFiles\Sideloadly\sideloadly.exe",
    "${env:ProgramFiles(x86)}\Sideloadly\sideloadly.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($sideloadly) {
    Good "Sideloadly installed ($sideloadly)"
} elseif ($VerifyOnly -or $SkipSideloadly) {
    Note "Sideloadly not installed — needed once, to put WebDriverAgent on the iPhone."
} else {
    Step "Sideloadly isn't in winget — opening the download page"
    Note "Install it, then come back. It's only needed to put WDA on the phone."
    Start-Process "https://sideloadly.io"
}
Set-Result "Sideloadly" ([bool]$sideloadly) $(if ($sideloadly) { "installed" } else { "install from sideloadly.io" })

# --- 7. Summary --------------------------------------------------------------
Write-Host "`n=== Summary ===`n" -ForegroundColor Cyan
$script:Results.Values | Format-Table -AutoSize | Out-String | Write-Host

$missing = @($script:Results.Values | Where-Object { $_.Status -ne "OK" })

if ($VerifyOnly) {
    if ($missing) {
        Write-Host "Some components are missing. Re-run setup.ps1 without -VerifyOnly.`n" -ForegroundColor Yellow
        exit 1
    }
    Write-Host "Everything checks out.`n" -ForegroundColor Green
    exit 0
}

if ($script:NeedsReboot) {
    Write-Host "REBOOT REQUIRED — the Apple USB drivers only register after a restart." -ForegroundColor Yellow
    Write-Host "Reboot, then run  .\setup.ps1 -VerifyOnly  to confirm everything is good.`n" -ForegroundColor Yellow
}

Write-Host @"
NEXT STEPS:
  1. $(if ($script:NeedsReboot) { "REBOOT the PC (iTunes drivers), then continue." } else { "No reboot needed." })
  2. Build WebDriverAgent.ipa:  GitHub -> Actions -> 'Build WebDriverAgent' -> Run workflow
     -> download the artifact -> unzip -> WebDriverAgent.ipa
  3. Plug in the iPhone, tap 'Trust This Computer'.
  4. Sideloadly -> drag in WebDriverAgent.ipa -> enter the iPhone's Apple ID -> Start.
  5. On the phone: Settings -> General -> VPN & Device Management -> trust your Apple ID.
     Settings -> Privacy & Security -> Developer Mode -> ON (the phone reboots).
     Settings -> Display & Brightness -> Auto-Lock -> Never.
  6. Start it up:
        .\start-gateway.ps1 -ApiKey "pick-a-secret"
  7. Open http://localhost:5000 and send a message.

Full details, including troubleshooting:  SETUP.md
"@ -ForegroundColor Gray

if ($script:Failed) { exit 1 }
