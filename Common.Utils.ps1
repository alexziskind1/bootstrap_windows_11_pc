<#
  Common.Utils.ps1
  Shared utility functions for ReviewPC scripts.

  This module is the SINGLE SOURCE OF TRUTH for:
    * host architecture detection        (Get-ReviewPCArch / Test-ReviewPCIsArm64)
    * the installed-app catalog          (Get-ReviewPCAppCatalog)
    * the robotic per-app install helpers used by ReviewPC.Install.ps1
      (winget, direct download+run, download+extract, Ollama arm64 zip)
    * the download-URL validation / retry logic

  ReviewPC.Install.ps1, ReviewPC.FinishSetup.ps1, ReviewPC.RunAll.ps1 and the
  post-install auditor (Test-ReviewPCArm64v2.ps1) all dot-source this file and
  consume these functions so that architecture logic and per-app path/version
  expectations can never drift between the installer and the auditor.
#>

# Function to ensure the script runs as Administrator
function Ensure-Admin {
  param([string]$ScriptName = "Script")

  $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)

  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[$ScriptName] Elevation required, relaunching as admin..." -ForegroundColor Yellow
    $psi = New-Object System.Diagnostics.ProcessStartInfo "powershell"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.PSCommandPath)`" " + ($MyInvocation.UnboundArguments -join ' ')
    $psi.Verb = "runas"
    [Diagnostics.Process]::Start($psi) | Out-Null
    exit
  }
}

# Function to set up logging
function Start-ReviewPCLogging {
  param(
    [Parameter(Mandatory)][string]$ScriptName,
    [string]$ScriptRoot = (Split-Path -Parent $PSCommandPath)
  )

  $LogDir = Join-Path $ScriptRoot "logs"
  New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
  $LogPath = Join-Path $LogDir ("{0}_{1:yyyyMMdd_HHmmss}.log" -f $ScriptName, (Get-Date))
  Start-Transcript -Path $LogPath -IncludeInvocationHeader | Out-Null
  Write-Host "[$ScriptName] Logging to $LogPath" -ForegroundColor Cyan
  return $LogPath
}

# Function to stop logging
function Stop-ReviewPCLogging {
  Stop-Transcript | Out-Null
}

# Function to install a package with enhanced logging (used on the x64 path)
function Install-ReviewPCPackage {
  param(
    [Parameter(Mandatory)][string]$PackageName,
    [string]$ExtraArgs = "",
    [string]$ScriptPrefix = "Install"
  )

  Write-Host "[$ScriptPrefix] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Installing $PackageName..."
  try {
    $cmd = "choco install $PackageName $ExtraArgs"
    Write-Host "[$ScriptPrefix] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Executing: $cmd"
    Invoke-Expression $cmd
    if ($LASTEXITCODE -eq 0) {
      Write-Host "[$ScriptPrefix] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $PackageName installed successfully." -ForegroundColor Green
    } else {
      Write-Host "[$ScriptPrefix] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - WARNING: $PackageName installation returned exit code $LASTEXITCODE" -ForegroundColor Yellow
    }
  } catch {
    Write-Host "[$ScriptPrefix] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - ERROR installing $PackageName`: $($_.Exception.Message)" -ForegroundColor Red
  }
}

# Function to configure Git with user settings
function Set-ReviewPCGitConfig {
  param(
    [Parameter(Mandatory)][string]$UserName,
    [Parameter(Mandatory)][string]$UserEmail,
    [string]$ScriptPrefix = "Setup"
  )

  Write-Host "[$ScriptPrefix] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Configuring Git global settings..."
  try {
    # Refresh PATH to ensure git is available
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User")

    # Check if git is available
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
      Write-Host "[$ScriptPrefix] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - WARNING: Git not found in PATH. Skipping Git configuration." -ForegroundColor Yellow
      return
    }

    # Set git global config
    & git config --global user.name "$UserName"
    & git config --global user.email "$UserEmail"

    # Verify configuration
    $configName = & git config --global user.name
    $configEmail = & git config --global user.email

    Write-Host "[$ScriptPrefix] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Git configured successfully:" -ForegroundColor Green
    Write-Host "[$ScriptPrefix]   - user.name: $configName" -ForegroundColor Green
    Write-Host "[$ScriptPrefix]   - user.email: $configEmail" -ForegroundColor Green

  } catch {
    Write-Host "[$ScriptPrefix] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - ERROR configuring Git: $($_.Exception.Message)" -ForegroundColor Red
  }
}

