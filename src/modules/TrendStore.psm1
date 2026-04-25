<#
TrendStore module.

Stores lightweight read-only trend snapshots for comparing operational risk
indicators between runs.
#>

function Get-TrendSafeNumber {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) { return 0 }

    try {
        return [int]$Value
    }
    catch {
        return 0
    }
}

function Get-TrendReadinessValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$MaintenanceReadiness
    )

    $status = if ($null -ne $MaintenanceReadiness -and $MaintenanceReadiness.PSObject.Properties.Name -contains 'ReadinessStatus') {
        [string]$MaintenanceReadiness.ReadinessStatus
    }
    else {
        [string]$MaintenanceReadiness
    }

    switch ($status) {
        'Ready' { 0 }
        'ReviewRequired' { 1 }
        'NotReady' { 2 }
        default { 0 }
    }
}

function Get-TrendReadinessChange {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$CurrentReadiness,

        [AllowNull()]
        [object]$PreviousReadiness
    )

    $currentValue = Get-TrendReadinessValue -MaintenanceReadiness $CurrentReadiness
    $previousValue = Get-TrendReadinessValue -MaintenanceReadiness $PreviousReadiness

    if ($currentValue -gt $previousValue) { return 'Worse' }
    if ($currentValue -lt $previousValue) { return 'Better' }
    return 'Unchanged'
}

function New-TrendSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Mode,

        [AllowNull()]
        [object]$RawResults,

        [AllowNull()]
        [object[]]$Findings,

        [Parameter(Mandatory)]
        [object]$OverallScore,

        [Parameter(Mandatory)]
        [object]$MaintenanceReadiness
    )

    $items = @($Findings | Where-Object { $null -ne $_ })
    $rawItems = @($RawResults | Where-Object { $null -ne $_ })
    $targetNames = @($items | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.TargetName) } | Select-Object -ExpandProperty TargetName -Unique)
    $targetCount = $targetNames.Count
    if ($targetCount -eq 0 -and $rawItems.Count -gt 0) {
        $targetCount = $rawItems.Count
    }
    if ($rawItems.Count -eq 1 -and $null -ne $rawItems[0].TotalTargetsChecked) {
        $targetCount = [int]$rawItems[0].TotalTargetsChecked
    }

    $targetSummaries = @(
        $items |
            Group-Object -Property TargetName, TargetType |
            ForEach-Object {
                $groupItems = @($_.Group)
                $redCount = @($groupItems | Where-Object { $_.Status -eq 'Red' }).Count
                $yellowCount = @($groupItems | Where-Object { $_.Status -eq 'Yellow' }).Count
                $unknownCount = @($groupItems | Where-Object { $_.Status -eq 'Unknown' }).Count
                $criticalCount = @($groupItems | Where-Object { $_.Severity -eq 'Critical' }).Count
                $highCount = @($groupItems | Where-Object { $_.Severity -eq 'High' }).Count
                $overallTargetRisk = if ($criticalCount -gt 0 -or $redCount -gt 0) {
                    'High'
                }
                elseif ($highCount -gt 0 -or $yellowCount -gt 0) {
                    'Medium'
                }
                elseif ($unknownCount -gt 0) {
                    'Unknown'
                }
                else {
                    'Low'
                }

                [pscustomobject]@{
                    TargetName        = [string]$groupItems[0].TargetName
                    TargetType        = [string]$groupItems[0].TargetType
                    RedCount          = $redCount
                    YellowCount       = $yellowCount
                    UnknownCount      = $unknownCount
                    CriticalCount     = $criticalCount
                    HighCount         = $highCount
                    OverallTargetRisk = $overallTargetRisk
                }
            }
    )

    $categorySummaries = @(
        $items |
            Group-Object -Property Category |
            ForEach-Object {
                $groupItems = @($_.Group)
                [pscustomobject]@{
                    Category      = [string]$_.Name
                    RedCount      = @($groupItems | Where-Object { $_.Status -eq 'Red' }).Count
                    YellowCount   = @($groupItems | Where-Object { $_.Status -eq 'Yellow' }).Count
                    UnknownCount  = @($groupItems | Where-Object { $_.Status -eq 'Unknown' }).Count
                    CriticalCount = @($groupItems | Where-Object { $_.Severity -eq 'Critical' }).Count
                    HighCount     = @($groupItems | Where-Object { $_.Severity -eq 'High' }).Count
                }
            }
    )

    $findingsSummary = @(
        $items |
            Sort-Object TargetName, Category, CheckName |
            Select-Object TargetName, TargetType, Category, CheckName, Status, Severity, ConfidenceLevel
    )

    [pscustomobject]@{
        SnapshotId           = [guid]::NewGuid().ToString()
        Timestamp            = Get-Date
        Mode                 = $Mode
        TargetCount          = $targetCount
        FindingCount         = Get-TrendSafeNumber -Value $OverallScore.FindingCount
        RedCount             = Get-TrendSafeNumber -Value $OverallScore.RedCount
        YellowCount          = Get-TrendSafeNumber -Value $OverallScore.YellowCount
        GreenCount           = Get-TrendSafeNumber -Value $OverallScore.GreenCount
        UnknownCount         = Get-TrendSafeNumber -Value $OverallScore.UnknownCount
        CriticalCount        = Get-TrendSafeNumber -Value $OverallScore.CriticalCount
        HighCount            = Get-TrendSafeNumber -Value $OverallScore.HighCount
        MediumCount          = Get-TrendSafeNumber -Value $OverallScore.MediumCount
        OverallStatus        = [string]$OverallScore.OverallStatus
        HealthScore          = Get-TrendSafeNumber -Value $OverallScore.Score
        MaintenanceReadiness = if ($MaintenanceReadiness.PSObject.Properties.Name -contains 'ReadinessStatus') { [string]$MaintenanceReadiness.ReadinessStatus } else { [string]$MaintenanceReadiness }
        TargetSummaries      = @($targetSummaries)
        CategorySummaries    = @($categorySummaries)
        FindingsSummary      = @($findingsSummary)
    }
}

