<#
ComponentRiskModel module.

Builds rule-based component risk scores from normalized health findings.
#>

function Get-RiskScoreFromLevel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Low', 'Medium', 'High', 'Critical', 'Unknown')]
        [string]$RiskLevel
    )

    switch ($RiskLevel) {
        'Low' { 1 }
        'Medium' { 2 }
        'High' { 4 }
        'Critical' { 6 }
        default { 1 }
    }
}

function Get-ComponentCategory {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Finding
    )

    $category = [string]$Finding.Category
    $checkName = [string]$Finding.CheckName

    if ($category -eq 'Storage' -or $category -eq 'AzureDisk' -or $checkName -like '*Disk*') { return 'Storage' }
    if ($category -eq 'Network' -or $category -eq 'AzureNetwork' -or $checkName -like '*Network Adapter*') { return 'Network' }
    if ($category -eq 'CriticalService' -or $checkName -like '*Critical Service*') { return 'Service' }
    if ($category -like 'EventLog:*' -or $category -eq 'EventLogRisk' -or $checkName -like '*Event*') { return 'EventLogRisk' }
    if ($category -eq 'PendingReboot' -or $checkName -like '*Pending Reboot*') { return 'PendingReboot' }
    if ($category -like 'Azure*' -or [string]$Finding.TargetType -eq 'AzureVM') { return 'AzureVM' }
    if ($category -like '*Hardware*' -or $checkName -like '*Sensor*') { return 'HardwareSensor' }

    return $null
}

function Get-ComponentRiskLevel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Findings,

        [Parameter(Mandatory)]
        [ValidateSet('Storage', 'Network', 'Service', 'EventLogRisk', 'PendingReboot', 'AzureVM', 'HardwareSensor')]
        [string]$ComponentCategory
    )

    $hasCritical = @($Findings | Where-Object { $_.Severity -eq 'Critical' }).Count -gt 0
    $hasHigh = @($Findings | Where-Object { $_.Severity -eq 'High' }).Count -gt 0
    $hasRed = @($Findings | Where-Object { $_.Status -eq 'Red' }).Count -gt 0
    $hasYellow = @($Findings | Where-Object { $_.Status -eq 'Yellow' }).Count -gt 0
    $hasUnknown = @($Findings | Where-Object { $_.Status -eq 'Unknown' }).Count -gt 0
    $evidenceCount = $Findings.Count

    switch ($ComponentCategory) {
        'Storage' {
            if ($hasCritical) { return 'Critical' }
            if ($hasRed -or $hasHigh) { return 'High' }
            if ($hasYellow) { return 'Medium' }
        }
        'EventLogRisk' {
            if ($hasCritical -or $hasRed -or $evidenceCount -ge 3) { return 'High' }
            if ($hasYellow -or $evidenceCount -gt 0) { return 'Medium' }
        }
        'Network' {
            if ($hasRed -or $hasHigh) { return 'High' }
            if ($hasYellow -or $hasUnknown) { return 'Medium' }
        }
        'PendingReboot' {
            if ($hasRed -or $hasCritical) { return 'High' }
            if ($hasYellow) { return 'Medium' }
        }
        'Service' {
            if ($hasCritical -or $hasRed) { return 'Critical' }
            if ($hasYellow -or $hasHigh) { return 'High' }
        }
        'AzureVM' {
            if ($hasRed -or $hasHigh) { return 'Medium' }
            if ($hasYellow -or $hasUnknown) { return 'Medium' }
        }
        'HardwareSensor' {
            if ($hasCritical -or $hasRed) { return 'Critical' }
            if ($hasYellow -or $hasHigh) { return 'High' }
            if ($hasUnknown) { return 'Unknown' }
        }
    }

    if ($hasUnknown) { return 'Unknown' }
    return 'Low'
}

