<#
HealthEvaluator module.

Planned purpose:
Evaluate collector output against thresholds and produce normalized health
states for reports.
#>

function Get-BasicHealthStatus {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value,

        [AllowNull()]
        [object]$WarningThreshold,

        [AllowNull()]
        [object]$CriticalThreshold,

        [Parameter(Mandatory)]
        [ValidateSet('GreaterThan', 'LessThan')]
        [string]$ComparisonType
    )

    if ($null -eq $Value -or $null -eq $WarningThreshold -or $null -eq $CriticalThreshold) {
        return 'Unknown'
    }

    try {
        $numericValue = [double]$Value
        $numericWarning = [double]$WarningThreshold
        $numericCritical = [double]$CriticalThreshold
    }
    catch {
        return 'Unknown'
    }

    switch ($ComparisonType) {
        'GreaterThan' {
            if ($numericValue -ge $numericCritical) {
                return 'Red'
            }

            if ($numericValue -ge $numericWarning) {
                return 'Yellow'
            }

            return 'Green'
        }
        'LessThan' {
            if ($numericValue -le $numericCritical) {
                return 'Red'
            }

            if ($numericValue -le $numericWarning) {
                return 'Yellow'
            }

            return 'Green'
        }
    }
}

function Get-DefaultSeverity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Green', 'Yellow', 'Red', 'Unknown')]
        [string]$Status
    )

    switch ($Status) {
        'Green' { 'Informational' }
        'Yellow' { 'Medium' }
        'Red' { 'High' }
        default { 'Unknown' }
    }
}

function ConvertTo-EvidenceText {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Evidence
    )

    if ($null -eq $Evidence) {
        return $null
    }

    if ($Evidence -is [string]) {
        return $Evidence
    }

    try {
        return ($Evidence | ConvertTo-Json -Depth 6 -Compress)
    }
    catch {
        return [string]$Evidence
    }
}

function New-HealthFinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TargetName,

        [Parameter(Mandatory)]
        [string]$TargetType,

        [Parameter(Mandatory)]
        [string]$Category,

        [Parameter(Mandatory)]
        [string]$CheckName,

        [ValidateSet('Green', 'Yellow', 'Red', 'Unknown')]
        [string]$Status = 'Unknown',

        [ValidateSet('Informational', 'Low', 'Medium', 'High', 'Critical', 'Unknown')]
        [string]$Severity = 'Unknown',

        [Parameter(Mandatory)]
        [string]$Message,

        [string]$Recommendation = 'Review this finding.',

        [AllowNull()]
        [object]$Evidence = '',

        [ValidateSet('Low', 'Medium', 'High', 'Unknown')]
        [string]$ConfidenceLevel = 'Unknown'
    )

    if ([string]::IsNullOrWhiteSpace($Recommendation)) {
        $Recommendation = 'Review this finding.'
    }

    if ($null -eq $Evidence) {
        $Evidence = ''
    }

    [pscustomobject]@{
        Timestamp       = Get-Date
        TargetName      = $TargetName
        TargetType      = $TargetType
        Category        = $Category
        CheckName       = $CheckName
        Status          = $Status
        Severity        = $Severity
        Message         = $Message
        Recommendation  = $Recommendation
        Evidence        = $Evidence
        ConfidenceLevel = $ConfidenceLevel
    }
}

