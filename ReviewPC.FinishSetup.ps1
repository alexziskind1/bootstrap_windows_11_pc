<#
  ReviewPC.FinishSetup.ps1
  - Chrome as default (via DefaultApps.xml)
  - Taskbar pins: Task Manager, Visual Studio, VS Code, Windows Terminal, Chrome
  - Disable notifications
  - Hide Copilot/Search/Widgets/Chat, center taskbar
  - Dev & power tweaks
  Part of the ReviewPC setup suite
#>

# Import common utilities
$ScriptRoot = Split-Path -Parent $PSCommandPath
. (Join-Path $ScriptRoot "Common.Utils.ps1")

# Ensure running as Administrator
Ensure-Admin -ScriptName "Finish"

# Set execution policy for session
Set-SessionExecutionPolicy

# Start logging  
$LogPath = Start-ReviewPCLogging -ScriptName "Finish"

Write-Host "[Finish] Starting finisher..."

# 1) Set Chrome as default via DefaultApps.xml
$defaultApps = Join-Path $ScriptRoot 'DefaultApps.xml'
if (Test-Path $defaultApps) {
  Write-Host "[Finish] Importing DefaultApps.xml (Chrome as default)..."
  Dism /Online /Import-DefaultAppAssociations:$defaultApps | Out-Null
} else {
  Write-Host "[Finish] DefaultApps.xml not found beside this script. Skipping default-apps import."
}

# 2) Taskbar pins
Write-Host "[Finish] Applying taskbar pins..."

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
  <CustomTaskbarLayoutCollection>
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
  Write-Host "[Finish] Wrote taskbar layout for current and new users."
}

# 3) Disable notifications
Write-Host "[Finish] Disabling notifications..."
Set-ReviewPCRegistry HKCU 'Software\Microsoft\Windows\CurrentVersion\PushNotifications' 'ToastEnabled' 0
Set-ReviewPCRegistry HKCU 'Software\Policies\Microsoft\Windows\Explorer' 'DisableNotificationCenter' 1
Set-ReviewPCRegistry HKCU 'Software\Microsoft\Windows\CurrentVersion\Notifications\Settings' 'NOC_GLOBAL_SETTING_TOASTS_ENABLED' 0

# 4) UI hygiene (center taskbar)
Write-Host "[Finish] Reasserting UI hygiene..."
Set-ReviewPCRegistry HKLM 'SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
Set-ReviewPCRegistry HKCU 'Software\Microsoft\Windows\Shell\Copilot' 'CopilotAvailability' 0
Set-ReviewPCRegistry HKCU 'Software\Microsoft\Windows\CurrentVersion\Search' 'SearchboxTaskbarMode' 0
Set-ReviewPCRegistry HKCU 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarDa' 0
Set-ReviewPCRegistry HKCU 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarMn' 0
#Set-ReviewPCRegistry HKCU 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAl' 0   # 0=left, 1=center
#Set-ReviewPCRegistry HKCU 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowSecondsInSystemClock' 1

# 5) Dev & power tweaks
Write-Host "[Finish] Applying dev and power tweaks..."
powercfg -h off | Out-Null
powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 | Out-Null
$ultimate = (powercfg -list) -match 'Ultimate Performance'
if ($ultimate) {
  $guid = ($ultimate -replace '.*GUID:\s*([a-f0-9\-]+).*','$1')
  if ($guid) { powercfg -setactive $guid | Out-Null }
}
Set-ReviewPCRegistry HKLM 'SYSTEM\CurrentControlSet\Control\FileSystem' 'LongPathsEnabled' 1
Set-ReviewPCRegistry HKLM 'SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' 'AllowAllTrustedApps' 1
Set-ReviewPCRegistry HKLM 'SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' 'AllowDevelopmentWithoutDevLicense' 1

# 6) Restart Explorer
Write-Host "[Finish] Restarting Explorer..."
Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Process explorer.exe

Write-Host "[Finish] Done. If pins or default apps do not show immediately, sign out/in or reboot."

# Stop logging
Stop-ReviewPCLogging
