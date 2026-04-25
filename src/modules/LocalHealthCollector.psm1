<#
LocalHealthCollector module.

Planned purpose:
Collect read-only OS health signals from the local Windows server, including
CPU, memory, uptime, critical services, event logs, and pending reboot indicators.
#>

$moduleImports = @(
    'HealthEvaluator.psm1',
    'StorageHealthCollector.psm1',
    'NetworkHealthCollector.psm1',
    'EventLogRiskAnalyzer.psm1'
)

foreach ($moduleImport in $moduleImports) {
    $modulePath = Join-Path $PSScriptRoot $moduleImport
    if (Test-Path -LiteralPath $modulePath -PathType Leaf) {
        Import-Module $modulePath -Force
    }
}

function Get-HighestHealthStatus {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object[]]$Statuses
    )

    $statusList = @($Statuses | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($statusList -contains 'Red') {
        return 'Red'
    }

    if ($statusList -contains 'Yellow') {
        return 'Yellow'
    }

    if ($statusList -contains 'Unknown') {
        return 'Unknown'
    }

    return 'Green'
}

function Get-LocalCpuHealth {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Thresholds
    )

    $targetName = $env:COMPUTERNAME

    try {
        $processor = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_Processor -Filter "Name = '_Total'" -ErrorAction Stop
        $cpuUsagePercent = [math]::Round([double]$processor.PercentProcessorTime, 2)
        $status = Get-BasicHealthStatus `
            -Value $cpuUsagePercent `
            -WarningThreshold $Thresholds.cpu.warningPercent `
            -CriticalThreshold $Thresholds.cpu.criticalPercent `
            -ComparisonType GreaterThan

        $message = switch ($status) {
            'Green' { 'CPU usage is within threshold.' }
            'Yellow' { 'CPU usage is above warning threshold.' }
            'Red' { 'CPU usage is above critical threshold.' }
            default { 'CPU usage status could not be evaluated.' }
        }

        [pscustomobject]@{
            Category   = 'OS'
            CheckName  = 'CPU Usage'
            TargetName = $targetName
            Value      = $cpuUsagePercent
            Unit       = 'Percent'
            Status     = $status
            Message    = $message
            Evidence   = 'Win32_PerfFormattedData_PerfOS_Processor.PercentProcessorTime'
        }
    }
    catch {
        [pscustomobject]@{
            Category   = 'OS'
            CheckName  = 'CPU Usage'
            TargetName = $targetName
            Value      = $null
            Unit       = 'Percent'
            Status     = 'Unknown'
            Message    = "Unable to read local CPU health: $($_.Exception.Message)"
            Evidence   = 'Win32_PerfFormattedData_PerfOS_Processor.PercentProcessorTime'
        }
    }
}

function Get-LocalMemoryHealth {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Thresholds
    )

    $targetName = $env:COMPUTERNAME

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $totalGb = [math]::Round(([double]$os.TotalVisibleMemorySize / 1MB), 2)
        $freeGb = [math]::Round(([double]$os.FreePhysicalMemory / 1MB), 2)
        $usedPercent = if ($os.TotalVisibleMemorySize -gt 0) {
            [math]::Round(((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100), 2)
        }
        else {
            $null
        }

        $status = Get-BasicHealthStatus `
            -Value $usedPercent `
            -WarningThreshold $Thresholds.memory.warningPercent `
            -CriticalThreshold $Thresholds.memory.criticalPercent `
            -ComparisonType GreaterThan

        $message = switch ($status) {
            'Green' { 'Memory usage is within threshold.' }
            'Yellow' { 'Memory usage is above warning threshold.' }
            'Red' { 'Memory usage is above critical threshold.' }
            default { 'Memory usage status could not be evaluated.' }
        }

        [pscustomobject]@{
            Category   = 'OS'
            CheckName  = 'Memory Usage'
            TargetName = $targetName
            Value      = $usedPercent
            Unit       = 'Percent'
            Status     = $status
            Message    = $message
            Evidence   = [pscustomobject]@{
                TotalGB = $totalGb
                FreeGB  = $freeGb
            }
        }
    }
    catch {
        [pscustomobject]@{
            Category   = 'OS'
            CheckName  = 'Memory Usage'
            TargetName = $targetName
            Value      = $null
            Unit       = 'Percent'
            Status     = 'Unknown'
            Message    = "Unable to read local memory health: $($_.Exception.Message)"
            Evidence   = 'Win32_OperatingSystem.TotalVisibleMemorySize/FreePhysicalMemory'
        }
    }
}

function Get-LocalUptimeHealth {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Thresholds
    )

    $targetName = $env:COMPUTERNAME

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $lastBootTime = $os.LastBootUpTime
        $uptimeDays = [math]::Round(((Get-Date) - $lastBootTime).TotalDays, 2)
        $status = Get-BasicHealthStatus `
            -Value $uptimeDays `
            -WarningThreshold $Thresholds.uptime.warningDays `
            -CriticalThreshold ([double]::MaxValue) `
            -ComparisonType GreaterThan

        [pscustomobject]@{
            Category   = 'OS'
            CheckName  = 'Uptime'
            TargetName = $targetName
            Value      = $uptimeDays
            Unit       = 'Days'
            Status     = $status
            Message    = if ($status -eq 'Yellow') { 'Uptime is above warning threshold.' } else { 'Uptime is within threshold.' }
            Evidence   = [pscustomobject]@{
                LastBootTime = $lastBootTime
            }
        }
    }
    catch {
        [pscustomobject]@{
            Category   = 'OS'
            CheckName  = 'Uptime'
            TargetName = $targetName
            Value      = $null
            Unit       = 'Days'
            Status     = 'Unknown'
            Message    = "Unable to read local uptime health: $($_.Exception.Message)"
            Evidence   = 'Win32_OperatingSystem.LastBootUpTime'
        }
    }
}

