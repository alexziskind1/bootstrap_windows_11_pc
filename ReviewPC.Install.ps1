<#
 ReviewPC.Install.ps1 — App installer for ReviewPC setup
 Uses ChocolateWrite-Host "Write-Host "[Install] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Installing benchmarks/monitoring..." -ForegroundColor Cyan
Install-ReviewPCPackage -PackageName "cpu-z"
Install-ReviewPCPackage -PackageName "hwmonitor"
Install-ReviewPCPackage -PackageName "crystaldiskmark"
# Cinebench isn't reliably packaged; install manually if needed
# Install-ReviewPCPackage -PackageName "cinebench"

Write-Host "[Install] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Installing media/productivity..." -ForegroundColor Cyan" -ForegroundColor Cyan
Install-ReviewPCPackage -PackageName "cpu-z"
Install-ReviewPCPackage -PackageName "hwmonitor"
Install-ReviewPCPackage -PackageName "crystaldiskmark"
# Cinebench isn't reliably packaged; install manually if needed
# Install-ReviewPCPackage -PackageName "cinebench"winget required)
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
Ensure-Admin -ScriptName "Install"

# Set execution policy for session
Set-SessionExecutionPolicy

# Start logging
$LogPath = Start-ReviewPCLogging -ScriptName "Install"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# 1) Install Chocolatey if missing
Write-Host "[Install] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Checking for Chocolatey..."
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Host "[Install] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Installing Chocolatey..." -ForegroundColor Cyan
    try {
        $chocoScript = 'https://community.chocolatey.org/install.ps1'
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString($chocoScript))
        Write-Host "[Install] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Chocolatey installation completed successfully."
    } catch {
        Write-Host "[Install] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - ERROR installing Chocolatey: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
} else {
    Write-Host "[Install] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Chocolatey already installed."
}

# Refresh PATH for current session
Write-Host "[Install] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Refreshing PATH environment variable..."
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("Path","User")

# 2) Configure Chocolatey (no prompts)
Write-Host "[Install] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Configuring Chocolatey settings..."
try {
    choco feature enable -n=allowGlobalConfirmation | Out-Null
    choco feature enable -n=useRememberedArgumentsForUpgrades | Out-Null
    Write-Host "[Install] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Chocolatey configuration completed."
} catch {
    Write-Host "[Install] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - ERROR configuring Chocolatey: $($_.Exception.Message)" -ForegroundColor Red
}

# 3) Install Apps
Write-Host "[Install] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Installing browsers..." -ForegroundColor Cyan
Install-ReviewPCPackage -PackageName "googlechrome" -ExtraArgs "--ignore-checksums"
# Install-ReviewPCPackage -PackageName "firefox"

Write-Host "[Install] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Installing dev tools..." -ForegroundColor Cyan
Install-ReviewPCPackage -PackageName "git"
Install-ReviewPCPackage -PackageName "vscode"
Install-ReviewPCPackage -PackageName "python" -ExtraArgs "--version=3.12.0"
Install-ReviewPCPackage -PackageName "nodejs-lts"
Install-ReviewPCPackage -PackageName "visualstudio2022community"
Install-ReviewPCPackage -PackageName "uv"
Install-ReviewPCPackage -PackageName "miniconda3"

Write-Host "[Install] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Installing AI tooling..." -ForegroundColor Cyan
# LM Studio (desktop app)
Install-ReviewPCPackage -PackageName "lm-studio"     # package id: lm-studio
# Ollama (CLI + service)
Install-ReviewPCPackage -PackageName "ollama"        # package id: ollama

Write-Host "[Install] Installing benchmarks/monitoring..." -ForegroundColor Cyan
choco install cpu-z
choco install hwmonitor
choco install crystaldiskmark
# Cinebench isn’t reliably packaged; install manually if needed
# choco install cinebench

Write-Host "[Install] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Installing media/productivity..." -ForegroundColor Cyan
# Install-ReviewPCPackage -PackageName "obs-studio"
Install-ReviewPCPackage -PackageName "vlc"
# Install-ReviewPCPackage -PackageName "7zip"

Write-Host "[Install] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Installing utilities..." -ForegroundColor Cyan
Install-ReviewPCPackage -PackageName "notepadplusplus"
Install-ReviewPCPackage -PackageName "powertoys"
Install-ReviewPCPackage -PackageName "microsoft-windows-terminal"

Write-Host "[Install] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - All apps installed successfully." -ForegroundColor Green

# Configure Git if parameters were provided
if ($GitUserName -and $GitUserEmail) {
  Write-Host "[Install] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Configuring Git..." -ForegroundColor Cyan
  Set-ReviewPCGitConfig -UserName $GitUserName -UserEmail $GitUserEmail -ScriptPrefix "Install"
}

# Stop logging
Stop-ReviewPCLogging
