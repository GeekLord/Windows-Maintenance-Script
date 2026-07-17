---
inclusion: always
---

# GeekLord Forge Maintenance

Branded, safety-first Windows maintenance automation. The project wraps a fixed set of
system-repair tasks so they can be shipped as a readable PowerShell one-liner
(`irm https://geeklord.com/forge-maintenance.ps1 | iex`) instead of an opaque script.

## Files

- `forge-maintenance.ps1` — Primary, current implementation. New work goes here.
- `Computer Maintainance.bat` — Legacy batch version, kept for reference. The filename
  misspelling is pre-existing; do not rename it unless asked.
- `blog_post.html` — GeekLord blog post that embeds the full script inside a `<pre><code>` block.
- `.kiro/steering/` — Steering docs.

## Maintenance pipeline (canonical order)

Both scripts run the same six steps in this order; keep them in sync:

1. Upgrade apps with WinGet (`winget upgrade --all`)
2. Release/renew IP (`ipconfig /release`, `/renew`)
3. Flush DNS and reset Winsock + IP stack (`ipconfig /flushdns`, `netsh winsock reset`, `netsh int ip reset`)
4. System File Checker (`sfc /scannow`)
5. Repair image health (`DISM /Online /Cleanup-Image /RestoreHealth`)
6. Schedule Check Disk for next reboot (`chkdsk /r`)

## Safety-first principles (non-negotiable)

The PowerShell version exists to add the safety rails the batch file lacks. Preserve all of them:

- Require elevation: `#requires -RunAsAdministrator` plus the `Test-Administrator` guard (exit 1 if not elevated).
- Create a System Restore point before making changes (`New-RestorePointSafe`).
- Log the full session via `Start-Transcript` into `$LogDirectory` (default `C:\ProgramData\GeekLord\Logs`).
- Gate disruptive actions behind confirmation prompts (`Confirm-Action` → `$PSCmdlet.ShouldContinue`).
- Support `-WhatIf` on destructive operations via `SupportsShouldProcess` and `$PSCmdlet.ShouldProcess`.
- Offer a `-Skip<Step>` switch for every step.
- Never abort the session on a single step failure: catch, record, and continue.
- Do not add telemetry, extra network calls, or silent destructive actions.

## PowerShell conventions

- `$ErrorActionPreference = 'Continue'`; rely on per-step try/catch, not a global stop.
- Approved Verb-Noun, PascalCase function names.
- Single-quoted strings unless interpolation is needed; suppress noise with `| Out-Null`.
- Hold session state in `$script:`-scoped variables (`$script:StepResults`, `$script:LogFile`, `$script:BrandName`, ...).
- Emit console output only through the `Write-*` helpers (`Write-Banner`, `Write-Step`, `Write-Info`,
  `Write-Ok`, `Write-WarnLine`); do not scatter raw colored `Write-Host` calls.
- Run every maintenance action through `Invoke-SafeStep`, and record the outcome with `Add-StepResult`
  (Time/Step/Status/Details) so the closing summary table stays complete.
- Read error text from `$_.Exception.Message`.
- Wrap the main flow in `try { } finally { Stop-Logging }` so logging always closes.

## Per-step pattern

Each step follows: check `-Skip<Step>` → `if ($PSCmdlet.ShouldProcess(...))` → `Confirm-Action`
for disruptive steps → `Invoke-SafeStep`. Record a `Skipped` status with a reason on every path
that does not run (skip switch, declined prompt, or `-WhatIf`).

## When changing the pipeline

- Add or remove the matching `-Skip<Step>` switch and update `$totalSteps` and the `[STEP x/y]` counters.
- Mirror the change in `Computer Maintainance.bat` and in the `<pre><code>` copy inside `blog_post.html`
  (HTML-escape as needed, e.g. `&` becomes `&amp;`).
- Keep the `GeekLord Forge Maintenance` brand and the hosted `irm ... | iex` one-liner consistent across all files.
