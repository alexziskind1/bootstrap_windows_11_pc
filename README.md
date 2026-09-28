# ReviewPC Bootstrap Scripts

A modular set of PowerShell scripts to automate Windows 11 PC setup for reviews and deployment. The **`arm64v2`** branch correctly and **completely** handles **Windows on ARM (WoA)** — every app is installed as its native ARM64 build instead of an x64-emulated one.

## Scripts Overview

### Main Script
- **`ReviewPC.RunAll.ps1`** - One-click setup that runs all components in sequence (including the post-install ARM64 audit)

### Modular Components
- **`Common.Utils.ps1`** - Shared utilities: admin elevation, logging, registry, and the **single source of truth** for architecture detection (`Get-ReviewPCArch` / `Test-ReviewPCIsArm64`), the installed-app catalog (`Get-ReviewPCAppCatalog`), and the robust winget / direct-download install helpers
- **`ReviewPC.Debloat.ps1`** - Runs Win11Debloat with safe, recommended flags (arch-agnostic)
- **`ReviewPC.RemoveOneDrive.ps1`** - Completely removes OneDrive (arch-agnostic)
- **`ReviewPC.Install.ps1`** - Installs applications (Chocolatey on x64; native ARM64 via winget/direct URLs on ARM)
- **`ReviewPC.FinishSetup.ps1`** - Final configuration (Chrome default, taskbar pins, notifications, dev tweaks; includes an ARM-aware shortcut-presence check)
- **`Test-ReviewPCArm64v2.ps1`** - Post-install ARM64 auditor (PASS/WARN/FAIL, Live + DryRun, exits non-zero on FAIL)

## Usage

### Quick Start
```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\ReviewPC.RunAll.ps1
```

### Optional Parameters
- `-SysprepMode` - Apply debloat to Default profile (affects new users)
- `-Silent` - Hide debloat prompts (default: true)
- `-SkipAudit` - Do not run the post-install ARM64 audit at the end

### Individual Scripts
Each component can be run independently:
```powershell
.\ReviewPC.Debloat.ps1 -Silent
.\ReviewPC.RemoveOneDrive.ps1
.\ReviewPC.Install.ps1
.\ReviewPC.FinishSetup.ps1
.\Test-ReviewPCArm64v2.ps1                     # Live audit (ARM64 host)
.\Test-ReviewPCArm64v2.ps1 -Mode DryRun       # Path/docs check (any host)
```

## Features

### What Gets Debloated
- Removes OneDrive, gaming apps, communication apps, new Outlook
- Disables Copilot, telemetry, ads, suggestions
- Hides search bar, widgets, chat
- Clears start menu recommendations
- Creates system restore point

### What Gets Installed (x64 path — unchanged Chocolatey set)
- **Browsers:** Google Chrome
- **Dev Tools:** Git, VS Code, Python 3.12, Node.js LTS, Visual Studio 2022 Community, uv, Miniconda3
- **AI Tools:** LM Studio, Ollama
- **Utilities:** CPU-Z, HWMonitor, CrystalDiskMark, VLC, Notepad++, PowerToys, Windows Terminal

### What Gets Configured
- Chrome set as default browser
- Taskbar pins: Task Manager, Visual Studio, VS Code, Windows Terminal, Chrome
- Notifications disabled
- UI cleanup (Copilot, search, widgets hidden)
- Developer tweaks (long paths enabled, dev mode)
- Ultimate Performance power plan activated

## Logging
All scripts create timestamped logs in the `logs/` subdirectory for troubleshooting.

## Requirements
- Windows 11
- PowerShell 5.1 or later
- Administrator privileges (automatically requested)

---

## Windows on ARM (ARM64) support — `arm64v2`

The `arm64v2` branch makes the **whole suite** architecture-aware so the same one-click orchestrator works correctly on both x64 and ARM64 (Snapdragon / Surface) hosts.

On an **x64** host behavior is **unchanged** (everything still installs via Chocolatey). On an **ARM64** host `ReviewPC.Install.ps1` detects the architecture and installs the **native ARM64** build of every app instead of the x64 Chocolatey package, avoiding x64 binaries that would otherwise run under Windows ARM64 emulation.

### How it works
1. **Single source of truth.** `Common.Utils.ps1` owns `Get-ReviewPCArch` (reads `PROCESSOR_ARCHITEW6432` → `PROCESSOR_ARCHITECTURE`, normalizing `aarch64`/`ARM64`) and `Get-ReviewPCAppCatalog` — a table of every app with its expected install paths and whether a **native ARM64** build is expected. The installer, `FinishSetup.ps1`, and the auditor all consume these, so architecture logic and path/version expectations **cannot drift**.
2. **`ReviewPC.Install.ps1` branches on `$IsArm64`:**
   - **ARM64** → winget per-arch packages + direct ARM64 installer/zip URLs, each **HEAD-validated**, downloaded with **retry + size checks**, then each app's path is **self-verified**.
   - **x64** → the original Chocolatey block, unchanged.
3. **`ReviewPC.RunAll.ps1` wires the auditor in** as the final step, so the one-click flow self-verifies the ARM install.
4. **`ReviewPC.FinishSetup.ps1` verifies the Start-Menu `.lnk` files** the taskbar-pin step depends on, so a failed ARM install surfaces instead of silently no-oping.

### Per-app ARM64 mechanism

