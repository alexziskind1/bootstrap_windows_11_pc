<#
 Test-ReviewPCArm64v2.ps1 - post-install ARM64 audit for the arm64v2 branch

 Verifies that every app installed by ReviewPC.Install.ps1 on a Windows-on-ARM
 host is the NATIVE ARM64 build (not an x64-emulated binary). It reads the COFF
 PE header machine type of each primary executable and reports PASS / WARN / FAIL.

 This auditor:
   * Consolidates architecture detection and per-app expected-path/version data
     into the SINGLE SOURCE OF TRUTH (Common.Utils.ps1: Get-ReviewPCArch /
     Test-ReviewPCIsArm64 / Get-ReviewPCAppCatalog), so it can never drift from
     what the installer guarantees.
   * Classifies each app from the catalog:
       NativeExpected=$true  -> binary missing OR PE machine != 0xAA64 (ARM64)
                                is a FAIL.
       NativeExpected=$false -> no native ARM64 build upstream (Miniconda
                                or Chocolatey); presence /
                                emulated arch is a documented WARN, never FAIL.
   * Supports Live (default; requires an ARM64 host) and DryRun (docs/path
     check, runs on ANY machine including an x64 host).
   * Exits non-zero if any required, expected-native item is missing or not
     ARM64.

 Usage (AS ADMIN on the target Windows-on-ARM machine, after bootstrap):
   Set-ExecutionPolicy Bypass -Scope Process -Force
   .\Test-ReviewPCArm64v2.ps1

 On an x64 host (or to skip active checks), run a path/documentation check:
   .\Test-ReviewPCArm64v2.ps1 -Mode DryRun

 Verdict semantics:
   [PASS] exe found AND PE machine type is ARM64 (0xAA64), OR the app is a
          Windows Terminal MSIX reparse point (native multi-arch MSIX).
   [WARN] exe found but documented as emulated / no native ARM64 upstream
          (Miniconda3, Chocolatey). Never fails.
   [FAIL] exe NOT found (install likely failed / wrong path), OR found but is
          x64 (0x8664) / x86 (0x14c) / ARMv7 (0x1c4) where a NATIVE ARM64
          build should have been installed.
#>
[CmdletBinding()]
param(
  [ValidateSet('Live','DryRun')]
  [string]$Mode = 'Live'
)

$ErrorActionPreference = 'Stop'

# Single source of truth: architecture + catalog come from Common.Utils.ps1.
$ScriptRoot = Split-Path -Parent $PSCommandPath
$UtilsPath = Join-Path $ScriptRoot "Common.Utils.ps1"
if (-not (Test-Path -LiteralPath $UtilsPath)) {
  Write-Host "[audit] ERROR: Common.Utils.ps1 not found beside this script." -ForegroundColor Red
  exit 2
}
. $UtilsPath

# ---------------------------------------------------------------------------
# Read the COFF/PE machine type of an .exe/.dll.
#   e_lfanew (offset 0x3C in the DOS header) -> "PE\0\0" signature -> machine word.
#   Returns $null if the file is not a readable PE (e.g. a reparse point / alias).
#   Machine values: 0xAA64=ARM64, 0x8664=x64/AMD64, 0x14c=x86/i386, 0x1c4=ARMv7.
# ---------------------------------------------------------------------------
function Get-PEMachineType {
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  try {
    $fs = [System.IO.File]::OpenRead($Path)
    try {
      $br = New-Object System.IO.BinaryReader($fs)
      $fs.Seek(0x3C, [System.IO.SeekOrigin]::Begin) | Out-Null     # e_lfanew
      $e_lfanew = $br.ReadUInt32()
      if ($e_lfanew -ge $fs.Length) { return $null }
      $fs.Seek($e_lfanew, [System.IO.SeekOrigin]::Begin) | Out-Null
      $sig = $br.ReadUInt32()                                       # "PE\0\0"
      if ($sig -ne 0x00004550) { return $null }                     # not a PE image
      $machine = $br.ReadUInt16()                                   # COFF machine word
      return $machine
    } finally { $br.Dispose() }
  } catch { return $null }
}

function Get-MachineName([int]$m) {
  switch ($m) {
    0xAA64 { 'ARM64' }
    0x8664 { 'x64' }
    0x14c  { 'x86' }
    0x1c4  { 'ARMv7' }
    default { ('0x{0:X}' -f $m) }
  }
}

Write-Host "=========================================================="
Write-Host " ReviewPC ARM64v2 audit ($Mode mode)"
Write-Host "=========================================================="

$Items = Get-ReviewPCAppCatalog