function Convert-LocalHealthResultToFindings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$LocalHealthResult
    )

    $targetName = [string]$LocalHealthResult.TargetName
    $targetType = if ($LocalHealthResult.TargetType) { [string]$LocalHealthResult.TargetType } else { 'Local' }
    $findings = [System.Collections.Generic.List[object]]::new()

    $cpu = $LocalHealthResult.OsHealth.Cpu
    if ($null -ne $cpu) {
        $findings.Add((New-HealthFinding -TargetName $targetName -TargetType $targetType -Category 'CPU' -CheckName 'CPU Usage' -Status $cpu.Status -Severity (Get-DefaultSeverity -Status $cpu.Status) -Message $cpu.Message -Recommendation 'Review CPU-heavy processes and scheduled workload patterns if usage remains elevated.' -Evidence ([pscustomobject]@{ Value = $cpu.Value; Unit = $cpu.Unit; Source = $cpu.Evidence }) -ConfidenceLevel 'High'))
    }

    $memory = $LocalHealthResult.OsHealth.Memory
    if ($null -ne $memory) {
        $findings.Add((New-HealthFinding -TargetName $targetName -TargetType $targetType -Category 'Memory' -CheckName 'Memory Usage' -Status $memory.Status -Severity (Get-DefaultSeverity -Status $memory.Status) -Message $memory.Message -Recommendation 'Review memory pressure, application working sets, and capacity trends if usage remains elevated.' -Evidence ([pscustomobject]@{ Value = $memory.Value; Unit = $memory.Unit; Details = $memory.Evidence }) -ConfidenceLevel 'High'))
    }

    $pendingReboot = $LocalHealthResult.PendingReboot
    if ($null -ne $pendingReboot) {
        $pendingSeverity = if ($pendingReboot.Status -eq 'Red') { 'Critical' } elseif ($pendingReboot.Status -eq 'Yellow') { 'Medium' } else { Get-DefaultSeverity -Status $pendingReboot.Status }
        $recommendation = if ($pendingReboot.IsPendingReboot) { 'Plan a controlled maintenance window to complete the pending reboot.' } else { 'No reboot action is indicated by the checked read-only signals.' }
        $findings.Add((New-HealthFinding -TargetName $targetName -TargetType $targetType -Category 'PendingReboot' -CheckName 'Pending Reboot' -Status $pendingReboot.Status -Severity $pendingSeverity -Message $pendingReboot.Message -Recommendation $recommendation -Evidence ([pscustomobject]@{ IsPendingReboot = $pendingReboot.IsPendingReboot; Reasons = @($pendingReboot.Reasons) }) -ConfidenceLevel 'High'))
    }

    foreach ($disk in @($LocalHealthResult.StorageHealth.LogicalDisks)) {
        if ($null -eq $disk) { continue }
        $checkName = if ($disk.DriveLetter) { "Logical Disk $($disk.DriveLetter)" } else { 'Logical Disk' }
        $diskSeverity = if ($disk.Status -eq 'Red') { 'Critical' } else { Get-DefaultSeverity -Status $disk.Status }
        $findings.Add((New-HealthFinding -TargetName $targetName -TargetType $targetType -Category 'Storage' -CheckName $checkName -Status $disk.Status -Severity $diskSeverity -Message $disk.Message -Recommendation 'Review disk free space and remove, archive, or move data during an approved maintenance process if needed.' -Evidence ([pscustomobject]@{ DriveLetter = $disk.DriveLetter; VolumeName = $disk.VolumeName; TotalGB = $disk.TotalGB; FreeGB = $disk.FreeGB; FreePercent = $disk.FreePercent }) -ConfidenceLevel 'High'))
    }

    foreach ($disk in @($LocalHealthResult.StorageHealth.PhysicalDisks)) {
        if ($null -eq $disk) { continue }
        $checkName = if ($disk.FriendlyName) { "Physical Disk $($disk.FriendlyName)" } else { 'Physical Disk' }
        $physicalSeverity = if ($disk.Status -eq 'Red') { 'Critical' } elseif ($disk.Status -eq 'Yellow') { 'High' } else { Get-DefaultSeverity -Status $disk.Status }
        $findings.Add((New-HealthFinding -TargetName $targetName -TargetType $targetType -Category 'Storage' -CheckName $checkName -Status $disk.Status -Severity $physicalSeverity -Message $disk.Message -Recommendation 'Review storage subsystem health, vendor tooling, backups, and replacement planning where hardware warnings are present.' -Evidence ([pscustomobject]@{ FriendlyName = $disk.FriendlyName; MediaType = $disk.MediaType; HealthStatus = $disk.HealthStatus; OperationalStatus = $disk.OperationalStatus; SizeGB = $disk.SizeGB }) -ConfidenceLevel 'Medium'))
    }

    foreach ($service in @($LocalHealthResult.OsHealth.CriticalServices)) {
        if ($null -eq $service) { continue }
        $serviceName = if ($service.Evidence.ServiceName) { $service.Evidence.ServiceName } else { 'UnknownService' }
        $serviceSeverity = if ($service.Status -eq 'Red') { 'Critical' } else { Get-DefaultSeverity -Status $service.Status }
        $findings.Add((New-HealthFinding -TargetName $targetName -TargetType $targetType -Category 'CriticalService' -CheckName "Critical Service $serviceName" -Status $service.Status -Severity $serviceSeverity -Message $service.Message -Recommendation 'Review the service state and dependencies before maintenance; do not restart services from this report workflow.' -Evidence ([pscustomobject]@{ Value = $service.Value; Unit = $service.Unit; Details = $service.Evidence }) -ConfidenceLevel 'High'))
    }

    foreach ($adapter in @($LocalHealthResult.NetworkHealth.Adapters)) {
        if ($null -eq $adapter) { continue }
        $adapterStatus = if ($adapter.StatusEvaluation) { [string]$adapter.StatusEvaluation } else { 'Unknown' }
        $checkName = if ($adapter.Name) { "Network Adapter $($adapter.Name)" } else { 'Network Adapter' }
        $findings.Add((New-HealthFinding -TargetName $targetName -TargetType $targetType -Category 'Network' -CheckName $checkName -Status $adapterStatus -Severity (Get-DefaultSeverity -Status $adapterStatus) -Message $adapter.Message -Recommendation 'Review adapter state, cabling, switch configuration, and expected link speed if network warnings persist.' -Evidence ([pscustomobject]@{ Name = $adapter.Name; InterfaceDescription = $adapter.InterfaceDescription; AdapterStatus = $adapter.Status; LinkSpeed = $adapter.LinkSpeed; MacAddress = $adapter.MacAddress }) -ConfidenceLevel 'Medium'))
    }

    $eventLogGroups = @($LocalHealthResult.EventLogRisk) |
        Where-Object { $null -ne $_ } |
        Group-Object -Property RiskCategory, LogName, EventId, ProviderName |
        ForEach-Object {
            $events = @($_.Group)
            $redCount = @($events | Where-Object { $_.Status -eq 'Red' }).Count
            $status = if ($redCount -gt 0) { 'Red' } elseif (@($events | Where-Object { $_.Status -eq 'Yellow' }).Count -gt 0) { 'Yellow' } else { 'Unknown' }
            $severity = if (@($events | Where-Object { $_.LevelDisplayName -eq 'Critical' }).Count -gt 0) { 'Critical' } elseif ($status -eq 'Red') { 'High' } elseif ($status -eq 'Yellow') { 'Medium' } else { 'Unknown' }
            [pscustomobject]@{
                RiskCategory     = [string]$events[0].RiskCategory
                LogName          = [string]$events[0].LogName
                EventId          = $events[0].EventId
                ProviderName     = [string]$events[0].ProviderName
                Status           = $status
                Severity         = $severity
                Count            = $events.Count
                LevelDisplayName = [string]$events[0].LevelDisplayName
                MessagePreview   = [string]$events[0].MessagePreview
            }
        } |
        Sort-Object @{ Expression = { if ($_.Severity -eq 'Critical') { 4 } elseif ($_.Severity -eq 'High') { 3 } elseif ($_.Severity -eq 'Medium') { 2 } else { 1 } }; Descending = $true }, @{ Expression = 'Count'; Descending = $true } |
        Select-Object -First 20

    foreach ($group in $eventLogGroups) {
        $message = "Risk Indicator: $($group.Count) matching event log entries were observed for Event ID $($group.EventId) from '$($group.ProviderName)' in '$($group.LogName)'."
        $recommendation = 'Review the grouped event log pattern, related vendor guidance, and recent change history; treat this as an early warning signal, not an exact failure prediction.'
        $findings.Add((New-HealthFinding -TargetName $targetName -TargetType $targetType -Category "EventLog:$($group.RiskCategory)" -CheckName "Event Log Risk $($group.EventId)" -Status $group.Status -Severity $group.Severity -Message $message -Recommendation $recommendation -Evidence ([pscustomobject]@{ RiskCategory = $group.RiskCategory; LogName = $group.LogName; EventId = $group.EventId; ProviderName = $group.ProviderName; Count = $group.Count; LevelDisplayName = $group.LevelDisplayName; MessagePreview = $group.MessagePreview }) -ConfidenceLevel 'Medium'))
    }

    return @($findings)
}