| App | ARM64 mechanism | Native? |
|-----|-----------------|---------|
| Chocolatey | Bootstrapped only (arch-agnostic); **not** used for ARM app installs | emulated (WARN) |
| Google Chrome | winget `Google.Chrome` (native `_arm64.msi`) | native |
| Git | winget `Git.Git` (native `-arm64.exe`) | native |
| VS Code | winget `Microsoft.VisualStudioCode` (native arm64) | native |
| Python 3.12.0 | direct `python-3.12.0-arm64.exe` from python.org (HTTP-verified) | native |
| Node.js LTS | winget `OpenJS.NodeJS.LTS` (native arm64 MSI) | native |
| Visual Studio 2022 Community | direct `vs_Community.exe` bootstrapper (auto-selects ARM64); **native ARM64 IDE since 17.4** (some auxiliary workloads still emulated) | native |
| uv | winget `astral-sh.uv` (native aarch64) | native |
| Miniconda3 | official **x86_64** Miniconda (runs under x64 emulation) — **no native arm64 installer exists** | emulated (WARN) |
| LM Studio | winget `ElementLabs.LMStudio` (native `-arm64.exe`) | native |
| Ollama | direct `ollama-windows-arm64.zip` from GitHub **latest** release (winget's `Ollama.Ollama` is x64-only); `ollama serve` is started and an **Ollama Serve** logon task is registered | native |
| CPU-Z | direct `download.cpuid.com/.../cpuz-arm64_1.05.zip` (native ARM64 portable) | native |
| HWMonitor | direct `download.cpuid.com/.../hwmonitor-arm64_1.05.zip` (native ARM64 portable) | native |
| CrystalDiskMark | winget `CrystalDewWorld.CrystalDiskMark` (universal installer → native arm64) | native |
| VLC | winget `VideoLAN.VLC` (native winarm64) | native |
| Notepad++ | winget `Notepad++.Notepad++` (native `.Installer.arm64.exe`) | native |
| PowerToys | winget `Microsoft.PowerToys` (native `-arm64.exe`) | native |
| Windows Terminal | winget `Microsoft.WindowsTerminal` (multi-arch MSIX) | native |

> **x64 hosts:** the x64 path installs exactly the same apps as `main`. This branch only changes install behavior on ARM64 hosts, so it can be merged into `main`.

### Caveats
- **Visual Studio 2022 is now a NATIVE ARM64 app** (since 17.4). On an ARM64 host the bootstrapper installs the native ARM64 IDE + build toolchain automatically (`--arch` is a layout-only option and is not passed). A few legacy/auxiliary workloads can still fall back to emulation; the auditor expects a native `devenv.exe` (PASS) and treats any residual emulated component as informational. The minimal `--add Microsoft.VisualStudio.Workload.CoreEditor` is installed; extend with extra `--add ...` flags (e.g. `Microsoft.VisualStudio.Workload.NativeDesktop`) if needed.
- **Miniconda3 has NO native Windows-ARM64 installer** (verified: `Miniconda3-latest-Windows-arm64.exe` is HTTP 404; repo.anaconda.com/miniconda ships only Windows x86/x64). It is installed as the official **x86_64** build under x64 emulation and is a documented **WARN**, never a FAIL. Prefer the system **ARM64 Python + uv/pip** for new environments. Re-check Anaconda before relying on a native arm64 build.
- **Chocolatey has no native ARM64 build** and runs under x64 emulation. On ARM it is bootstrapped (harmless) but **bypassed** for all app installs — this is the core of the arm64v2 design.
- **Ollama** is installed from GitHub releases as `ollama-windows-arm64.zip` (native ARM64). Do **not** use winget `Ollama.Ollama` on ARM — its manifest only ships an x64 `OllamaSetup.exe`.
- **Direct download URLs** (Python 3.12.0, VS bootstrapper, CPU-Z/HWMonitor zips) are **HEAD-validated** at install time and downloaded with retry + size validation. A 404 now **fails loudly** (reported) rather than being silently swallowed as a WARN. If cpuid bumps the zip version from `1.05`, update the pinned URL in `ReviewPC.Install.ps1` (the failure message will tell you the URL didn't resolve).
- **winget agreement prompts.** The ARM path passes `--accept-*` so installs stay silent; a source agreement may still be needed the first time winget runs.
- **`uv` arm64-Python note.** uv's binary is native aarch64, but uv's managed-Python fetch historically downloaded x86_64 Python on arm64 Windows ([astral-sh/uv#12906](https://github.com/astral-sh/uv/issues/12906)). Since Python 3.12 is installed natively ARM64, rely on the system interpreter or pin `UV_PYTHON_INSTALL_MIRROR` when using `uv python install`.

## Auditing the install
`Test-ReviewPCArm64v2.ps1` is the post-install ARM64 auditor. It is **wired into `ReviewPC.RunAll.ps1`** as the final step and can also be run standalone **as administrator on the target Windows-on-ARM machine** after bootstrap.

It reads the COFF/PE machine word of each primary executable:
- **PASS** = present AND PE machine `0xAA64` (ARM64), or a Windows Terminal MSIX reparse point (native multi-arch).
- **WARN** = present but emulated / no native ARM64 upstream (Miniconda3, Chocolatey) — never a failure.
- **FAIL** = missing, or expected-native but found x64/x86/ARMv7. **The script exits non-zero if any item FAILs.**

It uses the **same** catalog and arch detection as the installer (`Common.Utils.ps1`), so expectations can't drift.

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\Test-ReviewPCArm64v2.ps1            # Live (ARM64 host only)
.\Test-ReviewPCArm64v2.ps1 -Mode DryRun  # docs/path check — runs on ANY host incl. x64
```
