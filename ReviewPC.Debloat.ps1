<#
  ReviewPC.Debloat.ps1
  Runs Win11Debloat with safe, recommended flags
  Part of the ReviewPC setup suite
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

  # Create the debloat command
  $debloatInvoker = @"
& ([scriptblock]::Create((irm "https://debloat.raphi.re/"))) $($debloatArgs -join ' ')
"@

  Write-Host "[Debloat] Debloat flags: $($debloatArgs -join ' ')" -ForegroundColor DarkGray
  
  # Execute the debloat script
  Invoke-Expression $debloatInvoker
  Write-Host "[Debloat] Win11Debloat finished successfully." -ForegroundColor Green

} catch {
  Write-Warning "[Debloat] Win11Debloat error: $($_.Exception.Message)"
  throw
} finally {
  Stop-ReviewPCLogging
}
