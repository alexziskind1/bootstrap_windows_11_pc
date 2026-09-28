<#
  ReviewPC.FinishSetup.ps1
  - Chrome as default (via DefaultApps.xml)
  - Taskbar pins: Task Manager, Visual Studio, VS Code, Windows Terminal, Chrome
  - Disable notifications
  - Hide Copilot/Search/Widgets/Chat, center taskbar
  - Dev & power tweaks
  Part of the ReviewPC setup suite
#>

param(
  [string]$GitUserName,
  [string]$GitUserEmail
)

# Import common utilities
$ScriptRoot = Split-Path -Parent $PSCommandPath
. (Join-Path $ScriptRoot "Common.Utils.ps1")

# Ensure running as Administrator
Ensure-Admin -ScriptName "Finish"

# Set execution policy for session
Set-SessionExecutionPolicy

# Start logging  
$LogPath = Start-ReviewPCLogging -ScriptName "Finish"

Write-Host "[Finish] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Starting finisher..."

# 1) Set Chrome as default via DefaultApps.xml
Write-Host "[Finish] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Checking for DefaultApps.xml..."
$defaultApps = Join-Path $ScriptRoot 'DefaultApps.xml'
if (Test-Path $defaultApps) {
  Write-Host "[Finish] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Importing DefaultApps.xml (Chrome as default)..."
  try {
    Dism /Online /Import-DefaultAppAssociations:$defaultApps | Out-Null
    Write-Host "[Finish] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Default app associations imported successfully."
  } catch {
    Write-Host "[Finish] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - ERROR importing default apps: $($_.Exception.Message)" -ForegroundColor Red
  }
} else {
  Write-Host "[Finish] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - DefaultApps.xml not found beside this script. Skipping default-apps import." -ForegroundColor Yellow
}

# 2) Taskbar pins
Write-Host "[Finish] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Applying taskbar pins..."

# Clear existing taskbar pins first
Clear-ReviewPCTaskbarPins -ScriptPrefix "Finish"

# Resolve common .lnk targets
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

# On Windows-on-ARM the apps install to the SAME Start-Menu locations as x64
# (Program Files / LocalAppData), but the ARM code path uses winget/direct
# installers rather than Chocolatey. Verify the expected .lnk files exist so a
# failed ARM install surfaces here instead of the taskbar pin step silently
# no-oping. (Get-ReviewPCArch / Test-ReviewPCIsArm64 come from Common.Utils.ps1.)
$hostArch = Get-ReviewPCArch
$isArm64 = Test-ReviewPCIsArm64
Write-Host "[Finish] Host architecture: $hostArch" -ForegroundColor DarkGray

# Create Task Manager shortcut if missing
$TaskMgrDir = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\System Tools"
$TaskMgrLnk = Join-Path $TaskMgrDir "Task Manager.lnk"
if (-not (Test-Path $TaskMgrLnk)) {
  New-Item -ItemType Directory -Force -Path $TaskMgrDir | Out-Null
  $WshShell = New-Object -ComObject WScript.Shell
  $Shortcut = $WshShell.CreateShortcut($TaskMgrLnk)
  $Shortcut.TargetPath = "$env:SystemRoot\System32\Taskmgr.exe"
  $Shortcut.Save()
}

# Final pin order
$pins = @()
foreach ($lnk in @($TaskMgrLnk,$VStudioLnk,$VSCodeLnk,$TerminalLnk,$ChromeLnk)) {
  if ($lnk -and (Test-Path $lnk)) { $pins += $lnk }
}

# Shortcut presence summary (arch-aware): on ARM these Start-Menu .lnk files are
# produced by the winget/direct installers; report any missing so taskbar pinning
# does not silently no-op after a partially-failed ARM install.
Write-Host "[Finish] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Resolved pin targets:"
foreach ($c in @(@{n='Task Manager';p=$TaskMgrLnk},@{n='Visual Studio';p=$VStudioLnk},
                 @{n='VS Code';p=$VSCodeLnk},@{n='Windows Terminal';p=$TerminalLnk},
                 @{n='Chrome';p=$ChromeLnk})) {
  if ($c.p -and (Test-Path $c.p)) {
    Write-Host "[Finish]   [OK] $($c.n): $($c.p)" -ForegroundColor Green
  } else {
    Write-Host "[Finish]   [MISSING] $($c.n)" -ForegroundColor Yellow
  }
}

if ($pins.Count -eq 0) {
  Write-Host "[Finish] No pin targets found. Run after apps are installed."
} else {
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
  Write-Host "[Finish] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Wrote taskbar layout for current and new users."
  
  # Force Windows to reload the taskbar layout  
  Write-Host "[Finish] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Applying taskbar layout changes..."
  try {
    # Restart Explorer to apply taskbar changes immediately
    Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
    Start-Process explorer.exe
    Write-Host "[Finish] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Taskbar layout applied successfully."
  
  # Note about Windows 11 taskbar limitations
  Write-Host "`n[Finish] NOTE: Windows 11 has restricted automated taskbar pinning." -ForegroundColor Yellow
  Write-Host "[Finish] If apps didn't pin automatically, manually pin them:" -ForegroundColor Yellow
  Write-Host "[Finish]   1. Open each app (Task Manager: Ctrl+Shift+Esc)" -ForegroundColor Yellow  
  Write-Host "[Finish]   2. Right-click the app icon in taskbar while running" -ForegroundColor Yellow
  Write-Host "[Finish]   3. Select 'Pin to taskbar'" -ForegroundColor Yellow
  } catch {
    Write-Host "[Finish] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - WARNING: Could not restart Explorer to apply taskbar changes: $($_.Exception.Message)" -ForegroundColor Yellow
  }
}

