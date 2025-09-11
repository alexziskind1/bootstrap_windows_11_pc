<#
  Common.Utils.ps1
  Shared utility functions for ReviewPC scripts
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

# Function to install a package with enhanced logging
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
        & $ScriptPath @Arguments
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

# Functions are automatically available when the script is dot-sourced or imported
