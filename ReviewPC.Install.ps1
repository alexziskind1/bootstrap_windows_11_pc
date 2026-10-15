<#
 ReviewPC.Install.ps1 - App installer for ReviewPC setup (arm64v2)

 Architecture-aware installer:
   * x64 host   -> the original Chocolatey flow (unchanged behavior).
   * ARM64 host -> installs the NATIVE ARM64 build of every app (winget
                   per-arch manifests + direct ARM64 installer/zip URLs),
                   avoiding x64-emulated binaries. Chocolatey is bootstrapped
                   (harmless, arch-agnostic) but is NOT used for per-app
                   installs on ARM.

 Every ARM64 installer URL is HEAD-validated and downloaded with retry +
 size validation (see Common.Utils.ps1). Each app's expected install path is
 asserted after the install using the single source of truth in
 Get-ReviewPCAppCatalog. A per-app result object is returned so the caller
 (ReviewPC.RunAll.ps1) can report pass/fail and drive the audit.
#>

[CmdletBinding()]
param(
  [string]$GitUserName,
  [string]$GitUserEmail
)

$ScriptRoot = Split-Path -Parent $PSCommandPath
. (Join-Path $ScriptRoot "Common.Utils.ps1")

Ensure-Admin -ScriptName "Install"
Set-SessionExecutionPolicy
$LogPath = Start-ReviewPCLogging -ScriptName "Install"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- Detect host architecture ---
$HostArch = Get-ReviewPCArch
$IsArm64  = Test-ReviewPCIsArm64
Write-Host "[Install] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Detected host architecture: $HostArch"
if ($IsArm64) {
  Write-Host "[Install] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Windows-on-ARM host detected. Using NATIVE ARM64 installs." -ForegroundColor Cyan
} else {
  Write-Host "[Install] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - x64 host detected. Using standard Chocolatey installs." -ForegroundColor Cyan
}

# Per-app results consumed by RunAll / reported in summary.
$Results = @()

# 1) Install Chocolatey if missing (arch-agnostic bootstrap; kept on ARM too)
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

