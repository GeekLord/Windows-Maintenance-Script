#requires -RunAsAdministrator
<#
.SYNOPSIS
    GeekLord Forge Maintenance - safety-first Windows maintenance automation.

.DESCRIPTION
    Runs a fixed sequence of Windows maintenance tasks with a System Restore point,
    full session logging, confirmation prompts for disruptive actions, per-step
    opt-outs, and accurate per-step status reporting.

    The script is self-contained and works both when run as a downloaded file and
    when launched via the hosted one-liner (irm ... | iex). It does not depend on
    $PSCmdlet / ShouldProcess, which are unavailable under Invoke-Expression.

.PARAMETER SkipWinget
    Skip upgrading installed applications with WinGet.

.PARAMETER SkipNetworkRefresh
    Skip releasing and renewing the IP configuration.

.PARAMETER SkipNetworkReset
    Skip flushing DNS and resetting Winsock and the IP stack.

.PARAMETER SkipSFC
    Skip the System File Checker scan.

.PARAMETER SkipDISM
    Skip the DISM image repair.

.PARAMETER SkipCheckDisk
    Skip scheduling Check Disk for the next reboot.

.PARAMETER SkipRestorePoint
    Skip creating a System Restore point before making changes.

.PARAMETER WhatIf
    Preview mode. Shows what each step would do without making any changes.

.PARAMETER Yes
    Answer every confirmation prompt automatically (for unattended/automated runs).

.PARAMETER LogDirectory
    Directory where the session transcript log is written.
    Defaults to C:\ProgramData\GeekLord\Logs.

.EXAMPLE
    .\forge-maintenance.ps1

.EXAMPLE
    .\forge-maintenance.ps1 -WhatIf

.EXAMPLE
    .\forge-maintenance.ps1 -SkipNetworkRefresh -SkipNetworkReset -SkipCheckDisk

.EXAMPLE
    irm https://geeklord.com/forge-maintenance.ps1 | iex
#>
param(
    [switch]$SkipWinget,
    [switch]$SkipNetworkRefresh,
    [switch]$SkipNetworkReset,
    [switch]$SkipSFC,
    [switch]$SkipDISM,
    [switch]$SkipCheckDisk,
    [switch]$SkipRestorePoint,
    [switch]$WhatIf,
    [switch]$Yes,
    [string]$LogDirectory = 'C:\ProgramData\GeekLord\Logs'
)

$ErrorActionPreference = 'Continue'

# ------------------------------------------------------------------
# Session state
# ------------------------------------------------------------------
$script:BrandName         = 'GeekLord Forge Maintenance'
$script:TranscriptStarted = $false
$script:StepResults       = New-Object System.Collections.Generic.List[object]
$script:SystemDrive       = $env:SystemDrive          # e.g. 'C:'
$script:TotalSteps        = 6
$script:StepIndex         = 1

$sessionStamp             = Get-Date -Format 'yyyyMMdd_HHmmss'
$script:LogFile           = Join-Path $LogDirectory ('forge-maintenance_{0}.log' -f $sessionStamp)

# ------------------------------------------------------------------
# Console helpers
# ------------------------------------------------------------------
function Write-Banner {
    param([string]$Title)
    Write-Host ''
    Write-Host ('=' * 60) -ForegroundColor DarkCyan
    Write-Host $Title -ForegroundColor Cyan
    Write-Host ('=' * 60) -ForegroundColor DarkCyan
}

function Write-Step {
    param([string]$Message)
    Write-Host ''
    Write-Host $Message -ForegroundColor Yellow
}

function Write-Info {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Gray
}

function Write-Ok {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Green
}

function Write-WarnLine {
    param([string]$Message)
    Write-Host $Message -ForegroundColor DarkYellow
}

function Write-ErrLine {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Red
}

