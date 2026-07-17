---
inclusion: always
---

# GeekLord Forge Maintenance

Branded, safety-first Windows maintenance automation. The project wraps a fixed set of system-repair tasks so they can be shipped as a readable PowerShell one-liner (`irm https://geeklord.com/forge-maintenance.ps1 | iex`) instead of an opaque script.

## Files

- `forge-maintenance.ps1` — Primary, current implementation. New work goes here.
- `Computer Maintainance.bat` — Legacy batch version, kept for reference. The filename misspelling is pre-existing; do not rename it unless asked.
- `blog_post.html` — GeekLord blog post about the tool and the `irm | iex` pattern. It shows the launcher command and a step summary, not the full script.
- `.kiro/steering/` — Steering docs.

## Maintenance pipeline (canonical order)

Both scripts run the same six steps in this order; keep them in sync:

1. Upgrade apps with WinGet (`winget upgrade --all`)
2. Release/renew IP (`ipconfig /release`, `/renew`)
3. Flush DNS and reset Winsock + IP stack (`ipconfig /flushdns`, `netsh winsock reset`, `netsh int ip reset`)
4. System File Checker (`sfc /scannow`)
5. Repair image health (`DISM /Online /Cleanup-Image /RestoreHealth`)
6. Schedule Check Disk for next reboot (`chkdsk /r` against `$env:SystemDrive`)

## Safety-first principles (non-negotiable)

The PowerShell version exists to add the safety rails the batch file lacks. Preserve all of them:

- Require elevation: `#requires -RunAsAdministrator` blocks non-elevated *file* runs; a runtime `Test-Administrator` guard covers the `iex` path (where `#requires` is ignored).
- Create a System Restore point before making changes (`New-SystemRestorePoint`).
- Log the full session via `Start-Transcript` into `$LogDirectory` (default `C:\ProgramData\GeekLord\Logs`).
- Gate disruptive actions behind confirmation prompts (`Get-Confirmation`).
- Preview with `-WhatIf`; auto-approve for automation with `-Yes`.
- Offer a `-Skip<Step>` switch for every step.
- Never abort the session on a single step failure: catch, record, and continue.
- Do not add telemetry, extra network calls, or silent destructive actions.

## Must run under `irm ... | iex` (critical)

The script is distributed as a one-liner, so it must work when its text is piped to `Invoke-Expression`, not only when run as a `.ps1`. Under `iex` there is no cmdlet context:

- Do NOT use `$PSCmdlet`, `[CmdletBinding(SupportsShouldProcess)]`, `ShouldProcess`, or `ShouldContinue` — `$PSCmdlet` is `$null` under `iex` and any method call on it throws. Implement confirmation and preview yourself (`Get-Confirmation`, custom `-WhatIf`/`-Yes`).
- Do NOT rely on `#requires` for enforcement under `iex` (it is ignored); keep the runtime `Test-Administrator` check.
- Do NOT use `exit` or a top-level `return` for control flow — they can terminate the user's session. Put logic in functions and gate the bootstrap with `if/else`.
- Native tools do not throw on failure. After running one, check `$LASTEXITCODE` and map a non-zero result to a `Warning`/`Error` status instead of a false `Success`.

## PowerShell conventions

- `$ErrorActionPreference = 'Continue'`; rely on per-step try/catch, not a global stop.
- Approved Verb-Noun, PascalCase function names.
- Single-quoted strings unless interpolation is needed; suppress noise with `| Out-Null`.
- Hold session state in `$script:`-scoped variables (`$script:StepResults`, `$script:LogFile`, `$script:BrandName`, ...).
- Emit console output only through the `Write-*` helpers (`Write-Banner`, `Write-Step`, `Write-Info`, `Write-Ok`, `Write-WarnLine`); do not scatter raw colored `Write-Host` calls.
- Run every numbered maintenance action through `Invoke-MaintenanceStep`, which records the outcome with `Add-StepResult` (Time/Step/Status/Details) so the closing summary stays complete.
- Read error text from `$_.Exception.Message`.
- Wrap the main flow in `try { } finally { Stop-Logging }` so logging always closes.

## Per-step pattern

Numbered steps go through `Invoke-MaintenanceStep` with `-Name`, `-Description`, `-Action` (a scriptblock), optional `-RequiresConfirmation`/`-ConfirmQuestion`, and `-Skip`/`-SkipReason`. It resolves in this order: skip check → `-WhatIf` preview → `Get-Confirmation` (when required) → run the action → status from `$LASTEXITCODE` (0 = `Success`, non-zero = `Warning`, thrown = `Error`). Every non-executing path records a `Skipped`/`Preview`/`Cancelled` status with a reason.

## When changing the pipeline

- Add or remove the matching `-Skip<Step>` switch, add an `Invoke-MaintenanceStep` call, and update `$script:TotalSteps` (the `[STEP x/y]` counter advances automatically via `$script:StepIndex`).
- Mirror any pipeline change in `Computer Maintainance.bat`, and update the step summary in `blog_post.html` if the steps themselves change (the blog shows the launcher command and a step summary, not the full script).
- Keep the `GeekLord Forge Maintenance` brand and the hosted `irm ... | iex` one-liner consistent across all files.
