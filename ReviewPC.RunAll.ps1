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
  
  # ---------------------------
  # User Input Section
  # ---------------------------
  Write-Host "`n[RunAll] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Collecting user configuration..." -ForegroundColor Yellow
  
  # Git Configuration
  Write-Host "`nGit will be installed as part of this setup. Please provide your Git configuration:" -ForegroundColor Cyan
  
  do {
    $GitUserName = Read-Host "Enter your Git user name (e.g., 'John Doe')"
  } while ([string]::IsNullOrWhiteSpace($GitUserName))
  
  do {
    $GitUserEmail = Read-Host "Enter your Git email address (e.g., 'john@example.com')"
  } while ([string]::IsNullOrWhiteSpace($GitUserEmail) -or $GitUserEmail -notmatch '^[^\s@]+@[^\s@]+\.[^\s@]+$')
  
  Write-Host "[RunAll] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Git config: Name='$GitUserName', Email='$GitUserEmail'" -ForegroundColor Green
  
  # Store Git config for later use
  $GitConfig = @{
    UserName = $GitUserName
    UserEmail = $GitUserEmail
  }
  
  Write-Host "[RunAll] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - User configuration collected successfully.`n" -ForegroundColor Green
  
  # Define script paths
  $DebloatScript = Join-Path $ScriptRoot "ReviewPC.Debloat.ps1"
  $OneDriveScript = Join-Path $ScriptRoot "ReviewPC.RemoveOneDrive.ps1"
  $InstallScript = Join-Path $ScriptRoot "ReviewPC.Install.ps1"
  $FinishScript = Join-Path $ScriptRoot "ReviewPC.FinishSetup.ps1"

  # ---------------------------
  # 1) Run Win11Debloat (SAFE FLAGS)
  # ---------------------------
  Write-Host "[RunAll] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Running Win11 Debloat..." -ForegroundColor Cyan
  $debloatArgs = @()
  if ($SysprepMode) { $debloatArgs += "-SysprepMode" }
  if ($Silent) { $debloatArgs += "-Silent" }
  
  Invoke-ReviewPCScript -ScriptPath $DebloatScript -ScriptName "Win11Debloat" -Arguments $debloatArgs
  Write-Host "[RunAll] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Win11 Debloat completed." -ForegroundColor Green

  # ---------------------------
  # 2) Remove OneDrive completely
  # ---------------------------
  Write-Host "[RunAll] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Running OneDrive Removal..." -ForegroundColor Cyan
  Invoke-ReviewPCScript -ScriptPath $OneDriveScript -ScriptName "OneDrive Removal"
  Write-Host "[RunAll] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - OneDrive Removal completed." -ForegroundColor Green

  # ---------------------------
  # 3) Install applications
  # ---------------------------
  Write-Host "[RunAll] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Running App Installation..." -ForegroundColor Cyan
  $installArgs = @()
  if ($GitConfig.UserName) { $installArgs += "-GitUserName"; $installArgs += $GitConfig.UserName }
  if ($GitConfig.UserEmail) { $installArgs += "-GitUserEmail"; $installArgs += $GitConfig.UserEmail }
  Invoke-ReviewPCScript -ScriptPath $InstallScript -ScriptName "App Installation" -Arguments $installArgs
  Write-Host "[RunAll] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - App Installation completed." -ForegroundColor Green

  # ---------------------------
  # 4) Finish setup (Chrome default, pins, notifications, tweaks)
  # ---------------------------
  Write-Host "[RunAll] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Running Finish Setup..." -ForegroundColor Cyan
  $finishArgs = @()
  if ($GitConfig.UserName) { $finishArgs += "-GitUserName"; $finishArgs += $GitConfig.UserName }
  if ($GitConfig.UserEmail) { $finishArgs += "-GitUserEmail"; $finishArgs += $GitConfig.UserEmail }
  Invoke-ReviewPCScript -ScriptPath $FinishScript -ScriptName "Finish Setup" -Arguments $finishArgs
  Write-Host "[RunAll] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Finish Setup completed." -ForegroundColor Green

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