# ------------------------------------------------------------------
# Result tracking
# ------------------------------------------------------------------
function Add-StepResult {
    param(
        [string]$Step,
        [string]$Status,
        [string]$Details
    )
    $script:StepResults.Add([pscustomobject]@{
        Time    = Get-Date -Format 'HH:mm:ss'
        Step    = $Step
        Status  = $Status
        Details = $Details
    })
}

# ------------------------------------------------------------------
# Environment / prerequisites
# ------------------------------------------------------------------
function Test-Administrator {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Initialize-Logging {
    try {
        if (-not (Test-Path -LiteralPath $LogDirectory)) {
            New-Item -Path $LogDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        Start-Transcript -Path $script:LogFile -Append -ErrorAction Stop | Out-Null
        $script:TranscriptStarted = $true
        Write-Info ('Transcript log: {0}' -f $script:LogFile)
    }
    catch {
        Write-WarnLine ('Could not start transcript logging: {0}' -f $_.Exception.Message)
    }
}

function Stop-Logging {
    if ($script:TranscriptStarted) {
        try { Stop-Transcript | Out-Null } catch { }
        $script:TranscriptStarted = $false
    }
}

# ------------------------------------------------------------------
# Confirmation (self-contained; works under a real console and iex).
# Returns $true to proceed, $false to skip.
# ------------------------------------------------------------------
function Get-Confirmation {
    param([string]$Question)

    if ($Yes)    { return $true }   # unattended / auto-approve
    if ($WhatIf) { return $false }  # preview never executes

    try {
        $yesChoice = New-Object System.Management.Automation.Host.ChoiceDescription '&Yes', 'Run this step.'
        $noChoice  = New-Object System.Management.Automation.Host.ChoiceDescription '&No', 'Skip this step.'
        $choices   = [System.Management.Automation.Host.ChoiceDescription[]]@($yesChoice, $noChoice)
        # Default choice index 1 (No) is the safer default.
        $decision  = $Host.UI.PromptForChoice('Confirm', $Question, $choices, 1)
        return ($decision -eq 0)
    }
    catch {
        Write-WarnLine 'No interactive console is available to confirm this action. Skipping. Use -Yes to auto-approve.'
        return $false
    }
}

# ------------------------------------------------------------------
# Restore point (uses cmdlets, so it has its own runner)
# ------------------------------------------------------------------
function New-SystemRestorePoint {
    Write-Step '[Prep] Create a System Restore point before making changes'

    if ($SkipRestorePoint) {
        Write-WarnLine 'Restore point skipped by parameter.'
        Add-StepResult -Step 'Restore Point' -Status 'Skipped' -Details 'Skipped by parameter.'
        return
    }
    if ($WhatIf) {
        Write-Info '[Preview] Would create a System Restore point.'
        Add-StepResult -Step 'Restore Point' -Status 'Preview' -Details 'WhatIf: no changes made.'
        return
    }
    if (-not (Get-Confirmation -Question 'Create a System Restore point before continuing?')) {
        Write-WarnLine 'Restore point skipped by user choice.'
        Add-StepResult -Step 'Restore Point' -Status 'Skipped' -Details 'Declined at confirmation prompt.'
        return
    }
    if (-not (Get-Command Checkpoint-Computer -ErrorAction SilentlyContinue)) {
        Write-WarnLine 'Checkpoint-Computer is not available on this system; skipping restore point.'
        Add-StepResult -Step 'Restore Point' -Status 'Warning' -Details 'Checkpoint-Computer not available.'
        return
    }

    try {
        try {
            Enable-ComputerRestore -Drive ('{0}\' -f $script:SystemDrive) -ErrorAction Stop
        }
        catch {
            Write-WarnLine ('Could not enable System Restore on {0}. {1}' -f $script:SystemDrive, $_.Exception.Message)
        }

        $rpName = 'GeekLord Forge Maintenance - {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm')
        Checkpoint-Computer -Description $rpName -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
        Write-Ok ('Restore point created: {0}' -f $rpName)
        Add-StepResult -Step 'Restore Point' -Status 'Success' -Details $rpName
    }
    catch {
        Write-WarnLine 'Restore point could not be created. Windows may have created one within the last 24 hours, or System Restore may be disabled.'
        Write-WarnLine $_.Exception.Message
        Add-StepResult -Step 'Restore Point' -Status 'Warning' -Details $_.Exception.Message
    }
}

# ------------------------------------------------------------------
# Generic step runner for the numbered maintenance tasks.
# Handles skip logic, preview mode, confirmation, execution, and
# native exit-code aware status reporting.
# ------------------------------------------------------------------
function Invoke-MaintenanceStep {
    param(
        [string]$Name,
        [string]$Description,
        [scriptblock]$Action,
        [switch]$RequiresConfirmation,
        [string]$ConfirmQuestion,
        [bool]$Skip,
        [string]$SkipReason = 'Skipped by parameter.'
    )

    Write-Step ('[STEP {0}/{1}] {2}' -f $script:StepIndex, $script:TotalSteps, $Description)
    $script:StepIndex++

    if ($Skip) {
        Write-WarnLine ('Skipped: {0}' -f $SkipReason)
        Add-StepResult -Step $Name -Status 'Skipped' -Details $SkipReason
        return
    }

    if ($WhatIf) {
        Write-Info ('[Preview] Would run: {0}' -f $Description)
        Add-StepResult -Step $Name -Status 'Preview' -Details 'WhatIf: no changes made.'
        return
    }

    if ($RequiresConfirmation) {
        $question = if ($ConfirmQuestion) { $ConfirmQuestion } else { ("Proceed with: {0}?" -f $Description) }
        if (-not (Get-Confirmation -Question $question)) {
            Write-WarnLine 'Skipped by user choice.'
            Add-StepResult -Step $Name -Status 'Skipped' -Details 'Declined at confirmation prompt.'
            return
        }
    }

    # Reset so we can tell whether a native command set a fresh exit code.
    $global:LASTEXITCODE = 0
    try {
        & $Action
        $exitCode = $LASTEXITCODE
        if ($exitCode -and $exitCode -ne 0) {
            Write-WarnLine ('{0} finished with exit code {1}.' -f $Name, $exitCode)
            Add-StepResult -Step $Name -Status 'Warning' -Details ('Completed with exit code {0}.' -f $exitCode)
        }
        else {
            Write-Ok ('{0} completed.' -f $Name)
            Add-StepResult -Step $Name -Status 'Success' -Details 'Completed.'
        }
    }
    catch {
        Write-ErrLine ('{0} failed: {1}' -f $Name, $_.Exception.Message)
        Add-StepResult -Step $Name -Status 'Error' -Details $_.Exception.Message
    }
}

# ------------------------------------------------------------------
# Main orchestration
# ------------------------------------------------------------------
function Invoke-Maintenance {
    Write-Banner $script:BrandName
    Write-Info 'Updates apps, refreshes networking, verifies Windows integrity, and can schedule a disk check.'
    Write-Info ('Transcript log: {0}' -f $script:LogFile)
    if ($WhatIf) { Write-Info 'PREVIEW MODE (-WhatIf): no changes will be made.' }
    if ($Yes)    { Write-Info 'AUTO-CONFIRM (-Yes): prompts will be answered automatically.' }

    # Session-level go / no-go gate (skipped in preview mode).
    if (-not $WhatIf) {
        if (-not (Get-Confirmation -Question 'Proceed with system maintenance tasks on this computer?')) {
            Write-WarnLine 'Operation cancelled by user.'
            Add-StepResult -Step 'Session' -Status 'Cancelled' -Details 'User cancelled before execution.'
            return
        }
    }

    New-SystemRestorePoint

    # Step 1 - WinGet upgrades (auto-skip if WinGet is not installed).
    $wingetAvailable = [bool](Get-Command winget -ErrorAction SilentlyContinue)
    $skipWinget      = $SkipWinget.IsPresent -or (-not $wingetAvailable)
    $wingetReason    = if ($SkipWinget) { 'Skipped by parameter.' }
                       elseif (-not $wingetAvailable) { 'WinGet is not available on this system.' }
                       else { 'Skipped by parameter.' }
    Invoke-MaintenanceStep -Name 'WinGet Upgrade' `
        -Description 'Upgrade installed applications with WinGet' `
        -Skip $skipWinget -SkipReason $wingetReason `
        -Action { winget upgrade --all --accept-source-agreements --accept-package-agreements }

    # Step 2 - Release / renew IP.
    Invoke-MaintenanceStep -Name 'IP Refresh' `
        -Description 'Release and renew IP configuration' `
        -Skip $SkipNetworkRefresh.IsPresent -RequiresConfirmation `
        -ConfirmQuestion 'This may briefly disconnect your network. Release and renew IP now?' `
        -Action { ipconfig /release; ipconfig /renew }

    # Step 3 - Flush DNS and reset the network stack.
    Invoke-MaintenanceStep -Name 'DNS and Network Reset' `
        -Description 'Flush DNS and reset Winsock/IP stack' `
        -Skip $SkipNetworkReset.IsPresent -RequiresConfirmation `
        -ConfirmQuestion 'Reset Winsock and the IP stack? A restart may be needed for full effect.' `
        -Action { ipconfig /flushdns; netsh winsock reset; netsh int ip reset }

    # Step 4 - System File Checker.
    Invoke-MaintenanceStep -Name 'SFC Scan' `
        -Description 'Run System File Checker (sfc /scannow)' `
        -Skip $SkipSFC.IsPresent `
        -Action { sfc /scannow }

    # Step 5 - DISM image repair.
    Invoke-MaintenanceStep -Name 'DISM RestoreHealth' `
        -Description 'Repair Windows image health with DISM' `
        -Skip $SkipDISM.IsPresent `
        -Action { DISM /Online /Cleanup-Image /RestoreHealth }

    # Step 6 - Schedule Check Disk for next reboot.
    Invoke-MaintenanceStep -Name 'Check Disk Schedule' `
        -Description 'Schedule Check Disk for next reboot' `
        -Skip $SkipCheckDisk.IsPresent -RequiresConfirmation `
        -ConfirmQuestion 'Schedule a disk check for the next reboot? This can significantly increase restart time.' `
        -Action { cmd /c ('echo Y|chkdsk {0} /r' -f $script:SystemDrive) }

    # Summary
    Write-Banner ('{0} Summary' -f $script:BrandName)
    $script:StepResults | Format-Table -AutoSize | Out-Host
    Write-Host ''
    if ($WhatIf) {
        Write-Info 'Preview complete. Re-run without -WhatIf to apply these changes.'
    }
    else {
        Write-Ok 'Maintenance session complete.'
        Write-Info 'If Check Disk was scheduled, restart the system to let it run.'
        Write-Info ('Review the transcript log for a full record: {0}' -f $script:LogFile)
    }

    Write-Host ''
    Write-Host 'Recommended hosted command:' -ForegroundColor Gray
    Write-Host 'irm https://geeklord.com/forge-maintenance.ps1 | iex' -ForegroundColor White
}

# ------------------------------------------------------------------
# Bootstrap
# ------------------------------------------------------------------
# Note: 'exit' and top-level 'return' are avoided here so the script is
# safe to run via 'irm ... | iex' (where they could terminate the host).
if (-not (Test-Administrator)) {
    Write-Host ''
    Write-Host 'ERROR: GeekLord Forge Maintenance must run in an elevated PowerShell window.' -ForegroundColor Red
    Write-Host 'Right-click PowerShell (or Windows Terminal) and choose "Run as administrator", then try again.' -ForegroundColor Red
}
else {
    Initialize-Logging
    try {
        Invoke-Maintenance
    }
    finally {
        Stop-Logging
    }
}