function Get-OverallHealthScore {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object[]]$Findings
    )

    if ($null -eq $Findings) {
        return [pscustomobject]@{
            OverallStatus = 'Unknown'
            Score         = 0
            FindingCount  = 0
            RedCount      = 0
            YellowCount   = 0
            GreenCount    = 0
            UnknownCount  = 0
            CriticalCount = 0
            HighCount     = 0
            MediumCount   = 0
            SummaryMessage = 'Health findings could not be evaluated.'
        }
    }

    $items = @($Findings)
    if (@($items | Where-Object { $null -eq $_ }).Count -gt 0) {
        return [pscustomobject]@{
            OverallStatus = 'Unknown'
            Score         = 0
            FindingCount  = $items.Count
            RedCount      = 0
            YellowCount   = 0
            GreenCount    = 0
            UnknownCount  = $items.Count
            CriticalCount = 0
            HighCount     = 0
            MediumCount   = 0
            SummaryMessage = 'Health findings could not be evaluated.'
        }
    }

    $score = 0
    foreach ($finding in $items) {
        $score += switch ($finding.Status) {
            'Green' { 0 }
            'Yellow' { 1 }
            'Unknown' { 1 }
            'Red' { 3 }
            default { 1 }
        }
    }

    $criticalCount = @($items | Where-Object { $_.Severity -eq 'Critical' }).Count
    $overallStatus = if ($criticalCount -gt 0) {
        'Red'
    }
    elseif ($score -eq 0) {
        'Green'
    }
    elseif ($score -gt 5) {
        'Red'
    }
    else {
        'Yellow'
    }

    $summaryMessage = switch ($overallStatus) {
        'Green' { 'No warning, critical, or unknown findings were detected.' }
        'Yellow' { 'One or more findings should be reviewed before routine maintenance.' }
        default { 'Significant health findings require administrator review before maintenance.' }
    }

    [pscustomobject]@{
        OverallStatus = $overallStatus
        Score         = $score
        FindingCount  = $items.Count
        RedCount      = @($items | Where-Object { $_.Status -eq 'Red' }).Count
        YellowCount   = @($items | Where-Object { $_.Status -eq 'Yellow' }).Count
        GreenCount    = @($items | Where-Object { $_.Status -eq 'Green' }).Count
        UnknownCount  = @($items | Where-Object { $_.Status -eq 'Unknown' }).Count
        CriticalCount = $criticalCount
        HighCount     = @($items | Where-Object { $_.Severity -eq 'High' }).Count
        MediumCount   = @($items | Where-Object { $_.Severity -eq 'Medium' }).Count
        SummaryMessage = $summaryMessage
    }
}