function Save-TrendSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Snapshot,

        [string]$HistoryPath = './history'
    )

    if (-not (Test-Path -LiteralPath $HistoryPath -PathType Container)) {
        $null = New-Item -Path $HistoryPath -ItemType Directory -Force
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $path = Join-Path $HistoryPath "trend-snapshot-$timestamp.json"
    $Snapshot | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path -Encoding utf8
    return $path
}

function Get-LatestTrendSnapshots {
    [CmdletBinding()]
    param(
        [string]$HistoryPath = './history',

        [int]$Count = 1
    )

    if (-not (Test-Path -LiteralPath $HistoryPath -PathType Container)) {
        return @()
    }

    $files = @(
        Get-ChildItem -LiteralPath $HistoryPath -Filter 'trend-snapshot-*.json' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -First $Count
    )

    $snapshots = [System.Collections.Generic.List[object]]::new()
    foreach ($file in $files) {
        try {
            $snapshots.Add((Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json))
        }
        catch {
            continue
        }
    }

    return @($snapshots)
}

function Compare-TrendSnapshots {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$CurrentSnapshot,

        [AllowNull()]
        [object]$PreviousSnapshot
    )

    if ($null -eq $PreviousSnapshot) {
        return [pscustomobject]@{
            HasPreviousSnapshot       = $false
            PreviousTimestamp         = $null
            CurrentTimestamp          = $CurrentSnapshot.Timestamp
            HealthScoreChange         = 0
            RedFindingChange          = 0
            YellowFindingChange       = 0
            UnknownFindingChange      = 0
            CriticalFindingChange     = 0
            HighFindingChange         = 0
            MaintenanceReadinessChange = 'Unknown'
            RiskTrend                 = 'Unknown'
            SummaryMessage            = 'Reason: No previous snapshot found.'
        }
    }

    $healthScoreChange = (Get-TrendSafeNumber -Value $CurrentSnapshot.HealthScore) - (Get-TrendSafeNumber -Value $PreviousSnapshot.HealthScore)
    $redFindingChange = (Get-TrendSafeNumber -Value $CurrentSnapshot.RedCount) - (Get-TrendSafeNumber -Value $PreviousSnapshot.RedCount)
    $yellowFindingChange = (Get-TrendSafeNumber -Value $CurrentSnapshot.YellowCount) - (Get-TrendSafeNumber -Value $PreviousSnapshot.YellowCount)
    $unknownFindingChange = (Get-TrendSafeNumber -Value $CurrentSnapshot.UnknownCount) - (Get-TrendSafeNumber -Value $PreviousSnapshot.UnknownCount)
    $criticalFindingChange = (Get-TrendSafeNumber -Value $CurrentSnapshot.CriticalCount) - (Get-TrendSafeNumber -Value $PreviousSnapshot.CriticalCount)
    $highFindingChange = (Get-TrendSafeNumber -Value $CurrentSnapshot.HighCount) - (Get-TrendSafeNumber -Value $PreviousSnapshot.HighCount)
    $readinessChange = Get-TrendReadinessChange -CurrentReadiness $CurrentSnapshot.MaintenanceReadiness -PreviousReadiness $PreviousSnapshot.MaintenanceReadiness

    $criticalHighChange = $criticalFindingChange + $highFindingChange
    $riskTrend = if ($healthScoreChange -gt 0 -or $redFindingChange -gt 0 -or $criticalHighChange -gt 0) {
        'Worsening'
    }
    elseif ($healthScoreChange -lt 0 -and $redFindingChange -le 0 -and $criticalHighChange -le 0 -and ($redFindingChange -lt 0 -or $criticalHighChange -lt 0 -or $yellowFindingChange -lt 0 -or $unknownFindingChange -lt 0)) {
        'Improving'
    }
    else {
        'Stable'
    }

    $summaryMessage = switch ($riskTrend) {
        'Worsening' { 'Trend Indicator: Failure Risk appears to be increasing compared with the previous snapshot.' }
        'Improving' { 'Trend Indicator: Failure Risk appears to be decreasing compared with the previous snapshot.' }
        default { 'Trend Indicator: Failure Risk appears stable compared with the previous snapshot.' }
    }

    [pscustomobject]@{
        HasPreviousSnapshot        = $true
        PreviousTimestamp          = $PreviousSnapshot.Timestamp
        CurrentTimestamp           = $CurrentSnapshot.Timestamp
        HealthScoreChange          = $healthScoreChange
        RedFindingChange           = $redFindingChange
        YellowFindingChange        = $yellowFindingChange
        UnknownFindingChange       = $unknownFindingChange
        CriticalFindingChange      = $criticalFindingChange
        HighFindingChange          = $highFindingChange
        MaintenanceReadinessChange = $readinessChange
        RiskTrend                  = $riskTrend
        SummaryMessage             = $summaryMessage
    }
}

Export-ModuleMember -Function @(
    'New-TrendSnapshot',
    'Save-TrendSnapshot',
    'Get-LatestTrendSnapshots',
    'Compare-TrendSnapshots'
)