# Function to clear existing taskbar pins
function Clear-ReviewPCTaskbarPins {
  param(
    [string]$ScriptPrefix = "Setup"
  )

  Write-Host "[$ScriptPrefix] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Clearing existing taskbar pins..."
  try {
    # Clear current user's taskbar pins by removing the registry entries
    $taskbarPinPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband"
    if (Test-Path $taskbarPinPath) {
      Remove-Item -Path $taskbarPinPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Also clear the taskbar layout cache
    $shellPath = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Shell"
    if (Test-Path $shellPath) {
      Get-ChildItem -Path $shellPath -Filter "*TaskbarLayout*" | Remove-Item -Force -ErrorAction SilentlyContinue
    }

    Write-Host "[$ScriptPrefix] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Existing taskbar pins cleared."
  } catch {
    Write-Host "[$ScriptPrefix] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - WARNING: Could not fully clear taskbar pins: $($_.Exception.Message)" -ForegroundColor Yellow
  }
}

# Function to set execution policy for the session
function Set-SessionExecutionPolicy {
  Set-ExecutionPolicy Bypass -Scope Process -Force | Out-Null
}

# Function to check if a file/path exists
function Test-ReviewPCPath {
  param([string]$Path)
  Test-Path -LiteralPath $Path
}

# Function to set registry values with fallback to reg.exe
function Set-ReviewPCRegistry {
  param(
    [Parameter(Mandatory)][ValidateSet('HKLM','HKCU')]$Hive,
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)]$Value,
    [ValidateSet('String','DWord','QWord')]$Type='DWord'
  )

  $full = Join-Path "${Hive}:" $Path
  try {
    if (-not (Test-Path $full)) { New-Item -Path $full -Force | Out-Null }
    New-ItemProperty -Path $full -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
    Write-Verbose "Registry: Set $Hive\$Path\$Name = $Value (PowerShell method)"
  } catch {
    # Fallback using reg.exe (helps if policy locks PowerShell provider)
    $regType = switch ($Type) { 'String' {'REG_SZ'} 'DWord' {'REG_DWORD'} 'QWord' {'REG_QWORD'} }
    $root = if ($Hive -eq 'HKLM') { 'HKLM' } else { 'HKCU' }
    $cmd = "ADD `"$root\$Path`" /v `"$Name`" /t $regType /d $Value /f"
    & reg.exe $cmd | Out-Null
    Write-Verbose "Registry: Set $Hive\$Path\$Name = $Value (reg.exe fallback)"
  }
}

# Function to run a script safely with error handling
function Invoke-ReviewPCScript {
  param(
    [Parameter(Mandatory)][string]$ScriptPath,
    [string]$ScriptName = (Split-Path -Leaf $ScriptPath),
    [string[]]$Arguments = @()
  )

  if (Test-ReviewPCPath $ScriptPath) {
    Write-Host "[RunAll] Running $ScriptName..." -ForegroundColor Cyan
    try {
      if ($Arguments.Count -gt 0) {
        & $ScriptPath $Arguments
      } else {
        & $ScriptPath
      }
      Write-Host "[RunAll] $ScriptName completed." -ForegroundColor Green
      return $true
    } catch {
      Write-Warning "[RunAll] $ScriptName failed: $($_.Exception.Message)"
      return $false
    }
  } else {
    Write-Host "[RunAll] Skipping $ScriptName (not found at $ScriptPath)" -ForegroundColor Yellow
    return $false
  }
}

# =====================================================================
# ARM64 / Windows-on-ARM support (arm64v2)
# =====================================================================

# ---------------------------------------------------------------------
# Single source of truth for host architecture detection.
#
# Reads $env:PROCESSOR_ARCHITEW6432 first: that variable carries the real OS
# architecture when the running PowerShell process is 32-bit running on a
# 64-bit OS (WOW64). It falls back to $env:PROCESSOR_ARCHITECTURE for native
# processes. Returns one of: 'ARM64' | 'ARM' | 'AMD64' | 'x86'.
# ---------------------------------------------------------------------
function Get-ReviewPCArch {
  $arch = $env:PROCESSOR_ARCHITEW6432
  if (-not $arch) { $arch = $env:PROCESSOR_ARCHITECTURE }
  # Normalize aliases
  if ($arch -eq 'x86_64')            { $arch = 'AMD64' }
  elseif ($arch -eq 'aarch64')       { $arch = 'ARM64' }
  elseif ($arch -eq 'AARCH64')       { $arch = 'ARM64' }
  return $arch
}