function Get-LocalCriticalServiceHealth {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$ServiceNames
    )

    $targetName = $env:COMPUTERNAME

    foreach ($serviceName in $ServiceNames) {
        try {
            $service = Get-Service -Name $serviceName -ErrorAction Stop
            $status = if ($service.Status -eq 'Running') { 'Green' } else { 'Red' }
            $message = if ($status -eq 'Green') {
                "Critical service '$serviceName' is running."
            }
            else {
                "Critical service '$serviceName' is $($service.Status)."
            }

            [pscustomobject]@{
                Category   = 'OS'
                CheckName  = 'Critical Service'
                TargetName = $targetName
                Value      = $service.Status
                Unit       = 'ServiceStatus'
                Status     = $status
                Message    = $message
                Evidence   = [pscustomobject]@{
                    ServiceName = $service.Name
                    DisplayName = $service.DisplayName
                }
            }
        }
        catch {
            [pscustomobject]@{
                Category   = 'OS'
                CheckName  = 'Critical Service'
                TargetName = $targetName
                Value      = 'NotFound'
                Unit       = 'ServiceStatus'
                Status     = 'Unknown'
                Message    = "Critical service '$serviceName' was not found."
                Evidence   = [pscustomobject]@{
                    ServiceName = $serviceName
                }
            }
        }
    }
}

function Get-LocalPendingRebootStatus {
    [CmdletBinding()]
    param()

    $reasons = [System.Collections.Generic.List[string]]::new()

    try {
        if (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
            $reasons.Add('Component Based Servicing reboot pending')
        }

        if (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
            $reasons.Add('Windows Update reboot required')
        }

        $sessionManagerPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
        $sessionManager = Get-ItemProperty -LiteralPath $sessionManagerPath -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
        if ($sessionManager.PendingFileRenameOperations) {
            $reasons.Add('Pending file rename operations')
        }

        $isPendingReboot = $reasons.Count -gt 0
        [pscustomobject]@{
            IsPendingReboot = $isPendingReboot
            Reasons         = @($reasons)
            Status          = if ($isPendingReboot) { 'Yellow' } else { 'Green' }
            Message         = if ($isPendingReboot) { 'Pending reboot indicators were found.' } else { 'No common pending reboot indicators were found.' }
        }
    }
    catch {
        [pscustomobject]@{
            IsPendingReboot = $null
            Reasons         = @()
            Status          = 'Unknown'
            Message         = "Unable to read pending reboot indicators: $($_.Exception.Message)"
        }
    }
}

function Invoke-LocalHealthCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Thresholds,

        [AllowNull()]
        [object]$PredictiveRules
    )

    $targetName = $env:COMPUTERNAME
    $cpuHealth = Get-LocalCpuHealth -Thresholds $Thresholds
    $memoryHealth = Get-LocalMemoryHealth -Thresholds $Thresholds
    $uptimeHealth = Get-LocalUptimeHealth -Thresholds $Thresholds
    $serviceNames = @($Thresholds.services.defaultCriticalServices)
    $serviceHealth = @(Get-LocalCriticalServiceHealth -ServiceNames $serviceNames)
    $storageHealth = Invoke-LocalStorageHealthCheck -Thresholds $Thresholds
    $networkHealth = Invoke-LocalNetworkHealthCheck -Thresholds $Thresholds
    $eventLogRisk = @(Get-LocalEventLogRisk -Thresholds $Thresholds)
    $pendingReboot = Get-LocalPendingRebootStatus

    $allStatuses = @(
        $cpuHealth.Status
        $memoryHealth.Status
        $uptimeHealth.Status
        $serviceHealth.Status
        $storageHealth.LogicalDisks.Status
        $storageHealth.PhysicalDisks.Status
        $networkHealth.Adapters.StatusEvaluation
        $eventLogRisk.Status
        $pendingReboot.Status
    )

    [pscustomobject]@{
        TargetName    = $targetName
        TargetType    = 'Local'
        Timestamp     = Get-Date
        OsHealth      = [pscustomobject]@{
            Cpu              = $cpuHealth
            Memory           = $memoryHealth
            Uptime           = $uptimeHealth
            CriticalServices = $serviceHealth
        }
        StorageHealth = $storageHealth
        NetworkHealth = $networkHealth
        EventLogRisk  = $eventLogRisk
        PendingReboot = $pendingReboot
        Summary       = [pscustomobject]@{
            OverallStatus              = Get-HighestHealthStatus -Statuses $allStatuses
            LogicalDiskCount           = @($storageHealth.LogicalDisks).Count
            PhysicalDiskCount          = @($storageHealth.PhysicalDisks | Where-Object { $_.FriendlyName }).Count
            NetworkAdapterCount        = @($networkHealth.Adapters | Where-Object { $_.Name }).Count
            EventLogRiskIndicatorCount = @($eventLogRisk | Where-Object { $_.Status -ne 'Unknown' }).Count
            PredictiveRuleGroupsLoaded = @($PredictiveRules.rules.PSObject.Properties.Name).Count
        }
    }
}

Export-ModuleMember -Function @(
    'Get-LocalCpuHealth',
    'Get-LocalMemoryHealth',
    'Get-LocalUptimeHealth',
    'Get-LocalCriticalServiceHealth',
    'Get-LocalPendingRebootStatus',
    'Invoke-LocalHealthCheck'
)
