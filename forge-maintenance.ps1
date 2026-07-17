#requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [switch]$SkipWinget,
    [switch]$SkipNetworkRefresh,
    [switch]$SkipNetworkReset,
    [switch]$SkipSFC,
    [switch]$SkipDISM,
    [switch]$SkipCheckDisk,
    [switch]$SkipRestorePoint,
    [string]$LogDirectory = 'C:\ProgramData\GeekLord\Logs'
)

$ErrorActionPreference = 'Continue'
$script:TranscriptStarted = $false
$script:StepResults = New-Object System.Collections.Generic.List[object]
$script:BrandName = 'GeekLord Forge Maintenance'
$script:SessionStamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$script:LogFile = Join-Path $LogDirectory "forge-maintenance_$script:SessionStamp.log"

function Write-Banner {
    param([string]$Title)
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor DarkCyan
    Write-Host $Title -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor DarkCyan
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

function Add-StepResult {
    param(
        [string]$Step,
        [string]$Status,
        [string]$Details
    )
    $script:StepResults.Add([pscustomobject]@{
        Time = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Step = $Step
        Status = $Status
        Details = $Details
    }) | Out-Null
}

function Test-Administrator {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Initialize-Logging {
    if (-not (Test-Path $LogDirectory)) {
        New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
    }
    try {
        Start-Transcript -Path $script:LogFile -Append -ErrorAction Stop | Out-Null
        $script:TranscriptStarted = $true
        Add-StepResult -Step 'Logging' -Status 'Started' -Details "Transcript started at $script:LogFile"
    }
    catch {
        Write-WarnLine "Could not start transcript logging: $($_.Exception.Message)"
        Add-StepResult -Step 'Logging' -Status 'Warning' -Details $_.Exception.Message
    }
}

function Stop-Logging {
    if ($script:TranscriptStarted) {
        try {
            Stop-Transcript | Out-Null
        }
        catch {
        }
    }
}

function Confirm-Action {
    param(
        [string]$Title,
        [string]$Message
    )
    return $PSCmdlet.ShouldContinue($Message, $Title)
}

function Ensure-SystemRestoreEnabled {
    try {
        Enable-ComputerRestore -Drive 'C:\' -ErrorAction Stop
        return $true
    }
    catch {
        Write-WarnLine "Could not enable System Restore on C:. $($_.Exception.Message)"
        return $false
    }
}

function New-RestorePointSafe {
    if ($SkipRestorePoint) {
        Add-StepResult -Step 'Restore Point' -Status 'Skipped' -Details 'Skipped by user request.'
        Write-WarnLine 'Restore point creation skipped by user request.'
        return
    }

    Write-Step '[Prep] Creating a restore point before maintenance changes...'
    if (-not (Confirm-Action -Title 'Create Restore Point' -Message 'Create a System Restore point before continuing?')) {
        Add-StepResult -Step 'Restore Point' -Status 'Skipped' -Details 'User declined restore point creation.'
        Write-WarnLine 'Restore point creation skipped by user choice.'
        return
    }

    try {
        Ensure-SystemRestoreEnabled | Out-Null
        $rpName = "GeekLord Forge Maintenance - $((Get-Date).ToString('yyyy-MM-dd HH:mm'))"
        Checkpoint-Computer -Description $rpName -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop | Out-Null
        Add-StepResult -Step 'Restore Point' -Status 'Success' -Details $rpName
        Write-Ok "Restore point created: $rpName"
    }
    catch {
        $msg = $_.Exception.Message
        Add-StepResult -Step 'Restore Point' -Status 'Warning' -Details $msg
        Write-WarnLine "Restore point could not be created. Windows may already have created one in the last 24 hours, or System Restore may be unavailable."
        Write-WarnLine $msg
    }
}

function Invoke-SafeStep {
    param(
        [string]$StepName,
        [scriptblock]$Action
    )
    try {
        & $Action
        Add-StepResult -Step $StepName -Status 'Success' -Details 'Completed.'
    }
    catch {
        Add-StepResult -Step $StepName -Status 'Error' -Details $_.Exception.Message
        Write-WarnLine "$StepName failed: $($_.Exception.Message)"
    }
}

if (-not (Test-Administrator)) {
    Write-Host 'ERROR: Please run this script in an elevated PowerShell window.' -ForegroundColor Red
    exit 1
}

Initialize-Logging

try {
    Write-Banner $script:BrandName
    Write-Info 'This GeekLord script updates apps, refreshes networking, checks Windows integrity, and can schedule a disk scan.'
    Write-Info "Transcript log: $script:LogFile"
    Write-Info 'Tip: You can preview supported changes with -WhatIf where applicable.'

    if (-not (Confirm-Action -Title $script:BrandName -Message 'Proceed with system maintenance tasks on this computer?')) {
        Add-StepResult -Step 'Session' -Status 'Cancelled' -Details 'User cancelled before execution.'
        Write-WarnLine 'Operation cancelled by user.'
        return
    }

    New-RestorePointSafe

    $step = 1
    $totalSteps = 6

    if (-not $SkipWinget) {
        Write-Step "[STEP $step/$totalSteps] Upgrade installed applications with WinGet"
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            if ($PSCmdlet.ShouldProcess('Installed applications', 'Upgrade all available packages with WinGet')) {
                Invoke-SafeStep -StepName 'WinGet Upgrade' -Action {
                    winget upgrade --all --accept-source-agreements --accept-package-agreements
                }
            } else {
                Add-StepResult -Step 'WinGet Upgrade' -Status 'Skipped' -Details 'User declined action.'
            }
        }
        else {
            Write-WarnLine 'WinGet is not available on this system. Skipping application upgrades.'
            Add-StepResult -Step 'WinGet Upgrade' -Status 'Skipped' -Details 'WinGet not available.'
        }
    }
    else {
        Add-StepResult -Step 'WinGet Upgrade' -Status 'Skipped' -Details 'Skipped by parameter.'
    }
    $step++

    if (-not $SkipNetworkRefresh) {
        Write-Step "[STEP $step/$totalSteps] Release and renew IP configuration"
        if ($PSCmdlet.ShouldProcess('Network adapters', 'Release and renew IP configuration')) {
            if (Confirm-Action -Title 'Network Refresh' -Message 'This may briefly disconnect your network. Continue with IP release/renew?') {
                Invoke-SafeStep -StepName 'IP Refresh' -Action {
                    ipconfig /release
                    ipconfig /renew
                }
            } else {
                Add-StepResult -Step 'IP Refresh' -Status 'Skipped' -Details 'User declined action.'
            }
        }
        else {
            Add-StepResult -Step 'IP Refresh' -Status 'Skipped' -Details 'WhatIf/ShouldProcess prevented execution.'
        }
    }
    else {
        Add-StepResult -Step 'IP Refresh' -Status 'Skipped' -Details 'Skipped by parameter.'
    }
    $step++

    if (-not $SkipNetworkReset) {
        Write-Step "[STEP $step/$totalSteps] Flush DNS and reset Winsock/IP stack"
        if ($PSCmdlet.ShouldProcess('Network stack', 'Flush DNS and reset Winsock/IP stack')) {
            if (Confirm-Action -Title 'Network Stack Reset' -Message 'Reset Winsock and IP stack? A restart may be needed for full effect.') {
                Invoke-SafeStep -StepName 'DNS and Network Reset' -Action {
                    ipconfig /flushdns
                    netsh winsock reset
                    netsh int ip reset
                }
            } else {
                Add-StepResult -Step 'DNS and Network Reset' -Status 'Skipped' -Details 'User declined action.'
            }
        }
        else {
            Add-StepResult -Step 'DNS and Network Reset' -Status 'Skipped' -Details 'WhatIf/ShouldProcess prevented execution.'
        }
    }
    else {
        Add-StepResult -Step 'DNS and Network Reset' -Status 'Skipped' -Details 'Skipped by parameter.'
    }
    $step++

    if (-not $SkipSFC) {
        Write-Step "[STEP $step/$totalSteps] Run System File Checker (SFC)"
        if ($PSCmdlet.ShouldProcess('Windows system files', 'Run sfc /scannow')) {
            Invoke-SafeStep -StepName 'SFC Scan' -Action {
                sfc /scannow
            }
        }
        else {
            Add-StepResult -Step 'SFC Scan' -Status 'Skipped' -Details 'WhatIf/ShouldProcess prevented execution.'
        }
    }
    else {
        Add-StepResult -Step 'SFC Scan' -Status 'Skipped' -Details 'Skipped by parameter.'
    }
    $step++

    if (-not $SkipDISM) {
        Write-Step "[STEP $step/$totalSteps] Repair Windows image health with DISM"
        if ($PSCmdlet.ShouldProcess('Windows image', 'Run DISM RestoreHealth')) {
            Invoke-SafeStep -StepName 'DISM RestoreHealth' -Action {
                DISM /Online /Cleanup-Image /RestoreHealth
            }
        }
        else {
            Add-StepResult -Step 'DISM RestoreHealth' -Status 'Skipped' -Details 'WhatIf/ShouldProcess prevented execution.'
        }
    }
    else {
        Add-StepResult -Step 'DISM RestoreHealth' -Status 'Skipped' -Details 'Skipped by parameter.'
    }
    $step++

    if (-not $SkipCheckDisk) {
        Write-Step "[STEP $step/$totalSteps] Schedule Check Disk for next reboot"
        if ($PSCmdlet.ShouldProcess('System drive', 'Schedule chkdsk /r at next reboot')) {
            if (Confirm-Action -Title 'Schedule Check Disk' -Message 'Schedule a disk check for the next reboot? This can significantly increase restart time.') {
                Invoke-SafeStep -StepName 'Check Disk Schedule' -Action {
                    cmd /c "echo Y|chkdsk /r"
                }
            } else {
                Add-StepResult -Step 'Check Disk Schedule' -Status 'Skipped' -Details 'User declined action.'
            }
        }
        else {
            Add-StepResult -Step 'Check Disk Schedule' -Status 'Skipped' -Details 'WhatIf/ShouldProcess prevented execution.'
        }
    }
    else {
        Add-StepResult -Step 'Check Disk Schedule' -Status 'Skipped' -Details 'Skipped by parameter.'
    }

    Write-Banner 'GeekLord Forge Maintenance Summary'
    $script:StepResults | Format-Table -AutoSize
    Write-Host ''
    Write-Ok 'Maintenance session complete.'
    Write-Info 'If Check Disk was scheduled, restart the system to let it run.'
    Write-Info 'Review the transcript log for a complete record of commands and output.'
    Write-Host ''
    Write-Host 'Recommended hosted command:' -ForegroundColor Gray
    Write-Host 'irm https://geeklord.com/forge-maintenance.ps1 | iex' -ForegroundColor White
}
finally {
    Stop-Logging
}