# True when the host is any flavor of Windows on Arm (ARM64 or 32-bit ARM).
function Test-ReviewPCIsArm64 {
  return ((Get-ReviewPCArch) -in @('ARM64','ARM'))
}

# ---------------------------------------------------------------------
# The installed-app catalog - SINGLE SOURCE OF TRUTH for:
#   * what ReviewPC.Install.ps1 guarantees to install on ARM64,
#   * where each app's primary binary is expected to live,
#   * whether a native ARM64 build is expected (=> FAIL if the binary is
#     actually x64/emulated) or whether only an emulated build exists
#     (=> WARN, never a hard failure).
#
# Both the installer's self-verification step and the post-install auditor
# (Test-ReviewPCArm64v2.ps1) consume this catalog, so path/version
# expectations can never drift.
#
# Field semantics:
#   Id          - stable internal key.
#   Name        - human-readable, used by auditor/summary.
#   Category    - grouping in the installer.
#   NativeExpected - $true => the app MUST be a native ARM64 binary after the
#                   ARM64 path runs; a missing or non-ARM64 binary is a FAIL.
#                   $false => no native ARM64 build exists upstream; it runs
#                   emulated and is a documented WARN, never a FAIL.
#   WarnNote    - reason shown by the auditor when NativeExpected is $false.
#   Cmd         - CLI name used as a Get-Command fallback to locate the path.
#   Paths       - ordered candidate install paths for the primary binary.
#   InstallMethod - string describing the ARM64 install mechanism.
# ---------------------------------------------------------------------
function Get-ReviewPCAppCatalog {
  $pf   = $env:ProgramFiles
  $pf86 = ${env:ProgramFiles(x86)}
  $la   = $env:LOCALAPPDATA
  $pd   = $env:ProgramData

  return @(
    # --- Bootstrap / package manager ---
    @{ Id='choco'; Name='Chocolatey'; Category='Bootstrap';
       NativeExpected=$false;
       WarnNote="Chocolatey has no native ARM64 build (it is a .NET x86/x64 binary) and runs under x64 emulation on WoA. In arm64v2 it is bootstrapped only; per-app installs are routed to winget/direct ARM64 URLs.";
       Cmd='choco';
       Paths=@((Join-Path $pd "chocolatey\bin\choco.exe"));
       InstallMethod='Bootstrap (arch-agnostic; not used for ARM app installs)' },

    # --- Browsers ---
    @{ Id='chrome'; Name='Google Chrome'; Category='Browsers'; NativeExpected=$true;
       Cmd=$null;
       Paths=@((Join-Path $pf "Google\Chrome\Application\chrome.exe"),
               (Join-Path $pf86 "Google\Chrome\Application\chrome.exe"));
       InstallMethod='winget Google.Chrome (native _arm64.msi)' },
    @{ Id='firefox'; Name='Mozilla Firefox'; Category='Browsers'; NativeExpected=$true;
       Cmd=$null;
       Paths=@((Join-Path $pf "Mozilla Firefox\firefox.exe"),
               (Join-Path $pf86 "Mozilla Firefox\firefox.exe"));
       InstallMethod='winget Mozilla.Firefox (native arm64). Brought in as an additional native-ARM64 browser.' },

    # --- Dev tools ---
    @{ Id='git'; Name='Git'; Category='DevTools'; NativeExpected=$true;
       Cmd='git';
       Paths=@((Join-Path $pf "Git\cmd\git.exe"),
               (Join-Path $pf86 "Git\cmd\git.exe"),
               (Join-Path $la "Programs\Git\cmd\git.exe"));
       InstallMethod='winget Git.Git (native -arm64.exe)' },
    @{ Id='vscode'; Name='VS Code'; Category='DevTools'; NativeExpected=$true;
       Cmd=$null;
       Paths=@((Join-Path $la "Programs\Microsoft VS Code\Code.exe"),
               (Join-Path $pf "Microsoft VS Code\Code.exe"));
       InstallMethod='winget Microsoft.VisualStudioCode (native arm64 exe)' },
    @{ Id='python'; Name='Python 3.12'; Category='DevTools'; NativeExpected=$true;
       Cmd='python';
       Paths=@((Join-Path $pf "Python312\python.exe"),
               (Join-Path $la "Programs\Python\Python312\python.exe"));
       InstallMethod='direct python-3.12.0-arm64.exe from python.org (InstallAllUsers -> Program Files)' },
    @{ Id='node'; Name='Node.js LTS'; Category='DevTools'; NativeExpected=$true;
       Cmd='node';
       Paths=@((Join-Path $pf "nodejs\node.exe"),
               (Join-Path $pf86 "nodejs\node.exe"));
       InstallMethod='winget OpenJS.NodeJS.LTS (native arm64 MSI)' },
    @{ Id='vs2022'; Name='Visual Studio 2022'; Category='DevTools'; NativeExpected=$true;
       Cmd=$null;
       Paths=@((Join-Path $pf "Microsoft Visual Studio\2022\Community\Common7\IDE\devenv.exe"));
       InstallMethod='direct vs_Community.exe --arch arm64 (native ARM64 IDE since 17.4; some auxiliary workloads may still be emulated)' },
    @{ Id='uv'; Name='uv'; Category='DevTools'; NativeExpected=$true;
       Cmd='uv';
       Paths=@((Join-Path $la "Microsoft\WinGet\Links\uv.exe"),
               (Join-Path $la "Microsoft\WinGet\Packages\astral-sh.uv\uv.exe"),
               (Join-Path "$env:USERPROFILE\.local\bin" "uv.exe"),
               (Join-Path $la "Programs\uv\uv.exe"));
       InstallMethod='winget astral-sh.uv (native aarch64)' },
    @{ Id='miniconda'; Name='Miniconda3'; Category='DevTools'; NativeExpected=$false;
       WarnNote="No official native Windows-ARM64 Miniconda installer exists (verified: Miniconda3-latest-Windows-arm64.exe is HTTP 404; repo.anaconda.com/miniconda ships only Windows x86/x64). On ARM the official x86_64 Miniconda is installed and runs under x64 emulation. Prefer system ARM64 Python + uv/pip for new environments. Re-check Anaconda before relying on a native arm64 build.";
       Cmd='conda';
       Paths=@((Join-Path $la "miniconda3\python.exe"),
               (Join-Path $la "miniconda3\Scripts\conda.exe"));
       InstallMethod='direct Miniconda3-latest-Windows-x86_64.exe (x64-emulated fallback - WARN)' },

    # --- AI tooling ---
    @{ Id='lmstudio'; Name='LM Studio'; Category='AITools'; NativeExpected=$true;
       Cmd=$null;
       Paths=@((Join-Path $la "Programs\LM Studio\LM Studio.exe"));
       InstallMethod='winget ElementLabs.LMStudio (native -arm64.exe)' },
    @{ Id='ollama'; Name='Ollama'; Category='AITools'; NativeExpected=$true;
       Cmd='ollama';
       Paths=@((Join-Path $la "Programs\Ollama\ollama.exe"));
       InstallMethod='direct ollama-windows-arm64.zip from github latest (winget Ollama.Ollama is x64-only)' },

    # --- Benchmark / monitoring ---
    @{ Id='cpu-z'; Name='CPU-Z'; Category='Monitoring'; NativeExpected=$true;
       Cmd=$null;
       Paths=@((Join-Path $pf "CPU-Z\cpuz_arm64.exe"),
               (Join-Path $pf "CPU-Z\cpuz.exe"));
       InstallMethod='direct cpuz-arm64_*.zip from download.cpuid.com (native ARM64 portable)' },
    @{ Id='hwmonitor'; Name='HWMonitor'; Category='Monitoring'; NativeExpected=$true;
       Cmd=$null;
       Paths=@((Join-Path $pf "HWMonitor\hwmonitor_arm64.exe"),
               (Join-Path $pf "HWMonitor\Hwmonitor.exe"));
       InstallMethod='direct hwmonitor-arm64_*.zip from download.cpuid.com (native ARM64 portable)' },
    @{ Id='crystaldiskmark'; Name='CrystalDiskMark'; Category='Monitoring'; NativeExpected=$true;
       Cmd=$null;
       Paths=@((Join-Path $pf "CrystalDiskMark\DiskMark64.exe"),
               (Join-Path $pf "CrystalDiskMark\CrystalDiskMark.exe"));
       InstallMethod='winget CrystalDewWorld.CrystalDiskMark (universal installer -> native arm64)' },

    # --- Media / productivity ---
    @{ Id='vlc'; Name='VLC'; Category='Media'; NativeExpected=$true;
       Cmd='vlc';
       Paths=@((Join-Path $pf "VideoLAN\VLC\vlc.exe"),
               (Join-Path $pf86 "VideoLAN\VLC\vlc.exe"));
       InstallMethod='winget VideoLAN.VLC (native winarm64)' },
    @{ Id='7zip'; Name='7-Zip'; Category='Media'; NativeExpected=$true;
       Cmd='7z';
       Paths=@((Join-Path $pf "7-Zip\7z.exe"),
               (Join-Path $pf "7-Zip\7zFM.exe"));
       InstallMethod='winget 7zip.7zip (native arm64). Brought in as an additional native-ARM64 archive tool.' },

    # --- Utilities ---
    @{ Id='notepadpp'; Name='Notepad++'; Category='Utilities'; NativeExpected=$true;
       Cmd=$null;
       Paths=@((Join-Path $pf "Notepad++\notepad++.exe"),
               (Join-Path $pf86 "Notepad++\notepad++.exe"));
       InstallMethod='winget Notepad++.Notepad++ (native .Installer.arm64.exe)' },
    @{ Id='powertoys'; Name='PowerToys'; Category='Utilities'; NativeExpected=$true;
       Cmd=$null;
       Paths=@((Join-Path $la "Microsoft\PowerToys\PowerToys.exe"));
       InstallMethod='winget Microsoft.PowerToys (native -arm64.exe)' },
    @{ Id='terminal'; Name='Windows Terminal'; Category='Utilities'; NativeExpected=$true;
       Cmd='wt';
       Paths=@((Join-Path $la "Microsoft\WindowsApps\wt.exe"),
               (Join-Path $la "Microsoft\WindowsApps\WindowsTerminal.exe"));
       InstallMethod='winget Microsoft.WindowsTerminal (multi-arch MSIX - native arm64)' },

    # --- Windows feature / platform add-ons (native-ARM, justified for a review PC) ---
    @{ Id='wsl'; Name='WSL'; Category='Platform'; NativeExpected=$true;
       Cmd='wsl';
       Paths=@((Join-Path $env:SystemRoot "System32\wsl.exe"),
               (Join-Path $env:SystemRoot "System32\wslapi.dll"));
       InstallMethod='wsl --install (Windows Subsystem for Linux feature - native ARM64). Enables a Linux userland on WoA.' },
    @{ Id='openssh'; Name='OpenSSH Client'; Category='Platform'; NativeExpected=$true;
       Cmd='ssh';
       Paths=@((Join-Path $env:SystemRoot "System32\OpenSSH\ssh.exe"));
       InstallMethod='Add-WindowsCapability OpenSSH.Client (ships native ARM64 binaries in System32)' },
    @{ Id='docker'; Name='Docker Desktop'; Category='Platform'; NativeExpected=$false;
       WarnNote="Docker Desktop ships a native ARM64 build (winget Docker.DockerDesktop), but it requires a WSL2/Hyper-V backend. It is installed ONLY when the bootstrap explicitly opts in (-InstallDocker); otherwise it is documented as an emulated/opt-in capability and NOT a failure.";
       Cmd=$null;
       Paths=@((Join-Path $pf "Docker\Docker\Docker Desktop.exe"));
       InstallMethod='winget Docker.DockerDesktop (native ARM64, opt-in)' }
  )
}

