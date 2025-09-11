<#
 ReviewPC.Install.ps1 — App installer for ReviewPC setup
 Uses Chocolatey (no winget required)
 Run as Administrator
#>

# 0) Ensure running as Admin
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[Install] Relaunching as Administrator..."
    $psi = New-Object System.Diagnostics.ProcessStartInfo "powershell"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    $psi.Verb = "runas"
    [Diagnostics.Process]::Start($psi) | Out-Null
    exit
}

Set-ExecutionPolicy Bypass -Scope Process -Force | Out-Null
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# 1) Install Chocolatey if missing
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Host "[Install] Installing Chocolatey..." -ForegroundColor Cyan
    $chocoScript = 'https://community.chocolatey.org/install.ps1'
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString($chocoScript))
}

# Refresh PATH for current session
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("Path","User")

# 2) Configure Chocolatey (no prompts)
choco feature enable -n=allowGlobalConfirmation | Out-Null
choco feature enable -n=useRememberedArgumentsForUpgrades | Out-Null

# 3) Install Apps
Write-Host "[Install] Installing browsers..." -ForegroundColor Cyan
choco install googlechrome
# choco install firefox

Write-Host "[Install] Installing dev tools..." -ForegroundColor Cyan
choco install git
choco install vscode
choco install python --version=3.12.0
choco install nodejs-lts
choco install visualstudio2022community
choco install uv
choco install miniconda3

Write-Host "[Install] Installing AI tooling..." -ForegroundColor Cyan
# LM Studio (desktop app)
choco install lm-studio     # package id: lm-studio
# Ollama (CLI + service)
choco install ollama        # package id: ollama

Write-Host "[Install] Installing benchmarks/monitoring..." -ForegroundColor Cyan
choco install cpu-z
choco install hwmonitor
choco install crystaldiskmark
# Cinebench isn’t reliably packaged; install manually if needed
# choco install cinebench

Write-Host "[Install] Installing media/productivity..." -ForegroundColor Cyan
# choco install obs-studio
choco install vlc
# choco install 7zip

Write-Host "[Install] Installing utilities..." -ForegroundColor Cyan
choco install notepadplusplus
choco install powertoys

Write-Host "[Install] All apps installed successfully." -ForegroundColor Green