function Get-MaintenanceReadinessStatus {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object[]]$Findings
    )

    $items = @($Findings)
    $reasons = [System.Collections.Generic.List[string]]::new()

    if (@($items | Where-Object { $_.Severity -eq 'Critical' }).Count -gt 0) {
        $reasons.Add('One or more Critical severity findings are present.')
    }

    if (@($items | Where-Object { ($_.Category -eq 'Storage' -or $_.CheckName -like '*Disk*') -and $_.Status -eq 'Red' }).Count -gt 0) {
        $reasons.Add('A Red disk or storage finding is present.')
    }

    if (@($items | Where-Object { ($_.Category -eq 'PendingReboot' -or $_.CheckName -like '*Pending Reboot*') -and $_.Status -eq 'Red' }).Count -gt 0) {
        $reasons.Add('Pending reboot status is Red.')
    }

    if (@($items | Where-Object { ($_.Category -eq 'CriticalService' -or $_.CheckName -like '*Critical Service*') -and $_.Status -eq 'Red' }).Count -gt 0) {
        $reasons.Add('A critical service finding is Red.')
    }

    if ($reasons.Count -gt 0) {
        return [pscustomobject]@{
            ReadinessStatus = 'NotReady'
            Reasons         = @($reasons)
            Recommendation  = 'Resolve or formally accept Not Ready findings before starting maintenance.'
        }
    }

    if (@($items | Where-Object { $_.Severity -eq 'High' }).Count -gt 0) {
        $reasons.Add('One or more High severity findings are present.')
    }

    if (@($items | Where-Object { ($_.Category -eq 'PendingReboot' -or $_.CheckName -like '*Pending Reboot*') -and $_.Status -eq 'Yellow' }).Count -gt 0) {
        $reasons.Add('Pending reboot status is Yellow.')
    }

    if (@($items | Where-Object { $_.Category -like 'EventLog:*' -and $_.Status -ne 'Green' }).Count -gt 1) {
        $reasons.Add('Multiple event log risk indicators are present.')
    }

    if (@($items | Where-Object { ($_.Category -eq 'Storage' -or $_.CheckName -like '*Disk*') -and $_.Status -eq 'Yellow' }).Count -gt 0) {
        $reasons.Add('Disk free space is Yellow.')
    }

    if ($reasons.Count -gt 0 -or @($items | Where-Object { $_.Status -eq 'Red' }).Count -gt 0) {
        return [pscustomobject]@{
            ReadinessStatus = 'ReviewRequired'
            Reasons         = @($reasons)
            Recommendation  = 'Review warnings and document an operator decision before starting maintenance.'
        }
    }

    [pscustomobject]@{
        ReadinessStatus = 'Ready'
        Reasons         = @('No Red or High findings are present.')
        Recommendation  = 'Proceed with normal maintenance planning using standard change controls.'
    }
}

Export-ModuleMember -Function @(
    'Get-BasicHealthStatus',
    'New-HealthFinding',
    'Convert-LocalHealthResultToFindings',
    'Get-OverallHealthScore',
    'Get-MaintenanceReadinessStatus'
)
