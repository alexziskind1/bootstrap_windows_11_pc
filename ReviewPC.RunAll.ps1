<# 
  ReviewPC.RunAll.ps1
  One-click new-PC setup for reviews:
   1) Runs Win11Debloat with your chosen flags
   2) Runs your ReviewPC.Install.ps1   (apps via winget, etc.)
   3) Runs ReviewPC.FinishSetup.ps1 (Chrome default, taskbar pins, notifications off, dev/power tweaks)

  Usage (PowerShell as admin is automatic):
    Set-ExecutionPolicy Bypass -Scope Process -Force
    .\ReviewPC.RunAll.ps1

  Optional switches:
    -SysprepMode   => apply debloat to Default profile (affects NEW users) in addition to current user
    -Silent        => hides debloat prompts (default on)
#>

param(
  [switch]$SysprepMode,
  [switch]$Silent = $true
)

# ---------------------------
# 0) Self-elevate if needed
# ---------------------------
function Ensure-Admin {
  $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[RunAll] Elevation required, relaunching as admin..." -ForegroundColor Yellow
    $psi = New-Object System.Diagnostics.ProcessStartInfo "powershell"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" " + ($MyInvocation.UnboundArguments -join ' ')
    $psi.Verb = "runas"
    [Diagnostics.Process]::Start($psi) | Out-Null
    exit
  }
}
Ensure-Admin

# Session execution policy (temporary)
Set-ExecutionPolicy Bypass -Scope Process -Force | Out-Null

# ---------------------------
# 1) Prep paths & logging
# ---------------------------
$ScriptRoot = Split-Path -Parent $PSCommandPath
$LogDir     = Join-Path $ScriptRoot "logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogPath    = Join-Path $LogDir ("RunAll_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))
Start-Transcript -Path $LogPath -IncludeInvocationHeader | Out-Null
Write-Host "[RunAll] Logging to $LogPath" -ForegroundColor Cyan

# Helper: presence checks
function Exists([string]$p){ Test-Path -LiteralPath $p }

# Expected companion scripts/files
$InstallScript = Join-Path $ScriptRoot "ReviewPC.Install.ps1"
$FinishScript  = Join-Path $ScriptRoot "ReviewPC.FinishSetup.ps1"

# ---------------------------
# 2) Run Win11Debloat (SAFE FLAGS)
#    Removes OneDrive & clutter, keeps App Installer (winget)
# ---------------------------
Write-Host "[RunAll] Running Win11Debloat (safe flags)..." -ForegroundColor Cyan

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

if ($SysprepMode) { $debloatArgs += "-Sysprep" }
if ($Silent)      { $debloatArgs += "-Silent"    }

# Optional OEM bloat nukes (uncomment per unit)
# $debloatArgs += "-RemoveHPApps"

$debloatInvoker = @"
& ([scriptblock]::Create((irm "https://debloat.raphi.re/"))) $($debloatArgs -join ' ')
"@

Write-Host "[RunAll] Debloat flags: $($debloatArgs -join ' ')" -ForegroundColor DarkGray
try {
  Invoke-Expression $debloatInvoker
  Write-Host "[RunAll] Win11Debloat finished." -ForegroundColor Green
} catch {
  Write-Warning "[RunAll] Win11Debloat error: $($_.Exception.Message)"
}


# ---------------------------
# [Finish] Uninstall OneDrive completely
# ---------------------------
Write-Host "[Finish] Removing OneDrive…" -ForegroundColor Cyan

# Kill any running instance
taskkill /F /IM OneDrive.exe 2>$null

# Try winget uninstall (preferred)
try {
    winget uninstall --id Microsoft.OneDrive -e --silent
} catch {
    Write-Host "[Finish] winget uninstall failed, trying built-in uninstaller…" -ForegroundColor Yellow
}

# Run the built-in uninstaller (covers 32- and 64-bit systems)
$oneDrive32 = "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
$oneDrive64 = "$env:SystemRoot\System32\OneDriveSetup.exe"
if (Test-Path $oneDrive32) { & $oneDrive32 /uninstall }
if (Test-Path $oneDrive64) { & $oneDrive64 /uninstall }

# Optional: remove leftover folders
Remove-Item "$env:USERPROFILE\OneDrive" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$env:LOCALAPPDATA\Microsoft\OneDrive" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$env:ProgramData\Microsoft OneDrive" -Recurse -Force -ErrorAction SilentlyContinue



# ---------------------------
# 3) Run your app installer
# ---------------------------
if (Exists $InstallScript) {
  Write-Host "[RunAll] Running ReviewPC.Install.ps1..." -ForegroundColor Cyan
  try {
    & $InstallScript
    Write-Host "[RunAll] ReviewPC.Install.ps1 completed." -ForegroundColor Green
  } catch {
    Write-Warning "[RunAll] ReviewPC.Install.ps1 failed: $($_.Exception.Message)"
  }
} else {
  Write-Host "[RunAll] Skipping ReviewPC.Install.ps1 (not found at $InstallScript)" -ForegroundColor Yellow
}

# ---------------------------
# 4) Run your finisher (Chrome default, pins, notifications, tweaks)
# ---------------------------
if (Exists $FinishScript) {
  Write-Host "[RunAll] Running ReviewPC.FinishSetup.ps1..." -ForegroundColor Cyan
  try {
    & $FinishScript
    Write-Host "[RunAll] Finish setup completed." -ForegroundColor Green
  } catch {
    Write-Warning "[RunAll] ReviewPC.FinishSetup.ps1 failed: $($_.Exception.Message)"
  }
} else {
  Write-Host "[RunAll] Skipping ReviewPC.FinishSetup.ps1 (not found at $FinishScript)" -ForegroundColor Yellow
}

# ---------------------------
# 5) Wrap up
# ---------------------------
Stop-Transcript | Out-Null
Write-Host "`n[RunAll] All steps done. If taskbar pins or default apps didn’t update immediately, sign out/in or reboot." -ForegroundColor Cyan
