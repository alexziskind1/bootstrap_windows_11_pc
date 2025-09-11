<#
  Test-TaskbarPins.ps1
  Standalone test script for taskbar pin clearing and application
  This allows you to test the taskbar functionality without running the full setup
#>

param(
  [switch]$ClearOnly,  # Only clear pins, don't apply new ones
  [switch]$ApplyOnly   # Only apply pins, don't clear existing ones
)

# Import common utilities
$ScriptRoot = Split-Path -Parent $PSCommandPath
. (Join-Path $ScriptRoot "Common.Utils.ps1")

# Ensure running as Administrator
Ensure-Admin -ScriptName "TaskbarTest"

# Set execution policy for session
Set-SessionExecutionPolicy

Write-Host "[TaskbarTest] Starting taskbar pin test..." -ForegroundColor Cyan
Write-Host "[TaskbarTest] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Current parameters: ClearOnly=$ClearOnly, ApplyOnly=$ApplyOnly"

try {
  # Step 1: Clear existing pins (unless ApplyOnly is specified)
  if (-not $ApplyOnly) {
    Write-Host "`n[TaskbarTest] === CLEARING EXISTING PINS ===" -ForegroundColor Yellow
    Clear-ReviewPCTaskbarPins -ScriptPrefix "TaskbarTest"
    
    # Also apply registry tweaks to disable default pins
    Write-Host "[TaskbarTest] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Applying registry tweaks to disable default pins..."
    Set-ReviewPCRegistry HKCU 'Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband' 'NumPinnedItems' 0
    Set-ReviewPCRegistry HKCU 'Software\Policies\Microsoft\Windows\Explorer' 'NoPinningToTaskbar' 0
    
    if ($ClearOnly) {
      Write-Host "[TaskbarTest] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - ClearOnly mode: Restarting Explorer to apply changes..."
      Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
      Start-Sleep -Seconds 2
      Start-Process explorer.exe
      Write-Host "[TaskbarTest] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Taskbar cleared! Check your taskbar now." -ForegroundColor Green
      return
    }
  }

  # Step 2: Apply new pins (unless ClearOnly is specified)
  if (-not $ClearOnly) {
    Write-Host "`n[TaskbarTest] === APPLYING NEW PINS ===" -ForegroundColor Yellow
    
    # Resolve common .lnk targets (same logic as FinishSetup)
    $ChromeLnk    = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Google Chrome.lnk"
    $VSCodeLnk    = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Visual Studio Code.lnk"
    $TerminalLnk  = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Windows Terminal.lnk"

    # Visual Studio link can live in a few places
    $VStudioCandidates = @(
      "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Visual Studio 2022.lnk",
      "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Visual Studio 2022\Visual Studio 2022.lnk",
      "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Microsoft Visual Studio\Visual Studio 2022.lnk"
    )
    $VStudioLnk = $null
    foreach ($c in $VStudioCandidates) { if (Test-Path $c) { $VStudioLnk = $c; break } }

    # Create Task Manager shortcut if missing
    $TaskMgrDir = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\System Tools"
    $TaskMgrLnk = Join-Path $TaskMgrDir "Task Manager.lnk"
    if (-not (Test-Path $TaskMgrLnk)) {
      Write-Host "[TaskbarTest] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Creating Task Manager shortcut..."
      New-Item -ItemType Directory -Force -Path $TaskMgrDir | Out-Null
      $WshShell = New-Object -ComObject WScript.Shell
      $Shortcut = $WshShell.CreateShortcut($TaskMgrLnk)
      $Shortcut.TargetPath = "$env:SystemRoot\System32\Taskmgr.exe"
      $Shortcut.Save()
    }

    # Check what shortcuts exist
    Write-Host "[TaskbarTest] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Checking for application shortcuts..."
    $shortcuts = @{
      "Task Manager" = $TaskMgrLnk
      "Visual Studio 2022" = $VStudioLnk
      "VS Code" = $VSCodeLnk
      "Windows Terminal" = $TerminalLnk
      "Google Chrome" = $ChromeLnk
    }
    
    foreach ($app in $shortcuts.Keys) {
      $path = $shortcuts[$app]
      if ($path -and (Test-Path $path)) {
        Write-Host "[TaskbarTest]   ✅ Found: $app at $path" -ForegroundColor Green
      } else {
        Write-Host "[TaskbarTest]   ❌ Missing: $app" -ForegroundColor Red
      }
    }

    # Final pin order (only include existing shortcuts)
    $pins = @()
    foreach ($lnk in @($TaskMgrLnk,$VStudioLnk,$VSCodeLnk,$TerminalLnk,$ChromeLnk)) {
      if ($lnk -and (Test-Path $lnk)) { $pins += $lnk }
    }

    if ($pins.Count -eq 0) {
      Write-Host "[TaskbarTest] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - WARNING: No pin targets found. Install applications first." -ForegroundColor Yellow
      return
    }

    Write-Host "[TaskbarTest] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Creating taskbar layout with $($pins.Count) applications..."
    
    $xmlPins = ($pins | ForEach-Object {
'            <taskbar:DesktopApp DesktopApplicationLinkPath="' + [System.Security.SecurityElement]::Escape($_) + '" />'
    }) -join "`r`n"

    $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<LayoutModificationTemplate xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification"
                            xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout"
                            Version="1">
  <CustomTaskbarLayoutCollection PinListPlacement="Replace">
    <defaultlayout:TaskbarLayout xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout">
      <taskbar:TaskbarPinList>
$xmlPins
      </taskbar:TaskbarPinList>
    </defaultlayout:TaskbarLayout>
  </CustomTaskbarLayoutCollection>
</LayoutModificationTemplate>
"@

    $shellDefault = "C:\Users\Default\AppData\Local\Microsoft\Windows\Shell"
    $shellCurrent = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Shell"
    New-Item -ItemType Directory -Force -Path $shellDefault,$shellCurrent | Out-Null

    $xml | Out-File (Join-Path $shellDefault "TaskbarLayoutModification.xml") -Encoding UTF8 -Force
    $xml | Out-File (Join-Path $shellCurrent "TaskbarLayoutModification.xml") -Encoding UTF8 -Force
    Write-Host "[TaskbarTest] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Wrote taskbar layout files."
    
    # Show the XML content for debugging
    Write-Host "`n[TaskbarTest] === GENERATED XML LAYOUT ===" -ForegroundColor Cyan
    Write-Host $xml -ForegroundColor Gray
    Write-Host "=== END XML ===" -ForegroundColor Cyan
    
    # Force Windows to reload the taskbar layout  
    Write-Host "`n[TaskbarTest] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Applying taskbar layout changes..."
    Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 3
    Start-Process explorer.exe
    
    Write-Host "[TaskbarTest] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Taskbar layout applied! Check your taskbar now." -ForegroundColor Green
  }
  
} catch {
  Write-Host "[TaskbarTest] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - ERROR: $($_.Exception.Message)" -ForegroundColor Red
  throw
}

Write-Host "`n[TaskbarTest] === TEST COMPLETE ===" -ForegroundColor Green
Write-Host "[TaskbarTest] If the taskbar didn't change as expected, try:" -ForegroundColor Yellow
Write-Host "[TaskbarTest]   1. Sign out and sign back in" -ForegroundColor Yellow
Write-Host "[TaskbarTest]   2. Reboot the computer" -ForegroundColor Yellow
Write-Host "[TaskbarTest]   3. Check the generated XML file at: $env:LOCALAPPDATA\Microsoft\Windows\Shell\TaskbarLayoutModification.xml" -ForegroundColor Yellow