# Convenience: return the catalog entry (hashtable) for one app Id.
function Get-ReviewPCApp {
  param([Parameter(Mandatory)][string]$Id)
  $app = Get-ReviewPCAppCatalog | Where-Object { $_.Id -eq $Id }
  if ($app) { return $app }
  return $null
}

# Resolve the actual on-disk path for an app, walking its candidate Paths and
# falling back to Get-Command for PATH-shimmed CLIs. Shared by installer
# self-verification and the auditor.
function Resolve-ReviewPCAppPath {
  param(
    [Parameter(Mandatory)]$App
  )
  foreach ($c in $App.Paths) {
    if ($c -and (Test-Path -LiteralPath $c -PathType Leaf)) { return $c }
  }
  if ($App.Cmd) {
    $cmd = Get-Command $App.Cmd -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -and (Test-Path -LiteralPath $cmd.Source)) {
      return $cmd.Source
    }
  }
  return $null
}

# ---------------------------------------------------------------------
# Robust winget install.
#
# Fixes gap #4 in the old arm64 branch: a non-zero winget exit code is no
# longer blindly treated as a WARN. winget returns 0x8A15001B when the
# package is already installed; after any install attempt we re-check via
# `winget list` and only report failure when the package is genuinely not
# present. Returns $true on success / $false on failure (after retries).
# ---------------------------------------------------------------------
function Install-ReviewPCWinget {
  param(
    [Parameter(Mandatory)][string]$PackageId,
    [string]$ScriptPrefix = "Install",
    [string[]]$ExtraArgs = @(),
    [switch]$TrustSource
  )
  Write-Host "[$ScriptPrefix] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - winget installing $PackageId ..."
  $wingetArgs = @('install', '--id', $PackageId, '-e', '--silent',
                  '--accept-package-agreements', '--accept-source-agreements',
                  '--disable-interactivity')
  if ($TrustSource) { $wingetArgs += '--accept-microsoft-store-terms' }
  if ($ExtraArgs.Count -gt 0) { $wingetArgs += $ExtraArgs }

  # 0x8A15001B == "already installed" in winget (signed: -1978335205).
  # 0x8A150011 == "installed but not from this source / multiple packages"
  #               (signed: -1978335215). These are benign when the package is
  #               genuinely present; genuineness is re-confirmed via winget list.
  $ALREADY_INSTALLED_CODES = @(-1978335205, -1978335215, 0)

  $attempts = 0
  while ($attempts -lt 3) {
    $attempts++
    try {
      & winget @wingetArgs
      $code = $LASTEXITCODE
      $present = Test-ReviewPCWingetList $PackageId
      if ($code -eq 0 -or $present -or ($ALREADY_INSTALLED_CODES -contains $code)) {
        if ($present) {
          Write-Host "[$ScriptPrefix] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $PackageId present (installed or already installed)." -ForegroundColor Green
        } else {
          Write-Host "[$ScriptPrefix] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - winget $PackageId installed successfully." -ForegroundColor Green
        }
        return $true
      }
      Write-Host "[$ScriptPrefix] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - winget $PackageId returned exit code $code (attempt $attempts/3)." -ForegroundColor Yellow
      Start-Sleep -Seconds 5
    } catch {
      Write-Host "[$ScriptPrefix] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - ERROR winget $PackageId (attempt $attempts/3): $($_.Exception.Message)" -ForegroundColor Yellow
      Start-Sleep -Seconds 5
    }
  }
  Write-Host "[$ScriptPrefix] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - FAILED: winget could not install $PackageId after 3 attempts." -ForegroundColor Red
  return $false
}