function Get-ComponentRecommendation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Storage', 'Network', 'Service', 'EventLogRisk', 'PendingReboot', 'AzureVM', 'HardwareSensor')]
        [string]$ComponentCategory,

        [Parameter(Mandatory)]
        [string]$RiskLevel
    )

    switch ($ComponentCategory) {
        'Storage' { 'Review storage capacity, health status, backups, and vendor tooling before maintenance. Treat this as an early warning indicator.' }
        'Network' { 'Review adapter state, cabling, switch configuration, expected link speed, and recent network changes.' }
        'Service' { 'Review critical service state and dependencies before maintenance; do not restart services from this workflow.' }
        'EventLogRisk' { 'Review repeated event log patterns and correlate them with monitoring, vendor guidance, and recent changes.' }
        'PendingReboot' { 'Plan any reboot only through normal change control and maintenance approval.' }
        'AzureVM' { 'Review Azure context, access, VM metadata, and guest health visibility. This is not a hardware failure prediction.' }
        'HardwareSensor' {
            if ($RiskLevel -eq 'Unknown') {
                'Confirm hardware sensor visibility through approved vendor tooling if this signal is required.'
            }
            else {
                'Review hardware sensor alerts through approved vendor tooling and normal change control.'
            }
        }
    }
}

function Get-ComponentRiskScore {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object[]]$Findings,

        [string]$TargetName
    )

    $items = @($Findings | Where-Object { $null -ne $_ })
    if (-not [string]::IsNullOrWhiteSpace($TargetName)) {
        $items = @($items | Where-Object { [string]$_.TargetName -eq $TargetName })
    }

    $riskItems = @(
        $items |
            ForEach-Object {
                $componentCategory = Get-ComponentCategory -Finding $_
                if ($null -ne $componentCategory) {
                    [pscustomobject]@{
                        Finding           = $_
                        ComponentCategory = $componentCategory
                    }
                }
            } |
            Where-Object { $null -ne $_ }
    )

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($group in @($riskItems | Group-Object -Property { "$($_.Finding.TargetName)|$($_.Finding.TargetType)|$($_.ComponentCategory)|$($_.Finding.CheckName)" })) {
        $groupItems = @($group.Group)
        $findingsForComponent = @($groupItems.Finding)
        $category = [string]$groupItems[0].ComponentCategory
        $riskLevel = Get-ComponentRiskLevel -Findings $findingsForComponent -ComponentCategory $category
        $evidenceSummary = (@($findingsForComponent | Select-Object -ExpandProperty Message -First 3) -join ' | ')
        if ([string]::IsNullOrWhiteSpace($evidenceSummary)) {
            $evidenceSummary = (@($findingsForComponent | Select-Object -ExpandProperty CheckName -First 3) -join ' | ')
        }

        $results.Add([pscustomobject]@{
                TargetName        = [string]$findingsForComponent[0].TargetName
                TargetType        = [string]$findingsForComponent[0].TargetType
                ComponentCategory = $category
                ComponentName     = [string]$findingsForComponent[0].CheckName
                RiskLevel         = $riskLevel
                RiskScore         = Get-RiskScoreFromLevel -RiskLevel $riskLevel
                EvidenceCount     = $findingsForComponent.Count
                EvidenceSummary   = $evidenceSummary
                Recommendation    = Get-ComponentRecommendation -ComponentCategory $category -RiskLevel $riskLevel
                ConfidenceLevel   = if (@($findingsForComponent | Where-Object { $_.ConfidenceLevel -eq 'High' }).Count -gt 0) { 'High' } elseif (@($findingsForComponent | Where-Object { $_.ConfidenceLevel -eq 'Medium' }).Count -gt 0) { 'Medium' } elseif ($riskLevel -eq 'Unknown') { 'Unknown' } else { 'Low' }
            })
    }

    return @($results | Sort-Object TargetName, ComponentCategory, ComponentName)
}

Export-ModuleMember -Function 'Get-ComponentRiskScore'
