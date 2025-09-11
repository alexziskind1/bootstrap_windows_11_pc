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
  } catch {
    # Fallback using reg.exe (helps if policy locks PowerShell provider)
    $regType = switch ($Type) { 'String' {'REG_SZ'} 'DWord' {'REG_DWORD'} 'QWord' {'REG_QWORD'} }
    $root = if ($Hive -eq 'HKLM') { 'HKLM' } else { 'HKCU' }
    $cmd = "ADD `"$root\$Path`" /v `"$Name`" /t $regType /d $Value /f"
    & reg.exe $cmd | Out-Null
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