# ---------------------------------------------------------------------------
# Completeness closure check (arm64v2).
#
# Enforces the "no app left unaudited" invariant for the whole suite:
#   * Every app the installer's ARM64 path references (via `$Results +=
#     @{ Id='...'; ... }` in ReviewPC.Install.ps1) must have a catalog entry.
#     If a future editor adds an app to the ARM install path but forgets to
#     add an ARM-equivalent entry to Get-ReviewPCAppCatalog, the audit would
#     otherwise silently skip it; we FAIL instead of skipping.
#   * Every catalog entry must declare its ARM64 InstallMethod (so the install
#     mechanism is explicit, never silent).
#   * No catalog Id may be duplicated, and the catalog must be non-empty, so
#     an editor cannot accidentally drop entries.
#
# (Presence of the primary binary vs. the declared path/CLI is verified by the
# Live evaluation loop below, which FAILs any native-expected app whose binary
# cannot be resolved or is non-ARM64. This completeness check is host-portable
# and therefore does not depend on Windows root env vars resolving to paths.)
#
# Runs in BOTH DryRun and Live modes (it is a static check that needs no
# Windows/filesystem), and contributes to the exit code (FAIL => non-zero).
# ---------------------------------------------------------------------------
function Get-ReviewPCInstallerArmIds {
  param([string]$InstallScript = (Join-Path $ScriptRoot "ReviewPC.Install.ps1"))
  $ids = @()
  try {
    if ($InstallScript -and (Test-Path -LiteralPath $InstallScript)) {
      foreach ($l in (Get-Content -LiteralPath $InstallScript)) {
        # Matches:  $Results += @{ Id='chrome'; Ok=... }
        if ($l -match '\$Results\s*\+=\s*@\{[^}]*\bId\s*=\s*''([^'']+)''') {
          $ids += $Matches[1]
        }
      }
    }
  } catch {
    Write-Host "[audit] WARNING: could not read ReviewPC.Install.ps1 for completeness check: $($_.Exception.Message)" -ForegroundColor Yellow
  }
  return @($ids | Sort-Object -Unique)
}

function Test-ReviewPCCatalogComplete {
  param([AllowNull()]$CatalogItems)
  $errs = 0
  $list = @($CatalogItems)
  if ($list.Count -eq 0) {
    Write-Host "[FAIL][completeness] Get-ReviewPCAppCatalog returned ZERO entries. The audit surface is empty - an editor likely dropped the catalog." -ForegroundColor Red
    return 1
  }
  $dup = $list | Group-Object Id | Where-Object { $_.Count -gt 1 }
  if ($dup) {
    foreach ($g in $dup) {
      Write-Host "[FAIL][completeness] Duplicate catalog Id '$($g.Name)' ($($g.Count) entries). Ids must be unique." -ForegroundColor Red
      $errs++
    }
  }
  foreach ($a in $list) {
    if ([string]::IsNullOrWhiteSpace($a.Id)) {
      Write-Host "[FAIL][completeness] Catalog entry missing 'Id'." -ForegroundColor Red
      $errs++
      continue
    }
    if ([string]::IsNullOrWhiteSpace($a.InstallMethod)) {
      Write-Host "[FAIL][completeness] Catalog entry '$($a.Id)' has an empty InstallMethod. Document how it is installed on ARM so the mechanism is explicit." -ForegroundColor Red
      $errs++
    }
  }
  foreach ($id in (Get-ReviewPCInstallerArmIds)) {
    if (-not ($list | Where-Object { $_.Id -eq $id })) {
      Write-Host "[FAIL][completeness] ReviewPC.Install.ps1 ARM path installs app '$id' but it has NO catalog entry (no auditable ARM equivalent). Add it to Get-ReviewPCAppCatalog." -ForegroundColor Red
      $errs++
    }
  }
  return $errs
}

$completenessFails = Test-ReviewPCCatalogComplete -CatalogItems $Items
if ($completenessFails -gt 0) {
  Write-Host "[FAIL][completeness] $completenessFails catalog completeness violation(s) found. See messages above." -ForegroundColor Red
}

if ($Mode -eq 'DryRun') {
  Write-Host "`n[DryRun] Documentation / path check. No ARM64 host required."
  Write-Host "This script locates each exe and reads its PE machine type; the"
  Write-Host "documented WARN items (Miniconda3, Chocolatey)"
  Write-Host "have no native ARM64 build upstream.`n"
  foreach ($i in $Items) {
    Write-Host "  [$($i.Id)] $($i.Name)  (NativeExpected=$($i.NativeExpected), method: $($i.InstallMethod))"
    foreach ($p in $i.Paths) {
      if ($p) { Write-Host ("      expected path: " + $p) }
    }
  }
  if ($completenessFails -gt 0) {
    Write-Host "`n[DryRun] FAILED: catalog completeness violations require fixes before this branch is trustworthy." -ForegroundColor Red
    exit 1
  }
  Write-Host "`n[DryRun] Done (exit 0)."
  exit 0
}