if (-not $IsArm64) {
  # =====================================================================
  # X64 / STANDARD PATH (unchanged behavior)
  # =====================================================================
  Write-Host "[Install] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Configuring Chocolatey settings..."
  try {
      choco feature enable -n=allowGlobalConfirmation | Out-Null
      choco feature enable -n=useRememberedArgumentsForUpgrades | Out-Null
      Write-Host "[Install] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Chocolatey configuration completed."
  } catch {
      Write-Host "[Install] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - ERROR configuring Chocolatey: $($_.Exception.Message)" -ForegroundColor Red
  }

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

  Write-Host "[Install] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Installing benchmarks/monitoring..." -ForegroundColor Cyan
  choco install cpu-z
  choco install hwmonitor
  choco install crystaldiskmark
  # Cinebench isn't reliably packaged; install manually if needed
  # choco install cinebench

  Write-Host "[Install] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Installing media/productivity..." -ForegroundColor Cyan
  # Install-ReviewPCPackage -PackageName "obs-studio"
  Install-ReviewPCPackage -PackageName "vlc"
  # Install-ReviewPCPackage -PackageName "7zip"

  Write-Host "[Install] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Installing utilities..." -ForegroundColor Cyan
  Install-ReviewPCPackage -PackageName "notepadplusplus"
  Install-ReviewPCPackage -PackageName "powertoys"
  Install-ReviewPCPackage -PackageName "microsoft-windows-terminal"

  Write-Host "[Install] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - All x64 apps installed." -ForegroundColor Green
}
else {
  # =====================================================================
  # ARM64 / NATIVE PATH (Windows on ARM) - arm64v2
  # =====================================================================

  # Most of this path goes through winget; say so up front if it is missing
  # rather than letting every app fail one by one.
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host "[Install] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - ERROR: winget not found. Update 'App Installer' from the Microsoft Store and re-run; winget-based installs below will fail." -ForegroundColor Red
  }

  # --- 2) Browsers ---
  Write-Host "[Install] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - [ARM64] Installing browsers..." -ForegroundColor Cyan
  $chromeOk = Install-ReviewPCWinget -PackageId "Google.Chrome"
  if (-not $chromeOk) {
    # winget's Chrome manifest points at Google's unversioned "latest" MSI, so
    # its pinned hash goes stale whenever Chrome ships ahead of the manifest
    # (0x8A150011). Fall back to that same official ARM64 MSI directly.
    $chromeOk = Install-ReviewPCDownloadAndRun `
                  -Url "https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise_arm64.msi" `
                  -FileName "googlechromestandaloneenterprise_arm64.msi" `
                  -ExpectedSizeMB 100 `
                  -SilentArgs "/qn /norestart"
  }
  $Results += @{ Id='chrome'; Ok=$chromeOk }
  # Install-ReviewPCWinget -PackageId "Mozilla.Firefox"   # firefox (commented out, as on x64)

  # --- 3) Dev tools ---
  Write-Host "[Install] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - [ARM64] Installing dev tools..." -ForegroundColor Cyan
  $Results += @{ Id='git';  Ok=(Install-ReviewPCWinget -PackageId "Git.Git") }
  $Results += @{ Id='vscode'; Ok=(Install-ReviewPCWinget -PackageId "Microsoft.VisualStudioCode") }
  # Python 3.12.0 - native ARM64 installer (honors the original pinned version).
  $Results += @{ Id='python'; Ok=(Install-ReviewPCDownloadAndRun `
                        -Url "https://www.python.org/ftp/python/3.12.0/python-3.12.0-arm64.exe" `
                        -FileName "python-3.12.0-arm64.exe" `
                        -ExpectedSizeMB 20 `
                        -SilentArgs "/quiet InstallAllUsers=1 PrependPath=1 Include_test=0") }
  # Node.js LTS - native arm64 MSI.
  $Results += @{ Id='node'; Ok=(Install-ReviewPCWinget -PackageId "OpenJS.NodeJS.LTS") }
  # Visual Studio 2022 Community. Since VS 2022 17.4 the IDE is a native ARM64
  # app, and the bootstrapper picks the ARM64 build itself on an ARM64 host
  # (--arch is a layout-only parameter, not valid for an install). Some
  # auxiliary workloads still run emulated. Installed with a minimal core
  # editor; extend with extra --add flags as needed.
  $Results += @{ Id='vs2022'; Ok=(Install-ReviewPCDownloadAndRun `
                        -Url "https://aka.ms/vs/17/release/vs_community.exe" `
                        -FileName "vs_Community.exe" `
                        -ExpectedSizeMB 3 `
                        -SilentArgs "--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.CoreEditor") }
  # uv - native aarch64.
  $Results += @{ Id='uv'; Ok=(Install-ReviewPCWinget -PackageId "astral-sh.uv") }
  # Miniconda3 - documented WARN: no native Windows-ARM64 installer exists
  # (verified live: Miniconda3-latest-Windows-arm64.exe -> HTTP 404; repo ships
  # only Windows x86/x64). Install official x86_64 build -> runs under x64
  # emulation. Prefer system ARM64 Python + uv/pip for new envs.
  $Results += @{ Id='miniconda'; Ok=(Install-ReviewPCDownloadAndRun `
                        -Url "https://repo.anaconda.com/miniconda/Miniconda3-latest-Windows-x86_64.exe" `
                        -FileName "Miniconda3-latest-Windows-x86_64.exe" `
                        -ExpectedSizeMB 90 `
                        -SilentArgs "/InstallationType=JustMe /RegisterPython=0 /S /D=$env:LOCALAPPDATA\miniconda3") }

  # --- 4) AI tooling ---
  Write-Host "[Install] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - [ARM64] Installing AI tooling..." -ForegroundColor Cyan
  $Results += @{ Id='lmstudio'; Ok=(Install-ReviewPCWinget -PackageId "ElementLabs.LMStudio") }
  # Ollama - NATIVE ARM64 zip from GitHub latest.
  $Results += @{ Id='ollama'; Ok=(Install-ReviewPCOllamaArm64) }

  # --- 5) Benchmark / monitoring trio ---
  Write-Host "[Install] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - [ARM64] Installing benchmarks/monitoring..." -ForegroundColor Cyan
  # CPU-Z / HWMonitor: native ARM64 ships as SEPARATE portable zips (no winget
  # ARM64 coverage). URLs verified HTTP 200. If a zip version advances, update
  # the pinned 1.05 below (HEAD check fails loudly, never silent-WARN).
  $Results += @{ Id='cpu-z'; Ok=(Install-ReviewPCDownloadAndExtract `
                        -Url "https://download.cpuid.com/cpu-z/arm64/cpuz-arm64_1.05.zip" `
                        -FileName "cpuz-arm64_1.05.zip" `
                        -ExpectedSizeMB 2 `
                        -ExtractTo "$env:ProgramFiles\CPU-Z") }
  $Results += @{ Id='hwmonitor'; Ok=(Install-ReviewPCDownloadAndExtract `
                        -Url "https://download.cpuid.com/hwmonitor/arm64/hwmonitor-arm64_1.05.zip" `
                        -FileName "hwmonitor-arm64_1.05.zip" `
                        -ExpectedSizeMB 1 `
                        -ExtractTo "$env:ProgramFiles\HWMonitor") }
  $Results += @{ Id='crystaldiskmark'; Ok=(Install-ReviewPCWinget -PackageId "CrystalDewWorld.CrystalDiskMark") }

  # --- 6) Media / productivity ---
  Write-Host "[Install] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - [ARM64] Installing media/productivity..." -ForegroundColor Cyan
  # Install-ReviewPCWinget -PackageId "OBSProject.OBSStudio"   # obs-studio (commented out, as on x64)
  $Results += @{ Id='vlc';  Ok=(Install-ReviewPCWinget -PackageId "VideoLAN.VLC") }
  # Install-ReviewPCWinget -PackageId "7zip.7zip"              # 7-Zip (commented out, as on x64)

  # --- 7) Utilities ---
  Write-Host "[Install] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - [ARM64] Installing utilities..." -ForegroundColor Cyan
  $Results += @{ Id='notepadpp'; Ok=(Install-ReviewPCWinget -PackageId "Notepad++.Notepad++") }
  $Results += @{ Id='powertoys';  Ok=(Install-ReviewPCWinget -PackageId "Microsoft.PowerToys") }
  $Results += @{ Id='terminal';   Ok=(Install-ReviewPCWinget -PackageId "Microsoft.WindowsTerminal") }

  Write-Host "[Install] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - All ARM64 app installs requested." -ForegroundColor Green
}

