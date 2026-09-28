<# 
  ReviewPC.RunAll.ps1
  One-click new-PC setup for reviews:
   1) Runs Win11Debloat with your chosen flags
   2) Removes OneDrive completely
   3) Runs your ReviewPC.Install.ps1 (arch-aware app install: Chocolatey on x64,
      native ARM64 via winget/direct URLs on Windows-on-ARM)
   4) Runs ReviewPC.FinishSetup.ps1 (Chrome default, taskbar pins, notifications off, dev/power tweaks)
   5) Runs the post-install ARM64 audit (Test-ReviewPCArm64v2.ps1) and reports
      PASS/WARN/FAIL - wired into the normal suite run (arm64v2).

  Usage (PowerShell as admin is automatic):
    Set-ExecutionPolicy Bypass -Scope Process -Force
    .\ReviewPC.RunAll.ps1

  Optional switches:
    -SysprepMode   => apply debloat to Default profile (affects NEW users) in addition to current user
    -Silent        => hides debloat prompts (default on)
    -SkipAudit     => do not run the post-install ARM64 audit at the end
#>

param(
  [switch]$SysprepMode,
  [switch]$Silent = $true,
  [switch]$SkipAudit
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
  # 5) Post-install ARM64 audit (wired into the normal suite run)
  # ---------------------------
  $auditExit = 0
  if ($SkipAudit) {
    Write-Host "[RunAll] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Skipping post-install audit (-SkipAudit)." -ForegroundColor Yellow
  } else {
    $AuditScript = Join-Path $ScriptRoot "Test-ReviewPCArm64v2.ps1"
    if (Test-Path $AuditScript) {
      Write-Host "[RunAll] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Running post-install ARM64 audit..." -ForegroundColor Cyan
      # Run the auditor in a child PowerShell process so its `exit` status is
      # captured as $LASTEXITCODE without terminating this orchestrator. On an
      # ARM64 host it runs Live (real PE inspection); on an x64 host the auditor
      # automatically falls back to DryRun (which exits 0).
      & powershell -NoProfile -ExecutionPolicy Bypass -File $AuditScript -Mode Live
      $auditExit = $LASTEXITCODE
      if ($auditExit -eq 0) {
        Write-Host "[RunAll] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - ARM64 audit passed." -ForegroundColor Green
      } else {
        Write-Host "[RunAll] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - ARM64 audit FAILED (exit $auditExit). See audit output above." -ForegroundColor Red
      }
    } else {
      Write-Host "[RunAll] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Audit script not found at $AuditScript; skipping." -ForegroundColor Yellow
    }
  }

  # ---------------------------
  # 6) Summary
  # ---------------------------
  Write-Host "`n[RunAll] ✅ All setup steps completed." -ForegroundColor Green
  if ($auditExit -ne 0) {
    Write-Host "[RunAll] ⚠️  The post-install ARM64 audit reported failures (exit $auditExit) - resolve them before considering the setup complete." -ForegroundColor Yellow
  }
  Write-Host "[RunAll] If taskbar pins or default apps didn't update immediately, sign out/in or reboot." -ForegroundColor Cyan

} catch {
  Write-Error "[RunAll] ❌ Setup failed: $($_.Exception.Message)"
  exit 1
} finally {
  Stop-ReviewPCLogging
}