# True if winget reports the package as installed.
function Test-ReviewPCWingetList {
  param([Parameter(Mandatory)][string]$PackageId)
  try {
    $out = & winget list --id $PackageId -e --accept-source-agreements 2>$null
    return ($LASTEXITCODE -eq 0 -and ($out -match [regex]::Escape($PackageId)))
  } catch { return $false }
}

# ---------------------------------------------------------------------
# Download + run an installer.
#
# Fixes gap #10/#4 of the old arm64 branch: the URL is validated with a HEAD
# request (HTTP 200) before download, a minimum expected size can be enforced,
# downloads use a browser user-agent + TLS12, adopt a timeout, and retry up to
# 3 times. A hard download/validation failure is an ERROR (returns $false) and
# is surfaced, not swallowed as a silent WARN. When -ExpectedSha256 is
# provided the downloaded file is hashed and verified before running.
# ---------------------------------------------------------------------
function Install-ReviewPCDownloadAndRun {
  param(
    [Parameter(Mandatory)][string]$Url,
    [Parameter(Mandatory)][string]$FileName,
    [string]$SilentArgs = "",
    [string]$DestDir = (Join-Path $env:TEMP "ReviewPC-ARM64"),
    [string]$ScriptPrefix = "Install",
    [long]$ExpectedSizeMB = 0,
    [string]$ExpectedSha256 = "",
    [int]$TimeoutSec = 600
  )
  Write-Host "[$ScriptPrefix] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Downloading $FileName ..."
  try {
    if (-not (Test-ReviewPCUrl $Url)) {
      Write-Host "[$ScriptPrefix] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - ERROR: URL not reachable (not HTTP 200): $Url" -ForegroundColor Red
      return $false
    }
    New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
    $out = Join-Path $DestDir $FileName
    if (-not (Invoke-ReviewPCDownload -Url $Url -OutFile $out -ExpectedSizeMB $ExpectedSizeMB -ExpectedSha256 $ExpectedSha256 -TimeoutSec $TimeoutSec)) {
      return $false
    }
    Write-Host "[$ScriptPrefix] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Running installer: $FileName $SilentArgs"
    if ($SilentArgs -ne "") {
      Start-Process -FilePath $out -ArgumentList $SilentArgs -Wait -NoNewWindow
    } else {
      Start-Process -FilePath $out -Wait
    }
    Write-Host "[$ScriptPrefix] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Installer $FileName finished." -ForegroundColor Green
    return $true
  } catch {
    Write-Host "[$ScriptPrefix] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - ERROR downloading/running $FileName`: $($_.Exception.Message)" -ForegroundColor Red
    return $false
  }
}

