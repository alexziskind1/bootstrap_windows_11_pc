<#
  ReviewPC.RemoveOneDrive.ps1
  Completely removes OneDrive from the system
  Part of the ReviewPC setup suite

  Windows-on-ARM (arm64v2): This step is ARCH-AGNOSTIC. OneDrive is an in-box
  Windows provisioned package whose uninstaller paths (System32/SysWOW64
  OneDriveSetup.exe) and winget uninstall both work identically on x64 and
  ARM64 hosts. No per-architecture changes are required. (Note: the Debloat
  step also removes OneDrive; this is a belt-and-suspenders cleanup.)
#>

# Import common utilities
$ScriptRoot = Split-Path -Parent $PSCommandPath
. (Join-Path $ScriptRoot "Common.Utils.ps1")

# Ensure running as Administrator
Ensure-Admin -ScriptName "RemoveOneDrive"

# Set execution policy for session
Set-SessionExecutionPolicy

# Start logging
$LogPath = Start-ReviewPCLogging -ScriptName "RemoveOneDrive"

try {
  Write-Host "[RemoveOneDrive] Removing OneDrive completely..." -ForegroundColor Cyan

  # Kill any running OneDrive instances
  Write-Host "[RemoveOneDrive] Stopping OneDrive processes..." -ForegroundColor DarkGray
  taskkill /F /IM OneDrive.exe 2>$null

  # Try winget uninstall first (preferred method)
  Write-Host "[RemoveOneDrive] Attempting winget uninstall..." -ForegroundColor DarkGray
  try {
    winget uninstall --id Microsoft.OneDrive -e --silent
    Write-Host "[RemoveOneDrive] winget uninstall succeeded." -ForegroundColor Green
  } catch {
    Write-Host "[RemoveOneDrive] winget uninstall failed, trying built-in uninstaller..." -ForegroundColor Yellow
    
    # Run the built-in uninstaller (covers both 32-bit and 64-bit systems)
    $oneDrive32 = "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
    $oneDrive64 = "$env:SystemRoot\System32\OneDriveSetup.exe"
    
    if (Test-Path $oneDrive32) { 
      Write-Host "[RemoveOneDrive] Running 32-bit uninstaller..." -ForegroundColor DarkGray
      & $oneDrive32 /uninstall 
    }
    if (Test-Path $oneDrive64) { 
      Write-Host "[RemoveOneDrive] Running 64-bit uninstaller..." -ForegroundColor DarkGray
      & $oneDrive64 /uninstall 
    }
  }

  # Remove leftover folders
  Write-Host "[RemoveOneDrive] Cleaning up leftover folders..." -ForegroundColor DarkGray
  $foldersToRemove = @(
    "$env:USERPROFILE\OneDrive",
    "$env:LOCALAPPDATA\Microsoft\OneDrive",
    "$env:ProgramData\Microsoft OneDrive"
  )

  foreach ($folder in $foldersToRemove) {
    if (Test-Path $folder) {
      try {
        Remove-Item $folder -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "[RemoveOneDrive] Removed: $folder" -ForegroundColor DarkGray
      } catch {
        Write-Warning "[RemoveOneDrive] Could not remove: $folder"
      }
    }
  }

  Write-Host "[RemoveOneDrive] OneDrive removal completed successfully." -ForegroundColor Green

} catch {
  Write-Warning "[RemoveOneDrive] Error during OneDrive removal: $($_.Exception.Message)"
  throw
} finally {
  Stop-ReviewPCLogging
}
