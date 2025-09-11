<# 
  ReviewPC.RunAll.ps1
  One-click new-PC setup for reviews:
   1) Runs Win11Debloat with your chosen flags
   2) Removes OneDrive completely  
   3) Runs your ReviewPC.Install.ps1 (apps via Chocolatey)
   4) Runs ReviewPC.FinishSetup.ps1 (Chrome default, taskbar pins, notifications off, dev/power tweaks)

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

# Import common utilities
$ScriptRoot = Split-Path -Parent $PSCommandPath
. (Join-Path $ScriptRoot "Common.Utils.ps1")

# Ensure running as Administrator
Ensure-Admin -ScriptName "RunAll"

# Set execution policy for session
Set-SessionExecutionPolicy

# Start logging
$LogPath = Start-ReviewPCLogging -ScriptName "RunAll"

try {
  Write-Host "[RunAll] Starting ReviewPC one-click setup..." -ForegroundColor Cyan
  
  # Define script paths
  $DebloatScript = Join-Path $ScriptRoot "ReviewPC.Debloat.ps1"
  $OneDriveScript = Join-Path $ScriptRoot "ReviewPC.RemoveOneDrive.ps1"
  $InstallScript = Join-Path $ScriptRoot "ReviewPC.Install.ps1"
  $FinishScript = Join-Path $ScriptRoot "ReviewPC.FinishSetup.ps1"

  # ---------------------------
  # 1) Run Win11Debloat (SAFE FLAGS)
  # ---------------------------
  $debloatArgs = @()
  if ($SysprepMode) { $debloatArgs += "-SysprepMode" }
  if ($Silent) { $debloatArgs += "-Silent" }
  
  Invoke-ReviewPCScript -ScriptPath $DebloatScript -ScriptName "Win11Debloat" -Arguments $debloatArgs

  # ---------------------------
  # 2) Remove OneDrive completely
  # ---------------------------
  Invoke-ReviewPCScript -ScriptPath $OneDriveScript -ScriptName "OneDrive Removal"

  # ---------------------------
  # 3) Install applications
  # ---------------------------
  Invoke-ReviewPCScript -ScriptPath $InstallScript -ScriptName "App Installation"

  # ---------------------------
  # 4) Finish setup (Chrome default, pins, notifications, tweaks)
  # ---------------------------
  Invoke-ReviewPCScript -ScriptPath $FinishScript -ScriptName "Finish Setup"

  # ---------------------------
  # 5) Summary
  # ---------------------------
  Write-Host "`n[RunAll] ✅ All setup steps completed successfully!" -ForegroundColor Green
  Write-Host "[RunAll] If taskbar pins or default apps didn't update immediately, sign out/in or reboot." -ForegroundColor Cyan

} catch {
  Write-Error "[RunAll] ❌ Setup failed: $($_.Exception.Message)"
  exit 1
} finally {
  Stop-ReviewPCLogging
}