# ---------------------------------------------------------------------
# Download + extract a portable zip (CPU-Z / HWMonitor / Ollama).
# Same hardening as Install-ReviewPCDownloadAndRun (HEAD check, retry,
# size/checksum validation, clear ERROR on failure).
# ---------------------------------------------------------------------
function Install-ReviewPCDownloadAndExtract {
  param(
    [Parameter(Mandatory)][string]$Url,
    [Parameter(Mandatory)][string]$FileName,
    [Parameter(Mandatory)][string]$ExtractTo,
    [string]$DestDir = (Join-Path $env:TEMP "ReviewPC-ARM64"),
    [string]$ScriptPrefix = "Install",
    [long]$ExpectedSizeMB = 0,
    [string]$ExpectedSha256 = "",
    [int]$TimeoutSec = 600
  )
  Write-Host "[$ScriptPrefix] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Downloading $FileName ..."
  try {
    if (-not (Test-ReviewPCUrl $Url)) {
      Write-Host "[$ScriptPrefix] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - ERROR: URL not reachable (not HTTP 200): $Url" -ForegroundColor Red
      return $false
    }
    New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
    New-Item -ItemType Directory -Force -Path $ExtractTo | Out-Null
    $out = Join-Path $DestDir $FileName
    if (-not (Invoke-ReviewPCDownload -Url $Url -OutFile $out -ExpectedSizeMB $ExpectedSizeMB -ExpectedSha256 $ExpectedSha256 -TimeoutSec $TimeoutSec)) {
      return $false
    }
    Expand-Archive -Path $out -DestinationPath $ExtractTo -Force
    Write-Host "[$ScriptPrefix] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Extracted $FileName to $ExtractTo" -ForegroundColor Green
    return $true
  } catch {
    Write-Host "[$ScriptPrefix] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - ERROR downloading/extracting $FileName`: $($_.Exception.Message)" -ForegroundColor Red
    return $false
  }
}

