<#
PredictiveHealthAnalyzer module.

Combines normalized findings into honest rule-based predictive risk indicators.
#>

function Get-PredictiveComponentCategory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Finding
    )

    $category = [string]$Finding.Category
    $checkName = [string]$Finding.CheckName

    if ($category -eq 'Storage' -or $category -eq 'AzureDisk' -or $checkName -like '*Disk*') { return 'Storage' }
    if ($category -like 'EventLog:*' -or $category -eq 'EventLogRisk' -or $checkName -like '*Event*') { return 'EventLogRisk' }
    if ($category -eq 'Network' -or $category -eq 'AzureNetwork' -or $checkName -like '*Network*') { return 'Network' }
    if ($category -eq 'CriticalService' -or $checkName -like '*Critical Service*') { return 'Service' }
    if ($category -eq 'PendingReboot' -or $checkName -like '*Pending Reboot*') { return 'PendingReboot' }
    if ($category -like '*Hardware*' -or $checkName -like '*Sensor*') { return 'HardwareSensor' }
    if ($category -like 'Azure*' -or [string]$Finding.TargetType -eq 'AzureVM') { return 'AzureVM' }

    return $null
}

function Get-PredictiveRiskLevel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Finding,

        [Parameter(Mandatory)]
        [string]$ComponentCategory
    )

    if ($ComponentCategory -eq 'HardwareSensor' -and $Finding.Status -eq 'Unknown') { return 'Unknown' }
    if ($ComponentCategory -eq 'Service' -and ($Finding.Status -eq 'Red' -or $Finding.Severity -eq 'Critical')) { return 'Critical' }
    if ($Finding.Severity -eq 'Critical') { return 'Critical' }
    if ($Finding.Status -eq 'Red' -or $Finding.Severity -eq 'High') { return 'High' }
    if ($Finding.Status -eq 'Yellow' -or $Finding.Severity -eq 'Medium') { return 'Medium' }
    if ($Finding.Status -eq 'Unknown') { return 'Unknown' }
    return 'Low'
}

function Get-PredictiveRecommendation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComponentCategory
    )

    switch ($ComponentCategory) {
        'Storage' { 'Review storage capacity, disk health, backups, and related event log patterns before maintenance.' }
        'EventLogRisk' { 'Review repeated event log indicators and correlate them with monitoring and recent changes.' }
        'Network' { 'Review adapter state, expected link speed, cabling, switch configuration, and network change history.' }
        'Service' { 'Review critical service state and dependencies; this tool does not restart services.' }
        'PendingReboot' { 'Plan reboot activity only through approved maintenance and change control.' }
        'HardwareSensor' { 'Review hardware sensor visibility and warning states through approved vendor tooling.' }
        'AzureVM' { 'Review Azure context, access, VM metadata, and guest health visibility. This is an operational risk indicator, not a hardware failure prediction.' }
        default { 'Review this early warning indicator through normal operational procedures.' }
    }
}

function Get-PredictiveRiskIndicators {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object[]]$Findings,

        [AllowNull()]
        [object]$PredictiveRules
    )

    $items = @($Findings | Where-Object { $null -ne $_ })
    $indicators = [System.Collections.Generic.List[object]]::new()

    foreach ($finding in $items) {
        $componentCategory = Get-PredictiveComponentCategory -Finding $finding
        if ($null -eq $componentCategory) { continue }
        if ($finding.Status -eq 'Green' -and $finding.Severity -in @('Informational', 'Low')) { continue }

        $riskLevel = Get-PredictiveRiskLevel -Finding $finding -ComponentCategory $componentCategory
        $message = "Early Warning: $($finding.Message)"

        $indicators.Add([pscustomobject]@{
                TargetName        = [string]$finding.TargetName
                TargetType        = [string]$finding.TargetType
                ComponentCategory = $componentCategory
                IndicatorName     = [string]$finding.CheckName
                RiskLevel         = $riskLevel
                Message           = $message
                Evidence          = [pscustomobject]@{
                    Category        = $finding.Category
                    Status          = $finding.Status
                    Severity        = $finding.Severity
                    ConfidenceLevel = $finding.ConfidenceLevel
                }
                Recommendation    = Get-PredictiveRecommendation -ComponentCategory $componentCategory
                ConfidenceLevel   = if ([string]::IsNullOrWhiteSpace([string]$finding.ConfidenceLevel)) { 'Unknown' } else { [string]$finding.ConfidenceLevel }
            })
    }

    return @($indicators | Sort-Object TargetName, ComponentCategory, IndicatorName)
}

function Get-PredictiveRiskRank {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$RiskLevel
    )

    switch ($RiskLevel) {
        'Low' { 1 }
        'Medium' { 2 }
        'High' { 3 }
        'Critical' { 4 }
        'Unknown' { 0 }
        default { 0 }
    }
}

function Compare-PredictiveRiskTrend {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object[]]$CurrentComponentRisk,

        [AllowNull()]
        [object]$PreviousSnapshot
    )

    $currentItems = @($CurrentComponentRisk | Where-Object { $null -ne $_ })
    if ($null -eq $PreviousSnapshot) {
        return @(
            $currentItems | ForEach-Object {
                [pscustomobject]@{
                    TargetName        = $_.TargetName
                    TargetType        = $_.TargetType
                    ComponentCategory = $_.ComponentCategory
                    ComponentName     = $_.ComponentName
                    CurrentRiskLevel  = $_.RiskLevel
                    PreviousRiskLevel = $null
                    RiskTrend         = 'Unknown'
                }
            }
        )
    }

    $previousLookup = @{}
    foreach ($summary in @($PreviousSnapshot.TargetSummaries)) {
        if ($null -eq $summary) { continue }
        $key = "$($summary.TargetName)|$($summary.TargetType)"
        $previousLookup[$key] = [string]$summary.OverallTargetRisk
    }

    return @(
        $currentItems | ForEach-Object {
            $targetKey = "$($_.TargetName)|$($_.TargetType)"
            $previousRisk = if ($previousLookup.ContainsKey($targetKey)) { $previousLookup[$targetKey] } else { $null }
            $currentRank = Get-PredictiveRiskRank -RiskLevel $_.RiskLevel
            $previousRank = Get-PredictiveRiskRank -RiskLevel $previousRisk
            $trend = if ([string]::IsNullOrWhiteSpace($previousRisk)) {
                'NewRisk'
            }
            elseif ($currentRank -gt $previousRank) {
                'IncreasedRisk'
            }
            elseif ($currentRank -lt $previousRank) {
                'DecreasedRisk'
            }
            elseif ($currentRank -eq 0 -and $previousRank -eq 0) {
                'Unknown'
            }
            else {
                'StableRisk'
            }

            [pscustomobject]@{
                TargetName        = $_.TargetName
                TargetType        = $_.TargetType
                ComponentCategory = $_.ComponentCategory
                ComponentName     = $_.ComponentName
                CurrentRiskLevel  = $_.RiskLevel
                PreviousRiskLevel = $previousRisk
                RiskTrend         = $trend
            }
        }
    )
}

Export-ModuleMember -Function @(
    'Get-PredictiveRiskIndicators',
    'Compare-PredictiveRiskTrend'
)
