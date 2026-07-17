# GeekLord Forge Maintenance

Branded, safety-first Windows maintenance automation. Forge Maintenance bundles a proven set of Windows repair and upkeep tasks into a single PowerShell script that is transparent, auditable, and careful about the changes it makes to your system.

It is the modern, safer successor to a plain batch file: same core maintenance jobs, but with a System Restore point, full session logging, confirmation prompts, and per-step opt-outs so nothing disruptive runs silently.

## Table of contents

- [Overview](#overview)
- [Features](#features)
- [What it does](#what-it-does)
- [Safety features](#safety-features)
- [Requirements](#requirements)
- [Getting started](#getting-started)
- [Usage](#usage)
- [Parameters](#parameters)
- [Examples](#examples)
- [Logging and reporting](#logging-and-reporting)
- [Legacy batch script](#legacy-batch-script)
- [Project structure](#project-structure)
- [Responsible use and security](#responsible-use-and-security)
- [Troubleshooting](#troubleshooting)
- [Disclaimer](#disclaimer)
- [Author](#author)

## Overview

`forge-maintenance.ps1` runs a fixed, well-understood sequence of Windows maintenance
tasks: it updates installed applications, refreshes networking, verifies and repairs
core Windows components, and can schedule a disk check for the next reboot.

The design goal is to make a "maintenance one-liner" that is safe to publish and easy to
audit. Every action is optional, disruptive steps ask before they run, the whole session
is written to a transcript log, and a restore point is created up front when possible.

## Features

- One elevated script that performs six common maintenance tasks in a sensible order.
- System Restore point created before any changes (when System Restore is available).
- Full session transcript logging to a configurable directory.
- Confirmation prompts for disruptive actions (networking resets, disk check scheduling).
- `-WhatIf` support to preview what would run without changing anything.
- `-Yes` to auto-approve every prompt for unattended or automated runs.
- A `-Skip<Step>` switch for every task, so you can run only what you need.
- Runs correctly both as a downloaded file and via the `irm ... | iex` one-liner.
- Continues on error: a failed step is recorded but does not abort the session.
- A clear end-of-run summary table showing the status of every step.

## What it does

The script runs these steps in order. A System Restore point is attempted first, before
step 1.

| # | Step | Underlying commands | Notes |
|---|------|---------------------|-------|
| 1 | Upgrade applications | `winget upgrade --all --accept-source-agreements --accept-package-agreements` | Skipped automatically if WinGet is not installed. |
| 2 | Refresh IP configuration | `ipconfig /release`, `ipconfig /renew` | Can briefly disconnect the network. Prompts before running. |
| 3 | Reset DNS and network stack | `ipconfig /flushdns`, `netsh winsock reset`, `netsh int ip reset` | A restart may be needed for full effect. Prompts before running. |
| 4 | System File Checker | `sfc /scannow` | Scans and repairs protected system files. |
| 5 | Repair Windows image | `DISM /Online /Cleanup-Image /RestoreHealth` | Repairs the component store the SFC relies on. |
| 6 | Schedule Check Disk | `chkdsk <system drive> /r` | Targets the actual system drive (usually `C:`). Scheduled for the next reboot. Can significantly increase restart time. Prompts before running. |

## Safety features

Forge Maintenance exists to add the guardrails a raw batch file lacks:

- **Requires elevation.** The script declares `#requires -RunAsAdministrator` (which
  blocks non-elevated file runs) and also verifies elevation at runtime, so it refuses to
  run with a clear message even when launched via `irm ... | iex`.
- **Restore point first.** A `MODIFY_SETTINGS` restore point named
  `GeekLord Forge Maintenance - <timestamp>` is created before maintenance changes.
  Windows only allows one restore point per 24 hours by default, so this may be skipped
  by the OS.
- **Transcript logging.** The entire session (commands and output) is captured with
  `Start-Transcript` and saved to a timestamped log file.
- **Confirmation prompts.** Disruptive steps ask for confirmation before running.
- **Preview mode.** `-WhatIf` shows exactly what each step would do without making any
  changes. Use `-Yes` to auto-approve prompts for unattended runs.
- **Selective execution.** Every step has a `-Skip<Step>` switch.
- **Accurate status.** Native tools (WinGet, `netsh`, `sfc`, DISM, `chkdsk`) are checked
  by exit code, so a step that fails is reported as `Warning`/`Error` rather than a false
  `Success`.
- **Fault tolerant.** Each step is wrapped in error handling; a failure is logged and the
  run continues to the next step.

## Requirements

- Windows 10 or Windows 11 (client or the equivalent Windows Server release).
- Windows PowerShell 5.1 or PowerShell 7 or later.
- Administrator privileges (an elevated terminal).
- Optional: [WinGet](https://learn.microsoft.com/windows/package-manager/winget/)
  (the App Installer) for step 1. If it is not present, application upgrades are skipped.
- An internet connection for application upgrades.

## Getting started

### Option 1: Download and inspect first (recommended)

1. Download `forge-maintenance.ps1` into a folder.
2. Read through it so you know exactly what it will do.
3. Open PowerShell **as Administrator** in that folder.
4. If the file was downloaded from the internet, clear the block flag and allow the script
   to run for this session only:

   ```powershell
   Unblock-File .\forge-maintenance.ps1
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
   ```

5. Run it:

   ```powershell
   .\forge-maintenance.ps1
   ```

### Option 2: Hosted one-liner

If the script is hosted (for example on the GeekLord domain), it can be launched directly
in an elevated PowerShell window:

```powershell
irm https://geeklord.com/forge-maintenance.ps1 | iex
```

This fetches the script and runs it in the current session. Launched this way it runs
interactively and prompts before each disruptive step, using its built-in defaults
(parameters and `-Skip*` switches can only be passed when you run the downloaded file).
Only use this pattern with a source you trust and, ideally, after reading the script at
least once. See [Responsible use and security](#responsible-use-and-security).

## Usage

Run without arguments for the full guided maintenance session:

```powershell
.\forge-maintenance.ps1
```

Preview everything without making any changes:

```powershell
.\forge-maintenance.ps1 -WhatIf
```

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-SkipWinget` | switch | off | Skip upgrading applications with WinGet. |
| `-SkipNetworkRefresh` | switch | off | Skip releasing and renewing the IP configuration. |
| `-SkipNetworkReset` | switch | off | Skip flushing DNS and resetting Winsock and the IP stack. |
| `-SkipSFC` | switch | off | Skip the System File Checker scan. |
| `-SkipDISM` | switch | off | Skip the DISM image repair. |
| `-SkipCheckDisk` | switch | off | Skip scheduling Check Disk. |
| `-SkipRestorePoint` | switch | off | Skip creating a System Restore point. |
| `-LogDirectory` | string | `C:\ProgramData\GeekLord\Logs` | Directory where transcript logs are written. |
| `-WhatIf` | switch | off | Preview every step without making any changes. |
| `-Yes` | switch | off | Answer every confirmation prompt automatically (unattended/automated runs). |

## Examples

Run the full maintenance session:

```powershell
.\forge-maintenance.ps1
```

Update apps and repair Windows, but leave networking and the disk check alone:

```powershell
.\forge-maintenance.ps1 -SkipNetworkRefresh -SkipNetworkReset -SkipCheckDisk
```

Repair-only pass (skip app updates, networking, and disk scheduling):

```powershell
.\forge-maintenance.ps1 -SkipWinget -SkipNetworkRefresh -SkipNetworkReset -SkipCheckDisk
```

Run without creating a restore point and write logs to a custom folder:

```powershell
.\forge-maintenance.ps1 -SkipRestorePoint -LogDirectory 'D:\MaintenanceLogs'
```

Preview the whole run without changing anything:

```powershell
.\forge-maintenance.ps1 -WhatIf
```

Run unattended, auto-approving every prompt:

```powershell
.\forge-maintenance.ps1 -Yes
```

## Logging and reporting

- Each run writes a transcript to `<LogDirectory>\forge-maintenance_<yyyyMMdd_HHmmss>.log`.
- The default log directory is `C:\ProgramData\GeekLord\Logs`; override it with
  `-LogDirectory`.
- At the end of the session the script prints a summary table listing every step with its
  timestamp, status (`Success`, `Skipped`, `Warning`, `Error`, `Preview`, or `Cancelled`),
  and details.
- Review the transcript for a complete record of the commands that ran and their output.

## Legacy batch script

`Computer Maintainance.bat` is the original batch version that inspired this project. It
performs the same six maintenance tasks but without restore points, logging, confirmation
prompts, or selective execution. It is kept for reference and comparison; the PowerShell
script is the recommended way to run maintenance.

## Project structure

```
Windows Maintenance Script/
├── forge-maintenance.ps1      # Primary, current PowerShell implementation
├── Computer Maintainance.bat  # Legacy batch version (reference only)
├── blog_post.html             # GeekLord article explaining the tool and irm | iex
└── README.md                  # This file
```

## Responsible use and security

This tool is designed around the idea that convenience should not come at the cost of
transparency. A few habits worth keeping, whether you use this script or any other remote
PowerShell:

- Prefer to download and read a script before running it, especially in elevated sessions.
- Only use `irm ... | iex` with sources you trust, served over HTTPS from a domain you
  recognize.
- Keep source readable rather than obfuscated so it can be audited.
- Build safety into the script itself. Forge Maintenance does this with restore points,
  logging, and confirmation prompts.

The accompanying `blog_post.html` goes deeper on how `irm | iex` works, why the pattern is
popular, and how to weigh its risks.

## Troubleshooting

- **"must run in an elevated PowerShell window"** (or a `ScriptRequiresElevation` error).
  Start PowerShell with *Run as administrator* and try again.
- **The script will not run / execution policy error.** Unblock the file and allow it for
  the current session:

  ```powershell
  Unblock-File .\forge-maintenance.ps1
  Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
  ```

- **WinGet step is skipped.** WinGet (App Installer) is not installed or not on `PATH`.
  Install it from the Microsoft Store, or use `-SkipWinget` to silence the notice.
- **Restore point was not created.** Windows creates at most one restore point per 24
  hours by default, and System Restore must be enabled on the system drive. This is
  recorded as a warning and does not stop the run.
- **Check Disk did not run.** `chkdsk /r` is scheduled for the next reboot; restart the
  computer to let it complete. Expect a longer-than-usual startup while it runs.

## Disclaimer

This script performs system-level maintenance, including networking resets, Windows
component repair, and scheduling a full disk check. Review it before running, ensure you
have current backups, and use it at your own risk. The author is not responsible for any
loss or damage resulting from its use.

## Author

Created by **Shobhit** for **GeekLord**.
