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

function Convert-OnPremHealthResultToFindings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$OnPremHealthResult
    )

    $targetName = [string]$OnPremHealthResult.TargetName
    $targetType = if ($OnPremHealthResult.TargetType) { [string]$OnPremHealthResult.TargetType } else { 'OnPrem' }
    $findings = [System.Collections.Generic.List[object]]::new()

    $connectivity = $OnPremHealthResult.Connectivity
    if ($null -ne $connectivity) {
        $connectivitySeverity = if ($connectivity.Status -eq 'Red') { 'Critical' } else { Get-DefaultSeverity -Status $connectivity.Status }
        $findings.Add((New-HealthFinding -TargetName $targetName -TargetType $targetType -Category 'Connectivity' -CheckName 'Remote Connectivity' -Status $connectivity.Status -Severity $connectivitySeverity -Message $connectivity.Message -Recommendation 'Validate DNS, network routing, firewall rules, and WinRM/CIM access using approved administrative procedures.' -Evidence ([pscustomobject]@{ DnsResolved = $connectivity.DnsResolved; PingSucceeded = $connectivity.PingSucceeded; CimAvailable = $connectivity.CimAvailable; Details = $connectivity.Evidence }) -ConfidenceLevel 'Medium'))

        if (-not $connectivity.CimAvailable -or $connectivity.Status -eq 'Red') {
            $findings.Add((New-HealthFinding -TargetName $targetName -TargetType $targetType -Category 'Connectivity' -CheckName 'Server Unreachable' -Status 'Red' -Severity 'Critical' -Message "Remote health checks could not be completed for '$targetName'." -Recommendation 'Investigate reachability and remote management access before relying on this server health snapshot.' -Evidence ([pscustomobject]@{ ConnectivityStatus = $connectivity.Status; Message = $connectivity.Message }) -ConfidenceLevel 'High'))
        }
    }

    $cpu = $OnPremHealthResult.OsHealth.Cpu
    if ($null -ne $cpu) {
        $findings.Add((New-HealthFinding -TargetName $targetName -TargetType $targetType -Category 'CPU' -CheckName 'CPU Usage' -Status $cpu.Status -Severity (Get-DefaultSeverity -Status $cpu.Status) -Message $cpu.Message -Recommendation 'Review CPU-heavy processes and scheduled workload patterns if usage remains elevated.' -Evidence ([pscustomobject]@{ Value = $cpu.Value; Unit = $cpu.Unit; Source = $cpu.Evidence }) -ConfidenceLevel 'Medium'))
    }

    $memory = $OnPremHealthResult.OsHealth.Memory
    if ($null -ne $memory) {
        $findings.Add((New-HealthFinding -TargetName $targetName -TargetType $targetType -Category 'Memory' -CheckName 'Memory Usage' -Status $memory.Status -Severity (Get-DefaultSeverity -Status $memory.Status) -Message $memory.Message -Recommendation 'Review memory pressure, application working sets, and capacity trends if usage remains elevated.' -Evidence ([pscustomobject]@{ Value = $memory.Value; Unit = $memory.Unit; Details = $memory.Evidence }) -ConfidenceLevel 'Medium'))
    }

    $uptime = $OnPremHealthResult.OsHealth.Uptime
    if ($null -ne $uptime) {
        $findings.Add((New-HealthFinding -TargetName $targetName -TargetType $targetType -Category 'Uptime' -CheckName 'Uptime' -Status $uptime.Status -Severity (Get-DefaultSeverity -Status $uptime.Status) -Message $uptime.Message -Recommendation 'Review uptime against maintenance policy and planned patch cadence.' -Evidence ([pscustomobject]@{ Value = $uptime.Value; Unit = $uptime.Unit; Details = $uptime.Evidence }) -ConfidenceLevel 'Medium'))
    }

    $pendingReboot = $OnPremHealthResult.PendingReboot
    if ($null -ne $pendingReboot) {
        $pendingSeverity = if ($pendingReboot.Status -eq 'Red') { 'Critical' } elseif ($pendingReboot.Status -eq 'Yellow') { 'Medium' } else { Get-DefaultSeverity -Status $pendingReboot.Status }
        $recommendation = if ($pendingReboot.IsPendingReboot) { 'Plan a controlled maintenance window to complete the pending reboot.' } elseif ($pendingReboot.Status -eq 'Unknown') { 'Confirm pending reboot status through approved administrative tooling if this signal is required for maintenance decisions.' } else { 'No reboot action is indicated by the checked read-only signals.' }
        $findings.Add((New-HealthFinding -TargetName $targetName -TargetType $targetType -Category 'PendingReboot' -CheckName 'Pending Reboot' -Status $pendingReboot.Status -Severity $pendingSeverity -Message $pendingReboot.Message -Recommendation $recommendation -Evidence ([pscustomobject]@{ IsPendingReboot = $pendingReboot.IsPendingReboot; Reasons = @($pendingReboot.Reasons) }) -ConfidenceLevel 'Medium'))
    }

    foreach ($disk in @($OnPremHealthResult.StorageHealth.LogicalDisks)) {
        if ($null -eq $disk) { continue }
        $checkName = if ($disk.DriveLetter) { "Logical Disk $($disk.DriveLetter)" } else { 'Logical Disk' }
        $diskSeverity = if ($disk.Status -eq 'Red') { 'Critical' } else { Get-DefaultSeverity -Status $disk.Status }
        $findings.Add((New-HealthFinding -TargetName $targetName -TargetType $targetType -Category 'Storage' -CheckName $checkName -Status $disk.Status -Severity $diskSeverity -Message $disk.Message -Recommendation 'Review disk free space and remove, archive, or move data during an approved maintenance process if needed.' -Evidence ([pscustomobject]@{ DriveLetter = $disk.DriveLetter; VolumeName = $disk.VolumeName; TotalGB = $disk.TotalGB; FreeGB = $disk.FreeGB; FreePercent = $disk.FreePercent }) -ConfidenceLevel 'High'))
    }

    foreach ($service in @($OnPremHealthResult.OsHealth.CriticalServices)) {
        if ($null -eq $service) { continue }
        $serviceName = if ($service.Evidence.ServiceName) { $service.Evidence.ServiceName } else { 'UnknownService' }
        $serviceSeverity = if ($service.Status -eq 'Red') { 'Critical' } else { Get-DefaultSeverity -Status $service.Status }
        $findings.Add((New-HealthFinding -TargetName $targetName -TargetType $targetType -Category 'CriticalService' -CheckName "Critical Service $serviceName" -Status $service.Status -Severity $serviceSeverity -Message $service.Message -Recommendation 'Review the service state and dependencies before maintenance; do not restart services from this report workflow.' -Evidence ([pscustomobject]@{ Value = $service.Value; Unit = $service.Unit; Details = $service.Evidence }) -ConfidenceLevel 'Medium'))
    }

    foreach ($adapter in @($OnPremHealthResult.NetworkHealth.Adapters)) {
        if ($null -eq $adapter) { continue }
        $adapterStatus = if ($adapter.StatusEvaluation) { [string]$adapter.StatusEvaluation } else { 'Unknown' }
        $checkName = if ($adapter.Name) { "Network Adapter $($adapter.Name)" } else { 'Network Adapter' }
        $findings.Add((New-HealthFinding -TargetName $targetName -TargetType $targetType -Category 'Network' -CheckName $checkName -Status $adapterStatus -Severity (Get-DefaultSeverity -Status $adapterStatus) -Message $adapter.Message -Recommendation 'Review adapter state, cabling, switch configuration, and expected link speed if network warnings persist.' -Evidence ([pscustomobject]@{ Name = $adapter.Name; InterfaceDescription = $adapter.InterfaceDescription; AdapterStatus = $adapter.Status; NetConnectionStatus = $adapter.NetConnectionStatus; LinkSpeed = $adapter.LinkSpeed; MacAddress = $adapter.MacAddress }) -ConfidenceLevel 'Medium'))
    }

    return @($findings)
}