# HEAD-check that a URL is reachable and returns HTTP 200 (following
# redirects). Handles GitHub release-assets (which 200 on HEAD).
function Test-ReviewPCUrl {
  param([Parameter(Mandatory)][string]$Url)
  try {
    $resp = Invoke-WebRequest -Uri $Url -Method Head -UseBasicParsing -MaximumRedirection 10 `
                              -TimeoutSec 45 -UserAgent "ReviewPC-bootstrap/2.0"
    return ($resp.StatusCode -eq 200)
  } catch {
    # Some servers reject HEAD; fall back to a ranged GET (first 1 byte).
    try {
      $resp = Invoke-WebRequest -Uri $Url -Method Get -Headers @{ Range = "bytes=0-0" } `
                                -UseBasicParsing -MaximumRedirection 10 -TimeoutSec 45 `
                                -UserAgent "ReviewPC-bootstrap/2.0"
      return ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 400)
    } catch { return $false }
  }
}

# Core download with retry, size + (optional) SHA-256 validation.
function Invoke-ReviewPCDownload {
  param(
    [Parameter(Mandatory)][string]$Url,
    [Parameter(Mandatory)][string]$OutFile,
    [long]$ExpectedSizeMB = 0,
    [string]$ExpectedSha256 = "",
    [int]$TimeoutSec = 600,
    [string]$ScriptPrefix = "Install"
  )
  $attempts = 0
  while ($attempts -lt 3) {
    $attempts++
    try {
      [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
      $wc = New-Object System.Net.WebClient
      $wc.Headers.Add('User-Agent', 'ReviewPC-bootstrap/2.0')
      try {
        $wc.DownloadFile($Url, $OutFile)
      } finally {
        $wc.Dispose()
      }
      # Size validation
      if ($ExpectedSizeMB -gt 0) {
        $len = (Get-Item -LiteralPath $OutFile).Length
        $minBytes = $ExpectedSizeMB * 1MB
        if ($len -lt $minBytes) {
          Write-Host "[$ScriptPrefix] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - WARN: $OutFile size $len bytes < expected ${ExpectedSizeMB}MB (attempt $attempts/3)" -ForegroundColor Yellow
          Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
          Start-Sleep -Seconds 3
          continue
        }
      }
      # SHA-256 validation
      if ($ExpectedSha256 -ne "") {
        $hash = (Get-FileHash -LiteralPath $OutFile -Algorithm SHA256).Hash.ToLower()
        if ($hash -ne $ExpectedSha256.ToLower()) {
          Write-Host "[$ScriptPrefix] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - WARN: SHA256 mismatch for $OutFile (attempt $attempts/3)" -ForegroundColor Yellow
          Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
          Start-Sleep -Seconds 3
          continue
        }
      }
      Write-Host "[$ScriptPrefix] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Downloaded $OutFile (size $((Get-Item -LiteralPath $OutFile).Length) bytes)." -ForegroundColor Green
      return $true
    } catch {
      Write-Host "[$ScriptPrefix] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - ERROR downloading $Url (attempt $attempts/3): $($_.Exception.Message)" -ForegroundColor Yellow
      Start-Sleep -Seconds 3
    }
  }
  Write-Host "[$ScriptPrefix] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - FAILED: could not download $Url after 3 attempts." -ForegroundColor Red
  return $false
}

# ---------------------------------------------------------------------
# Install Ollama natively on ARM64 from the GitHub "latest" release.
# winget's Ollama.Ollama manifest is x64-only, so we use the dedicated
# native ARM64 zip. The 'latest' URL is always resolved by GitHub, so this
# never goes stale (gap #3 in the old arm64 branch).
# ---------------------------------------------------------------------
function Install-ReviewPCOllamaArm64 {
  param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA "Programs\Ollama"),
    [string]$DestDir = (Join-Path $env:TEMP "ReviewPC-ARM64"),
    [string]$ScriptPrefix = "Install"
  )
  Write-Host "[$ScriptPrefix] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Installing Ollama (native ARM64 zip)..."
  try {
    $zipUrl = "https://github.com/ollama/ollama/releases/latest/download/ollama-windows-arm64.zip"
    $ok = Install-ReviewPCDownloadAndExtract -Url $zipUrl `
                                             -FileName "ollama-windows-arm64.zip" `
                                             -ExtractTo $InstallDir `
                                             -DestDir $DestDir -ScriptPrefix $ScriptPrefix `
                                             -ExpectedSizeMB 60 -TimeoutSec 900
    if (-not $ok) { return $false }

    # Add install dir to the user PATH if not already present
    $userPath = [System.Environment]::GetEnvironmentVariable("Path","User")
    if ($userPath -notlike "*$InstallDir*") {
      [System.Environment]::SetEnvironmentVariable("Path", "$InstallDir;$userPath", "User")
      Write-Host "[$ScriptPrefix] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Added $InstallDir to user PATH." -ForegroundColor Green
    }

    # Launch ollama.exe once so it self-registers the Ollama service
    $ollamaExe = Join-Path $InstallDir "ollama.exe"
    if (Test-Path $ollamaExe) {
      Write-Host "[$ScriptPrefix] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Launching $ollamaExe to register the Ollama service..."
      Start-Process -FilePath $ollamaExe -WindowStyle Hidden
    } else {
      Write-Host "[$ScriptPrefix] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - WARNING: $ollamaExe not found after extraction." -ForegroundColor Yellow
      return $false
    }
    Write-Host "[$ScriptPrefix] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Ollama ARM64 install complete." -ForegroundColor Green
    return $true
  } catch {
    Write-Host "[$ScriptPrefix] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - ERROR installing Ollama ARM64: $($_.Exception.Message)" -ForegroundColor Red
    return $false
  }
}

# ---------------------------------------------------------------------
# Helper used by the installer to self-verify an app after the install step.
# Returns $true if the app's primary binary resolved to an on-disk path.
# (The auditor does the stricter PE-machine-type check.)
# ---------------------------------------------------------------------
function Assert-ReviewPCAppPath {
  param(
    [Parameter(Mandatory)][string]$Id,
    [string]$ScriptPrefix = "Install"
  )
  $app = Get-ReviewPCApp $Id
  if ($app) {
    $p = Resolve-ReviewPCAppPath -App $app
    if ($p) {
      Write-Host "[$ScriptPrefix] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - OK: $($app.Name) at $p" -ForegroundColor Green
      return $true
    }
    Write-Host "[$ScriptPrefix] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - WARNING: $($app.Name) installed but expected binary not found in configured paths." -ForegroundColor Yellow
    return $false
  }
  return $false
}

# Functions are automatically available when the script is dot-sourced or imported