# 3) Disable notifications
Write-Host "[Finish] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Disabling notifications..."
try {
  Set-ReviewPCRegistry HKCU 'Software\Microsoft\Windows\CurrentVersion\PushNotifications' 'ToastEnabled' 0
  Set-ReviewPCRegistry HKCU 'Software\Policies\Microsoft\Windows\Explorer' 'DisableNotificationCenter' 1
  Set-ReviewPCRegistry HKCU 'Software\Microsoft\Windows\CurrentVersion\Notifications\Settings' 'NOC_GLOBAL_SETTING_TOASTS_ENABLED' 0
  Write-Host "[Finish] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Notification settings configured successfully."
} catch {
  Write-Host "[Finish] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - ERROR configuring notifications: $($_.Exception.Message)" -ForegroundColor Red
}

# 4) UI hygiene (center taskbar)
Write-Host "[Finish] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Reasserting UI hygiene..."
try {
  Set-ReviewPCRegistry HKLM 'SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
  Set-ReviewPCRegistry HKCU 'Software\Microsoft\Windows\Shell\Copilot' 'CopilotAvailability' 0
  Set-ReviewPCRegistry HKCU 'Software\Microsoft\Windows\CurrentVersion\Search' 'SearchboxTaskbarMode' 0
  Set-ReviewPCRegistry HKCU 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarDa' 0
  Set-ReviewPCRegistry HKCU 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarMn' 0
  
  # Remove default taskbar pins (Microsoft Store, Outlook, etc.)
  Set-ReviewPCRegistry HKCU 'Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband' 'NumPinnedItems' 0
  Set-ReviewPCRegistry HKCU 'Software\Policies\Microsoft\Windows\Explorer' 'NoPinningToTaskbar' 0  # 0 allows custom pinning
  
  #Set-ReviewPCRegistry HKCU 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAl' 0   # 0=left, 1=center
  #Set-ReviewPCRegistry HKCU 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowSecondsInSystemClock' 1
  Write-Host "[Finish] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - UI hygiene settings applied successfully."
} catch {
  Write-Host "[Finish] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - ERROR applying UI hygiene: $($_.Exception.Message)" -ForegroundColor Red
}

# 5) Dev & power tweaks
Write-Host "[Finish] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Applying dev and power tweaks..."
try {
  Write-Host "[Finish] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Disabling hibernation..."
  powercfg -h off | Out-Null
  
  Write-Host "[Finish] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Setting up Ultimate Performance power plan..."
  powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 | Out-Null
  $ultimate = (powercfg -list) -match 'Ultimate Performance'
  if ($ultimate) {
    $guid = ($ultimate -replace '.*GUID:\s*([a-f0-9\-]+).*','$1')
    if ($guid) { 
      powercfg -setactive $guid | Out-Null 
      Write-Host "[Finish] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Ultimate Performance power plan activated."
    }
  }
  
  Write-Host "[Finish] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Configuring development settings..."
  Set-ReviewPCRegistry HKLM 'SYSTEM\CurrentControlSet\Control\FileSystem' 'LongPathsEnabled' 1
  Set-ReviewPCRegistry HKLM 'SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' 'AllowAllTrustedApps' 1
  Set-ReviewPCRegistry HKLM 'SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' 'AllowDevelopmentWithoutDevLicense' 1
  
  Write-Host "[Finish] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Dev and power tweaks applied successfully."
} catch {
  Write-Host "[Finish] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - ERROR applying dev/power tweaks: $($_.Exception.Message)" -ForegroundColor Red
}

# Configure Git if parameters were provided and not already configured
if ($GitUserName -and $GitUserEmail) {
  Write-Host "[Finish] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Checking Git configuration..." -ForegroundColor Cyan
  try {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User")
    
    if (Get-Command git -ErrorAction SilentlyContinue) {
      $currentName = & git config --global user.name 2>$null
      $currentEmail = & git config --global user.email 2>$null
      
      if (-not $currentName -or -not $currentEmail) {
        Write-Host "[Finish] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Configuring Git (fallback)..." -ForegroundColor Yellow
        Set-ReviewPCGitConfig -UserName $GitUserName -UserEmail $GitUserEmail -ScriptPrefix "Finish"
      } else {
        Write-Host "[Finish] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Git already configured: $currentName <$currentEmail>" -ForegroundColor Green
      }
    }
  } catch {
    Write-Host "[Finish] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Could not check Git configuration: $($_.Exception.Message)" -ForegroundColor Yellow
  }
}

Write-Host "[Finish] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Done. If pins or default apps do not show immediately, sign out/in or reboot." -ForegroundColor Green

# Stop logging
Stop-ReviewPCLogging
