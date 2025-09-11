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
