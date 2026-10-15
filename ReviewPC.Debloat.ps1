<#
  ReviewPC.Debloat.ps1
  Runs Win11Debloat with safe, recommended flags
  Part of the ReviewPC setup suite

  Windows-on-ARM (arm64v2): This step is ARCH-AGNOSTIC. Win11Debloat performs
  registry + Appx/Start-menu operations that behave identically on x64 and
  ARM64 hosts, and it deliberately keeps the App Installer (winget) intact,
  which the ARM64 install path relies on. No per-archive changes are required.
  The remote payload (https://debloat.raphi.re/) is fetched at runtime and run
  in a child PowerShell; a download failure or non-zero exit is reported.
#>

param(
  [switch]$SysprepMode,
  [switch]$Silent = $true
)

# Import common utilities
$ScriptRoot = Split-Path -Parent $PSCommandPath
. (Join-Path $ScriptRoot "Common.Utils.ps1")

# Ensure running as Administrator
Ensure-Admin -ScriptName "Debloat"

# Set execution policy for session
Set-SessionExecutionPolicy

# Start logging
$LogPath = Start-ReviewPCLogging -ScriptName "Debloat"

try {
  Write-Host "[Debloat] Running Win11Debloat with safe flags..." -ForegroundColor Cyan

  # Configure debloat arguments (safe flags that keep winget intact)
  $debloatArgs = @(
    "-RunDefaults",                # Base recommended tweaks (non-destructive)
    # Targeted removals (keep App Installer/winget intact)
    "-RemoveOneDrive",
    "-RemoveGamingApps", 
    "-RemoveCommApps",
    "-RemoveW11Outlook",
    # UI/ads/telemetry cleanup
    "-DisableCopilot",
    "-DisableTelemetry",
    "-DisableSuggestions",
    "-DisableBing",
    "-DisableEdgeAds",
    "-DisableDesktopSpotlight",
    "-DisableLockscreenTips",
    "-DisableSettings365Ads",
    "-DisableStartRecommended",
    "-HideSearchTb",
    "-DisableWidgets",
    "-HideChat",
    "-EnableEndTask",
    "-ClearStartAllUsers",         # We'll apply our own pins later
    "-CreateRestorePoint"
  )

  # Add optional flags based on parameters
  if ($SysprepMode) { $debloatArgs += "-Sysprep" }
  if ($Silent)      { $debloatArgs += "-Silent" }

  # Optional OEM bloat removal (uncomment as needed)
  # $debloatArgs += "-RemoveHPApps"

  Write-Host "[Debloat] Debloat flags: $($debloatArgs -join ' ')" -ForegroundColor DarkGray

  # Run the launcher in a child PowerShell rather than as an in-process
  # scriptblock: it ends with `Exit $exitCode`, which in-process surfaces as a
  # bogus "System error." ExitException and hides the real exit code.
  $launcher = Join-Path $env:TEMP "Win11Debloat-get.ps1"
  Invoke-RestMethod "https://debloat.raphi.re/" -OutFile $launcher
  & powershell -NoProfile -ExecutionPolicy Bypass -File $launcher @debloatArgs
  $code = $LASTEXITCODE
  Remove-Item $launcher -Force -ErrorAction SilentlyContinue
  if ($code -ne 0) { throw "Win11Debloat exited with code $code (see $env:TEMP\Win11Debloat\Logs)" }
  Write-Host "[Debloat] Win11Debloat finished successfully." -ForegroundColor Green

} catch {
  Write-Warning "[Debloat] Win11Debloat error: $($_.Exception.Message)"
  throw
} finally {
  Stop-ReviewPCLogging
}
