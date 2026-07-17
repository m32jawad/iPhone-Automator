<#
  setup.ps1 — entry point. Run this right after cloning the repo:

      powershell -ExecutionPolicy Bypass -File .\setup.ps1

  It just forwards to windows\setup.ps1, which does the real work. Any flags you
  pass (-VerifyOnly, -SkipITunes, -SkipSideloadly) are handed straight through.
#>

$real = Join-Path $PSScriptRoot "windows\setup.ps1"
if (-not (Test-Path $real)) {
    Write-Host "windows\setup.ps1 not found — is this the repo root?" -ForegroundColor Red
    exit 1
}
& $real @args
exit $LASTEXITCODE