function Convert-OnPremBatchHealthResultToFindings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$OnPremHealthResults
    )

    $findings = [System.Collections.Generic.List[object]]::new()
    foreach ($result in @($OnPremHealthResults)) {
        if ($null -eq $result) { continue }
        foreach ($finding in @(Convert-OnPremHealthResultToFindings -OnPremHealthResult $result)) {
            $findings.Add($finding)
        }
    }

    return @($findings)
}

function Get-AzureFindingStatus {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Status
    )

    $statusText = [string]$Status
    if ($statusText -in @('Green', 'Yellow', 'Red', 'Unknown')) {
        return $statusText
    }

    return 'Unknown'
}

function Convert-AzureVmHealthResultToFindings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$AzureVmHealthResult
    )

    $targetName = [string]$AzureVmHealthResult.TargetName
    $targetType = if ($AzureVmHealthResult.TargetType) { [string]$AzureVmHealthResult.TargetType } else { 'AzureVM' }
    $findings = [System.Collections.Generic.List[object]]::new()

    foreach ($module in @($AzureVmHealthResult.AzureContext.Modules)) {
        if ($null -eq $module) { continue }
        $status = if ($module.Available) { 'Green' } else { 'Unknown' }
        $recommendation = if ($module.Available) {
            'No action is needed for this Azure PowerShell module.'
        }
        else {
            "Install the '$($module.ModuleName)' PowerShell module before using Azure checks that require it."
        }

        $findings.Add((New-HealthFinding -TargetName $targetName -TargetType $targetType -Category 'AzureContext' -CheckName "Az Module $($module.ModuleName)" -Status $status -Severity (Get-DefaultSeverity -Status $status) -Message ([string]$module.Message) -Recommendation $recommendation -Evidence ([pscustomobject]@{ ModuleName = $module.ModuleName; Available = $module.Available; Version = $module.Version }) -ConfidenceLevel 'High'))
    }

    $context = $AzureVmHealthResult.AzureContext.Context
    if ($null -ne $context) {
        $status = Get-AzureFindingStatus -Status $context.Status
        $severity = if (-not $context.IsAuthenticated) { 'High' } else { Get-DefaultSeverity -Status $status }
        $findings.Add((New-HealthFinding -TargetName $targetName -TargetType $targetType -Category 'AzureContext' -CheckName 'Azure Authentication Context' -Status $status -Severity $severity -Message ([string]$context.Message) -Recommendation 'Run Connect-AzAccount in the current PowerShell session before using Azure mode. Use an account with the least privilege needed for read-only review and optional Run Command.' -Evidence ([pscustomobject]@{ IsAuthenticated = $context.IsAuthenticated; Account = $context.Account; TenantIdMasked = $context.TenantIdMasked; SubscriptionIdMasked = $context.SubscriptionIdMasked; SubscriptionName = $context.SubscriptionName }) -ConfidenceLevel 'High'))
    }

    $subscription = $AzureVmHealthResult.AzureContext.Subscription
    if ($null -ne $subscription) {
        $status = Get-AzureFindingStatus -Status $subscription.Status
        $severity = if (-not $subscription.Succeeded) { 'High' } else { Get-DefaultSeverity -Status $status }
        $findings.Add((New-HealthFinding -TargetName $targetName -TargetType $targetType -Category 'AzureContext' -CheckName 'Azure Subscription Context' -Status $status -Severity $severity -Message ([string]$subscription.Message) -Recommendation 'Use a real subscription ID in a local ignored config file and confirm the signed-in account has access to that subscription.' -Evidence ([pscustomobject]@{ Succeeded = $subscription.Succeeded; SubscriptionIdMasked = $subscription.SubscriptionIdMasked; SubscriptionName = $subscription.SubscriptionName }) -ConfidenceLevel 'High'))
    }

    $metadataResult = $AzureVmHealthResult.Metadata
    if ($null -ne $metadataResult) {
        $status = Get-AzureFindingStatus -Status $metadataResult.Status
        $message = if ($metadataResult.Message) { [string]$metadataResult.Message } else { 'Azure VM metadata status could not be evaluated.' }
        $recommendation = if ($status -eq 'Red') {
            'Confirm the VM exists, the resource group is correct, and the signed-in account has at least Reader access.'
        }
        else {
            'Review Azure VM metadata before maintenance and confirm the VM identity and state are expected.'
        }

        $findings.Add((New-HealthFinding -TargetName $targetName -TargetType $targetType -Category 'AzureMetadata' -CheckName 'Azure VM Metadata' -Status $status -Severity (Get-DefaultSeverity -Status $status) -Message $message -Recommendation $recommendation -Evidence $metadataResult.Metadata -ConfidenceLevel 'High'))

        if ($null -ne $metadataResult.Metadata) {
            $powerState = [string]$metadataResult.Metadata.PowerState
            $powerStatus = if ([string]::IsNullOrWhiteSpace($powerState)) {
                'Unknown'
            }
            elseif ($powerState -match 'running') {
                'Green'
            }
            else {
                'Yellow'
            }
            $powerMessage = if ([string]::IsNullOrWhiteSpace($powerState)) {
                'Azure VM power state was not available.'
            }
            else {
                "Azure VM power state is '$powerState'."
            }
            $findings.Add((New-HealthFinding -TargetName $targetName -TargetType $targetType -Category 'AzureMetadata' -CheckName 'Azure VM Power State' -Status $powerStatus -Severity (Get-DefaultSeverity -Status $powerStatus) -Message $powerMessage -Recommendation 'Review stopped, deallocated, or unknown VM power states before maintenance. This tool does not start, stop, or reboot VMs.' -Evidence ([pscustomobject]@{ PowerState = $powerState }) -ConfidenceLevel 'High'))

            $provisioningState = [string]$metadataResult.Metadata.ProvisioningState
            $provisioningStatus = if ([string]::IsNullOrWhiteSpace($provisioningState)) {
                'Unknown'
            }
            elseif ($provisioningState -eq 'Succeeded') {
                'Green'
            }
            else {
                'Yellow'
            }
            $findings.Add((New-HealthFinding -TargetName $targetName -TargetType $targetType -Category 'AzureMetadata' -CheckName 'Azure VM Provisioning State' -Status $provisioningStatus -Severity (Get-DefaultSeverity -Status $provisioningStatus) -Message "Azure VM provisioning state is '$provisioningState'." -Recommendation 'Review non-succeeded provisioning states in Azure before maintenance.' -Evidence ([pscustomobject]@{ ProvisioningState = $provisioningState }) -ConfidenceLevel 'High'))
        }
    }

    $diskSummary = $AzureVmHealthResult.DiskSummary
    if ($null -ne $diskSummary) {
        $status = Get-AzureFindingStatus -Status $diskSummary.Status
        $findings.Add((New-HealthFinding -TargetName $targetName -TargetType $targetType -Category 'AzureDisk' -CheckName 'Azure Managed Disk Summary' -Status $status -Severity (Get-DefaultSeverity -Status $status) -Message ([string]$diskSummary.Message) -Recommendation 'Review OS and data disk count, SKU, and size against expected VM design. This tool does not modify disks.' -Evidence ([pscustomobject]@{ OsDiskName = $diskSummary.OsDiskName; OsDiskType = $diskSummary.OsDiskType; DataDiskCount = $diskSummary.DataDiskCount; Disks = @($diskSummary.Disks) }) -ConfidenceLevel 'Medium'))
    }

    $networkSummary = $AzureVmHealthResult.NetworkSummary
    if ($null -ne $networkSummary) {
        $status = Get-AzureFindingStatus -Status $networkSummary.Status
        $findings.Add((New-HealthFinding -TargetName $targetName -TargetType $targetType -Category 'AzureNetwork' -CheckName 'Azure Network Interface Summary' -Status $status -Severity (Get-DefaultSeverity -Status $status) -Message ([string]$networkSummary.Message) -Recommendation 'Review NIC count, private IPs, public IP associations, and accelerated networking before maintenance. This tool does not modify network resources.' -Evidence ([pscustomobject]@{ NicCount = $networkSummary.NicCount; PrivateIPs = @($networkSummary.PrivateIPs); PublicIPAssociations = @($networkSummary.PublicIPAssociations); NetworkInterfaceNames = @($networkSummary.NetworkInterfaceNames); AcceleratedNetworking = @($networkSummary.AcceleratedNetworking); Nics = @($networkSummary.Nics) }) -ConfidenceLevel 'Medium'))
    }

    $guestHealth = $AzureVmHealthResult.GuestHealth
    if ($null -ne $guestHealth) {
        $status = Get-AzureFindingStatus -Status $guestHealth.Status
        $severity = if ($guestHealth.Attempted -and $status -eq 'Unknown') { 'High' } else { Get-DefaultSeverity -Status $status }
        $findings.Add((New-HealthFinding -TargetName $targetName -TargetType $targetType -Category 'AzureGuestHealth' -CheckName 'Azure VM Run Command Guest Health' -Status $status -Severity $severity -Message ([string]$guestHealth.Message) -Recommendation 'Confirm VM Agent and Run Command permissions if guest health is required. This tool does not reboot VMs, restart services, or remediate guest issues.' -Evidence ([pscustomobject]@{ Attempted = $guestHealth.Attempted; ParsedAvailable = $null -ne $guestHealth.Parsed }) -ConfidenceLevel 'Medium'))

        if ($null -ne $guestHealth.Parsed) {
            $parsed = $guestHealth.Parsed
            if ($null -ne $parsed.Cpu) {
                $cpuStatus = Get-BasicHealthStatus -Value $parsed.Cpu.UsagePercent -WarningThreshold 80 -CriticalThreshold 95 -ComparisonType GreaterThan
                $findings.Add((New-HealthFinding -TargetName $targetName -TargetType $targetType -Category 'AzureGuestHealth' -CheckName 'Guest CPU Usage' -Status $cpuStatus -Severity (Get-DefaultSeverity -Status $cpuStatus) -Message "Guest CPU usage is $($parsed.Cpu.UsagePercent)%." -Recommendation 'Review CPU-heavy processes and workload schedule if usage remains elevated.' -Evidence $parsed.Cpu -ConfidenceLevel 'Medium'))
            }

            if ($null -ne $parsed.Memory) {
                $memoryStatus = Get-BasicHealthStatus -Value $parsed.Memory.UsedPercent -WarningThreshold 80 -CriticalThreshold 95 -ComparisonType GreaterThan
                $findings.Add((New-HealthFinding -TargetName $targetName -TargetType $targetType -Category 'AzureGuestHealth' -CheckName 'Guest Memory Usage' -Status $memoryStatus -Severity (Get-DefaultSeverity -Status $memoryStatus) -Message "Guest memory usage is $($parsed.Memory.UsedPercent)%." -Recommendation 'Review memory pressure and application working sets if usage remains elevated.' -Evidence $parsed.Memory -ConfidenceLevel 'Medium'))
            }

            foreach ($disk in @($parsed.LogicalDisks)) {
                if ($null -eq $disk) { continue }
                $diskStatus = Get-BasicHealthStatus -Value $disk.FreePercent -WarningThreshold 20 -CriticalThreshold 10 -ComparisonType LessThan
                $diskSeverity = if ($diskStatus -eq 'Red') { 'Critical' } else { Get-DefaultSeverity -Status $diskStatus }
                $findings.Add((New-HealthFinding -TargetName $targetName -TargetType $targetType -Category 'AzureGuestHealth' -CheckName "Guest Logical Disk $($disk.DriveLetter)" -Status $diskStatus -Severity $diskSeverity -Message "Guest logical disk $($disk.DriveLetter) free space is $($disk.FreePercent)%." -Recommendation 'Review guest disk free space during an approved maintenance process. This tool does not remove or move data.' -Evidence $disk -ConfidenceLevel 'Medium'))
            }

            foreach ($service in @($parsed.CriticalServices)) {
                if ($null -eq $service) { continue }
                $serviceStatus = if ($service.Status -eq 'Running') { 'Green' } elseif ($service.Status -eq 'Unknown') { 'Unknown' } else { 'Red' }
                $serviceSeverity = if ($serviceStatus -eq 'Red') { 'Critical' } else { Get-DefaultSeverity -Status $serviceStatus }
                $findings.Add((New-HealthFinding -TargetName $targetName -TargetType $targetType -Category 'AzureGuestHealth' -CheckName "Guest Critical Service $($service.ServiceName)" -Status $serviceStatus -Severity $serviceSeverity -Message "Guest service '$($service.ServiceName)' status is '$($service.Status)'." -Recommendation 'Review service state and dependencies before maintenance. This tool does not restart services.' -Evidence $service -ConfidenceLevel 'Medium'))
            }

            if ($null -ne $parsed.PendingReboot) {
                $rebootStatus = if ($parsed.PendingReboot.IsPendingReboot) { 'Yellow' } else { 'Green' }
                $findings.Add((New-HealthFinding -TargetName $targetName -TargetType $targetType -Category 'AzureGuestHealth' -CheckName 'Guest Pending Reboot' -Status $rebootStatus -Severity (Get-DefaultSeverity -Status $rebootStatus) -Message $(if ($parsed.PendingReboot.IsPendingReboot) { 'Guest pending reboot indicators were found.' } else { 'No common guest pending reboot indicators were found.' }) -Recommendation 'Plan reboot activity through normal change control if pending reboot indicators matter for maintenance.' -Evidence $parsed.PendingReboot -ConfidenceLevel 'Medium'))
            }

            foreach ($eventCount in @($parsed.RecentEventCounts)) {
                if ($null -eq $eventCount) { continue }
                $eventStatus = if ($null -eq $eventCount.ErrorOrCriticalCount) { 'Unknown' } elseif ($eventCount.ErrorOrCriticalCount -gt 0) { 'Yellow' } else { 'Green' }
                $findings.Add((New-HealthFinding -TargetName $targetName -TargetType $targetType -Category 'AzureGuestHealth' -CheckName "Guest Event Count $($eventCount.LogName)" -Status $eventStatus -Severity (Get-DefaultSeverity -Status $eventStatus) -Message "Guest $($eventCount.LogName) log has $($eventCount.ErrorOrCriticalCount) Error/Critical event(s) in the last 24 hours." -Recommendation 'Review recent guest event log errors before maintenance if warning counts are present.' -Evidence $eventCount -ConfidenceLevel 'Medium'))
            }
        }
    }

    return @($findings)
}

function Convert-AzureVmBatchHealthResultToFindings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$AzureVmHealthResults
    )

    $findings = [System.Collections.Generic.List[object]]::new()
    foreach ($result in @($AzureVmHealthResults)) {
        if ($null -eq $result) { continue }
        foreach ($finding in @(Convert-AzureVmHealthResultToFindings -AzureVmHealthResult $result)) {
            $findings.Add($finding)
        }
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
    'Convert-OnPremHealthResultToFindings',
    'Convert-OnPremBatchHealthResultToFindings',
    'Convert-AzureVmHealthResultToFindings',
    'Convert-AzureVmBatchHealthResultToFindings',
    'Get-OverallHealthScore',
    'Get-MaintenanceReadinessStatus'
)
