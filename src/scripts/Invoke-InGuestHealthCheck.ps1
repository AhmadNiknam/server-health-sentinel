<#
.SYNOPSIS
    Collects read-only in-guest health signals for an Azure Windows VM.

.DESCRIPTION
    This script is intended to run through Azure VM Run Command. It is
    self-contained, emits compressed JSON, and does not remediate or change
    system configuration.
#>

[CmdletBinding()]
param()

function Get-SafeCimInstance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ClassName,

        [string]$Filter
    )

    try {
        $parameters = @{
            ClassName   = $ClassName
            ErrorAction = 'Stop'
        }

        if (-not [string]::IsNullOrWhiteSpace($Filter)) {
            $parameters.Filter = $Filter
        }

        Get-CimInstance @parameters
    }
    catch {
        $null
    }
}

function Test-RegistryKeyExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    try {
        Test-Path -LiteralPath $Path -ErrorAction Stop
    }
    catch {
        $false
    }
}

$timestamp = Get-Date
$computerName = $env:COMPUTERNAME

$cpuSample = Get-SafeCimInstance -ClassName 'Win32_PerfFormattedData_PerfOS_Processor' -Filter "Name = '_Total'"
$cpuUsagePercent = if ($null -ne $cpuSample) { [math]::Round([double]$cpuSample.PercentProcessorTime, 2) } else { $null }

$os = Get-SafeCimInstance -ClassName 'Win32_OperatingSystem'
$memory = if ($null -ne $os -and $os.TotalVisibleMemorySize -gt 0) {
    $totalGb = [math]::Round(([double]$os.TotalVisibleMemorySize / 1MB), 2)
    $freeGb = [math]::Round(([double]$os.FreePhysicalMemory / 1MB), 2)
    [pscustomobject]@{
        TotalGB     = $totalGb
        FreeGB      = $freeGb
        UsedPercent = [math]::Round(((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100), 2)
    }
}
else {
    [pscustomobject]@{
        TotalGB     = $null
        FreeGB      = $null
        UsedPercent = $null
    }
}

$uptime = if ($null -ne $os -and $os.LastBootUpTime) {
    [pscustomobject]@{
        LastBootTime = $os.LastBootUpTime
        UptimeDays   = [math]::Round(($timestamp - $os.LastBootUpTime).TotalDays, 2)
    }
}
else {
    [pscustomobject]@{
        LastBootTime = $null
        UptimeDays   = $null
    }
}

$logicalDisks = @(Get-SafeCimInstance -ClassName 'Win32_LogicalDisk' -Filter 'DriveType = 3' | ForEach-Object {
        $freePercent = if ($_.Size -gt 0) { [math]::Round((($_.FreeSpace / $_.Size) * 100), 2) } else { $null }
        [pscustomobject]@{
            DriveLetter = [string]$_.DeviceID
            VolumeName  = [string]$_.VolumeName
            TotalGB     = if ($_.Size) { [math]::Round(($_.Size / 1GB), 2) } else { $null }
            FreeGB      = if ($_.FreeSpace) { [math]::Round(($_.FreeSpace / 1GB), 2) } else { $null }
            FreePercent = $freePercent
        }
    })

$criticalServiceNames = @('WinRM', 'EventLog')
$criticalServices = foreach ($serviceName in $criticalServiceNames) {
    try {
        $service = Get-Service -Name $serviceName -ErrorAction Stop
        [pscustomobject]@{
            ServiceName = $service.Name
            DisplayName = $service.DisplayName
            Status      = [string]$service.Status
            StartType   = [string]$service.StartType
        }
    }
    catch {
        [pscustomobject]@{
            ServiceName = $serviceName
            DisplayName = $null
            Status      = 'Unknown'
            StartType   = $null
            Message     = $_.Exception.Message
        }
    }
}

$pendingRebootReasons = [System.Collections.Generic.List[string]]::new()
if (Test-RegistryKeyExists -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
    $pendingRebootReasons.Add('Component Based Servicing reboot pending')
}
if (Test-RegistryKeyExists -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
    $pendingRebootReasons.Add('Windows Update reboot required')
}
try {
    $pendingFileRename = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'PendingFileRenameOperations' -ErrorAction Stop
    if (@($pendingFileRename.PendingFileRenameOperations).Count -gt 0) {
        $pendingRebootReasons.Add('Pending file rename operations')
    }
}
catch {
    $null = $_
}

$lookbackStart = $timestamp.AddHours(-24)
$eventCounts = foreach ($logName in @('System', 'Application')) {
    try {
        $events = @(Get-WinEvent -FilterHashtable @{ LogName = $logName; Level = @(1, 2); StartTime = $lookbackStart } -MaxEvents 200 -ErrorAction Stop)
        [pscustomobject]@{
            LogName = $logName
            ErrorOrCriticalCount = $events.Count
        }
    }
    catch {
        [pscustomobject]@{
            LogName = $logName
            ErrorOrCriticalCount = $null
            Message = $_.Exception.Message
        }
    }
}

$result = [pscustomobject]@{
    ComputerName      = $computerName
    Timestamp         = $timestamp
    Cpu               = [pscustomobject]@{
        UsagePercent = $cpuUsagePercent
    }
    Memory            = $memory
    LogicalDisks      = @($logicalDisks)
    Uptime            = $uptime
    CriticalServices  = @($criticalServices)
    PendingReboot     = [pscustomobject]@{
        IsPendingReboot = $pendingRebootReasons.Count -gt 0
        Reasons         = @($pendingRebootReasons)
    }
    RecentEventCounts = @($eventCounts)
}

$result | ConvertTo-Json -Depth 8 -Compress