$HostArch = Get-ReviewPCArch
Write-Host "Detected host architecture: $HostArch`n"
if (-not (Test-ReviewPCIsArm64)) {
  Write-Host "This machine is NOT ARM64 ($HostArch). The Live ARM64 audit only"
  Write-Host "applies to Windows-on-ARM hosts. Re-run on an ARM64 machine, or"
  Write-Host "use -Mode DryRun for a docs/path check. Exiting 0."
  exit 0
}

# Pick up PATH entries added by the installers since this session started
# (the CLI fallback in Resolve-ReviewPCAppPath depends on it).
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("Path","User")

# ---------------------------------------------------------------------------
# Evaluate each item
# ---------------------------------------------------------------------------
$fail = 0
$results = @()
foreach ($i in $Items) {
  $name      = $i.Name
  $exePath   = Resolve-ReviewPCAppPath -App $i
  $nativeExp = $i.NativeExpected

  # Windows Terminal special-case: MSIX alias is a reparse point (PE unreadable)
  # and UWP apps are per-arch, so presence (native multi-arch MSIX) is PASS.
  if ($i.Id -eq 'terminal' -and $exePath -and -not (Get-PEMachineType $exePath)) {
    $results += @{ Id=$i.Id; Name=$name; Verdict='PASS'; Arch='ARM64(MSIX)'; Path=$exePath }
    Write-Host "[PASS] $name ARM64(MSIX) $exePath" -ForegroundColor Green
    continue
  }

  if (-not $exePath) {
    if ($nativeExp) {
      $results += @{ Id=$i.Id; Name=$name; Verdict='FAIL'; Arch='missing'; Path='' }
      Write-Host "[FAIL] $name missing (ARM64 install expected it but no binary found)" -ForegroundColor Red
      $fail++
    } else {
      $results += @{ Id=$i.Id; Name=$name; Verdict='WARN'; Arch='missing'; Path='' }
      Write-Host "[WARN] $name not found (no native ARM64 upstream; $($i.WarnNote))" -ForegroundColor Yellow
      if ($i.WarnNote) { Write-Host "       note: $($i.WarnNote)" }
    }
    continue
  }

  $machine = Get-PEMachineType $exePath
  if ($null -eq $machine) {
    if ($nativeExp) {
      $results += @{ Id=$i.Id; Name=$name; Verdict='FAIL'; Arch='unreadable'; Path=$exePath }
      Write-Host "[FAIL] $name present but PE header unreadable: $exePath" -ForegroundColor Red
      $fail++
    } else {
      $results += @{ Id=$i.Id; Name=$name; Verdict='WARN'; Arch='unreadable'; Path=$exePath }
      Write-Host "[WARN] $name present (PE unreadable; no native ARM64 upstream): $exePath" -ForegroundColor Yellow
    }
    continue
  }

  $archName = Get-MachineName $machine
  if ($machine -eq 0xAA64) {
    $results += @{ Id=$i.Id; Name=$name; Verdict='PASS'; Arch='ARM64'; Path=$exePath }
    Write-Host "[PASS] $name ARM64 $exePath" -ForegroundColor Green
  }
  elseif (-not $nativeExp) {
    $results += @{ Id=$i.Id; Name=$name; Verdict='WARN'; Arch=$archName; Path=$exePath }
    Write-Host "[WARN] $name $archName $exePath (no native ARM64 upstream; runs emulated)" -ForegroundColor Yellow
    if ($i.WarnNote) { Write-Host "       note: $($i.WarnNote)" }
  }
  else {
    $results += @{ Id=$i.Id; Name=$name; Verdict='FAIL'; Arch=$archName; Path=$exePath }
    Write-Host "[FAIL] $name is $archName (native ARM64 expected): $exePath" -ForegroundColor Red
    $fail++
  }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host "`n================= SUMMARY ================="
$pass = ($results | Where-Object Verdict -eq 'PASS').Count
$warn = ($results | Where-Object Verdict -eq 'WARN').Count
Write-Host ("PASS: " + $pass + "  WARN: " + $warn + "  FAIL: " + $fail)
Write-Host "WARN items (Miniconda3, Chocolatey) have no native"
Write-Host "ARM64 build upstream and intentionally run emulated; they are not failures."
if (($fail -gt 0) -or ($completenessFails -gt 0)) {
  if ($fail -gt 0) {
    Write-Host "`n*** $fail item(s) FAILED. Native ARM64 was expected for these but was" -ForegroundColor Red
    Write-Host "*** not found / not native. Review the ARM64 install path for them." -ForegroundColor Red
  }
  if ($completenessFails -gt 0) {
    Write-Host "`n*** $completenessFails catalog completeness violation(s) found (missing/duplicate/undocumented catalog entries)." -ForegroundColor Red
  }
  exit 1
}
Write-Host "`nAll required items are native ARM64 (or documented WARN)." -ForegroundColor Green
exit 0