# ---------------------------------------------------------------------
# Self-verification: assert each expected install path (single source of
# truth = Get-ReviewPCAppCatalog). Independent of the mechanism used.
# ---------------------------------------------------------------------
Write-Host "[Install] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Verifying installed app paths..." -ForegroundColor Cyan
# Pick up PATH entries the installers just added (CLI fallback lookups).
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("Path","User")
$allOk = $true
foreach ($entry in $Results) {
  if ($entry.Ok) {
    $appPathOk = Assert-ReviewPCAppPath -Id $entry.Id
    if (-not $appPathOk) { $allOk = $false }
  } else {
    Write-Host "[Install] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - WARNING: $($entry.Id) install helper reported failure; support this app manually." -ForegroundColor Yellow
    $allOk = $false
  }
}

# Configure Git if parameters were provided
if ($GitUserName -and $GitUserEmail) {
  Write-Host "[Install] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Configuring Git..." -ForegroundColor Cyan
  Set-ReviewPCGitConfig -UserName $GitUserName -UserEmail $GitUserEmail -ScriptPrefix "Install"
}

if (-not $IsArm64) {
  # The x64 path reports per-package results inline (Chocolatey exit codes).
  Write-Host "[Install] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Installer finished." -ForegroundColor Green
} elseif ($allOk) {
  Write-Host "[Install] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Installer finished; all primary binaries verified present." -ForegroundColor Green
} else {
  Write-Host "[Install] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Installer finished with some apps unverified - review the warnings above and run the audit." -ForegroundColor Yellow
}

Stop-ReviewPCLogging
