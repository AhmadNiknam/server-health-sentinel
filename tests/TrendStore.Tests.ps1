Describe 'TrendStore' {
    BeforeAll {
        $modulePath = Join-Path $PSScriptRoot '../src/modules/TrendStore.psm1'
        Import-Module $modulePath -Force

        function New-TestTrendFinding {
            param(
                [string]$TargetName = 'TEST-SERVER',
                [string]$TargetType = 'Local',
                [string]$Category = 'Storage',
                [string]$CheckName = 'Logical Disk C:',
                [string]$Status = 'Green',
                [string]$Severity = 'Informational'
            )

            [pscustomobject]@{
                Timestamp       = Get-Date
                TargetName      = $TargetName
                TargetType      = $TargetType
                Category        = $Category
                CheckName       = $CheckName
                Status          = $Status
                Severity        = $Severity
                Message         = 'Test finding.'
                Recommendation  = 'Review this finding.'
                Evidence        = ''
                ConfidenceLevel = 'High'
            }
        }

        function New-TestOverallScore {
            param(
                [int]$Score = 1,
                [int]$RedCount = 0,
                [int]$YellowCount = 1,
                [int]$CriticalCount = 0,
                [int]$HighCount = 0
            )

            [pscustomobject]@{
                OverallStatus = if ($RedCount -gt 0 -or $CriticalCount -gt 0) { 'Red' } elseif ($YellowCount -gt 0) { 'Yellow' } else { 'Green' }
                Score         = $Score
                FindingCount  = 1
                RedCount      = $RedCount
                YellowCount   = $YellowCount
                GreenCount    = 0
                UnknownCount  = 0
                CriticalCount = $CriticalCount
                HighCount     = $HighCount
                MediumCount   = $YellowCount
            }
        }
    }

    BeforeEach {
        $script:HistoryPath = Join-Path (Join-Path $env:TEMP 'ServerHealthSentinelTrendTests') ([guid]::NewGuid().ToString())
        $null = New-Item -Path $script:HistoryPath -ItemType Directory -Force
        $script:Readiness = [pscustomobject]@{
            ReadinessStatus = 'ReviewRequired'
            Reasons         = @('Test reason.')
            Recommendation  = 'Review before maintenance.'
        }
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:HistoryPath) {
            Remove-Item -LiteralPath $script:HistoryPath -Recurse -Force
        }
    }

    It 'creates expected trend snapshot object' {
        $findings = @(New-TestTrendFinding -Status 'Red' -Severity 'Critical')
        $snapshot = New-TrendSnapshot -Mode 'Local' -RawResults ([pscustomobject]@{ TargetName = 'TEST-SERVER'; TargetType = 'Local' }) -Findings $findings -OverallScore (New-TestOverallScore -Score 3 -RedCount 1 -YellowCount 0 -CriticalCount 1) -MaintenanceReadiness $script:Readiness

        $snapshot.SnapshotId | Should -Not -BeNullOrEmpty
        $snapshot.Mode | Should -Be 'Local'
        $snapshot.TargetCount | Should -Be 1
        $snapshot.RedCount | Should -Be 1
        $snapshot.CriticalCount | Should -Be 1
        @($snapshot.TargetSummaries).Count | Should -Be 1
        @($snapshot.CategorySummaries).Count | Should -Be 1
        @($snapshot.FindingsSummary).Count | Should -Be 1
    }

    It 'saves a trend snapshot as JSON in a temp folder' {
        $snapshot = New-TrendSnapshot -Mode 'Local' -RawResults @() -Findings @(New-TestTrendFinding) -OverallScore (New-TestOverallScore) -MaintenanceReadiness $script:Readiness

        $path = Save-TrendSnapshot -Snapshot $snapshot -HistoryPath $script:HistoryPath

        Test-Path -LiteralPath $path | Should -Be $true
        Split-Path -Parent $path | Should -Be $script:HistoryPath
        Split-Path -Leaf $path | Should -Match '^trend-snapshot-local-\d{8}-\d{6}-\d{3}\.json$'
    }

    It 'returns latest trend snapshots' {
        $first = New-TrendSnapshot -Mode 'Local' -RawResults @() -Findings @(New-TestTrendFinding) -OverallScore (New-TestOverallScore -Score 1) -MaintenanceReadiness $script:Readiness
        $second = New-TrendSnapshot -Mode 'Local' -RawResults @() -Findings @(New-TestTrendFinding -Status 'Red' -Severity 'Critical') -OverallScore (New-TestOverallScore -Score 3 -RedCount 1 -YellowCount 0 -CriticalCount 1) -MaintenanceReadiness $script:Readiness
        $null = Save-TrendSnapshot -Snapshot $first -HistoryPath $script:HistoryPath
        Start-Sleep -Milliseconds 20
        $null = Save-TrendSnapshot -Snapshot $second -HistoryPath $script:HistoryPath

        $snapshots = @(Get-LatestTrendSnapshots -HistoryPath $script:HistoryPath -Count 1)

        $snapshots.Count | Should -Be 1
        $snapshots[0].HealthScore | Should -Be 3
    }

    It 'returns only Local snapshots when Mode is Local' {
        $local = New-TrendSnapshot -Mode 'Local' -RawResults @() -Findings @(New-TestTrendFinding) -OverallScore (New-TestOverallScore -Score 2) -MaintenanceReadiness $script:Readiness
        $hybrid = New-TrendSnapshot -Mode 'Hybrid' -RawResults @() -Findings @(New-TestTrendFinding -TargetType 'Hybrid') -OverallScore (New-TestOverallScore -Score 5 -RedCount 1 -YellowCount 0) -MaintenanceReadiness $script:Readiness
        $null = Save-TrendSnapshot -Snapshot $hybrid -HistoryPath $script:HistoryPath
        Start-Sleep -Milliseconds 20
        $null = Save-TrendSnapshot -Snapshot $local -HistoryPath $script:HistoryPath

        $snapshots = @(Get-LatestTrendSnapshots -HistoryPath $script:HistoryPath -Count 5 -Mode 'Local')

        $snapshots.Count | Should -Be 1
        $snapshots[0].Mode | Should -Be 'Local'
        $snapshots[0].HealthScore | Should -Be 2
    }

    It 'returns only Hybrid snapshots when Mode is Hybrid' {
        $local = New-TrendSnapshot -Mode 'Local' -RawResults @() -Findings @(New-TestTrendFinding) -OverallScore (New-TestOverallScore -Score 2) -MaintenanceReadiness $script:Readiness
        $hybrid = New-TrendSnapshot -Mode 'Hybrid' -RawResults @() -Findings @(New-TestTrendFinding -TargetType 'Hybrid') -OverallScore (New-TestOverallScore -Score 5 -RedCount 1 -YellowCount 0) -MaintenanceReadiness $script:Readiness
        $null = Save-TrendSnapshot -Snapshot $local -HistoryPath $script:HistoryPath
        Start-Sleep -Milliseconds 20
        $null = Save-TrendSnapshot -Snapshot $hybrid -HistoryPath $script:HistoryPath

        $snapshots = @(Get-LatestTrendSnapshots -HistoryPath $script:HistoryPath -Count 5 -Mode 'Hybrid')

        $snapshots.Count | Should -Be 1
        $snapshots[0].Mode | Should -Be 'Hybrid'
        $snapshots[0].HealthScore | Should -Be 5
    }

    It 'returns an empty collection when no same-mode snapshot exists' {
        $local = New-TrendSnapshot -Mode 'Local' -RawResults @() -Findings @(New-TestTrendFinding) -OverallScore (New-TestOverallScore -Score 2) -MaintenanceReadiness $script:Readiness
        $null = Save-TrendSnapshot -Snapshot $local -HistoryPath $script:HistoryPath

        $snapshots = @(Get-LatestTrendSnapshots -HistoryPath $script:HistoryPath -Count 1 -Mode 'Hybrid')

        $snapshots.Count | Should -Be 0
    }

    It 'keeps legacy snapshot filenames readable when filtering by mode' {
        $legacy = New-TrendSnapshot -Mode 'Local' -RawResults @() -Findings @(New-TestTrendFinding) -OverallScore (New-TestOverallScore -Score 2) -MaintenanceReadiness $script:Readiness
        $legacyPath = Join-Path $script:HistoryPath 'trend-snapshot-20260425-101500-000.json'
        $legacy | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $legacyPath -Encoding utf8

        $snapshots = @(Get-LatestTrendSnapshots -HistoryPath $script:HistoryPath -Count 1 -Mode 'Local')

        $snapshots.Count | Should -Be 1
        $snapshots[0].Mode | Should -Be 'Local'
    }

    It 'returns Unknown when no previous snapshot exists' {
        $current = New-TrendSnapshot -Mode 'Local' -RawResults @() -Findings @(New-TestTrendFinding) -OverallScore (New-TestOverallScore) -MaintenanceReadiness $script:Readiness

        $comparison = Compare-TrendSnapshots -CurrentSnapshot $current -PreviousSnapshot $null

        $comparison.HasPreviousSnapshot | Should -Be $false
        $comparison.RiskTrend | Should -Be 'Unknown'
        $comparison.SummaryMessage | Should -Be 'No previous snapshot found for mode: Local.'
    }

    It 'returns Unknown when no previous same-mode snapshot exists' {
        $local = New-TrendSnapshot -Mode 'Local' -RawResults @() -Findings @(New-TestTrendFinding) -OverallScore (New-TestOverallScore -Score 4 -RedCount 1 -YellowCount 0) -MaintenanceReadiness $script:Readiness
        $currentHybrid = New-TrendSnapshot -Mode 'Hybrid' -RawResults @() -Findings @(New-TestTrendFinding -TargetType 'Hybrid') -OverallScore (New-TestOverallScore -Score 1) -MaintenanceReadiness $script:Readiness
        $null = Save-TrendSnapshot -Snapshot $local -HistoryPath $script:HistoryPath

        $previousSnapshots = @(Get-LatestTrendSnapshots -HistoryPath $script:HistoryPath -Count 1 -Mode $currentHybrid.Mode)
        $previousSnapshot = if ($previousSnapshots.Count -gt 0) { $previousSnapshots[0] } else { $null }
        $comparison = Compare-TrendSnapshots -CurrentSnapshot $currentHybrid -PreviousSnapshot $previousSnapshot

        $comparison.HasPreviousSnapshot | Should -Be $false
        $comparison.RiskTrend | Should -Be 'Unknown'
        $comparison.SummaryMessage | Should -Be 'No previous snapshot found for mode: Hybrid.'
    }

    It 'does not compare a Hybrid snapshot against a Local snapshot' {
        $local = New-TrendSnapshot -Mode 'Local' -RawResults @() -Findings @(New-TestTrendFinding) -OverallScore (New-TestOverallScore -Score 8 -RedCount 1 -YellowCount 0 -CriticalCount 1) -MaintenanceReadiness $script:Readiness
        $currentHybrid = New-TrendSnapshot -Mode 'Hybrid' -RawResults @() -Findings @(New-TestTrendFinding -TargetType 'Hybrid') -OverallScore (New-TestOverallScore -Score 1) -MaintenanceReadiness $script:Readiness
        $null = Save-TrendSnapshot -Snapshot $local -HistoryPath $script:HistoryPath

        $previousSnapshots = @(Get-LatestTrendSnapshots -HistoryPath $script:HistoryPath -Count 1 -Mode 'Hybrid')
        $comparison = Compare-TrendSnapshots -CurrentSnapshot $currentHybrid -PreviousSnapshot $previousSnapshots[0]

        $comparison.HasPreviousSnapshot | Should -Be $false
        $comparison.RiskTrend | Should -Be 'Unknown'
        $comparison.SummaryMessage | Should -Be 'No previous snapshot found for mode: Hybrid.'
    }

    It 'returns Worsening when health score increases' {
        $previous = New-TrendSnapshot -Mode 'Local' -RawResults @() -Findings @(New-TestTrendFinding) -OverallScore (New-TestOverallScore -Score 1) -MaintenanceReadiness $script:Readiness
        $current = New-TrendSnapshot -Mode 'Local' -RawResults @() -Findings @(New-TestTrendFinding -Status 'Red' -Severity 'Critical') -OverallScore (New-TestOverallScore -Score 4 -RedCount 1 -YellowCount 0 -CriticalCount 1) -MaintenanceReadiness $script:Readiness

        $comparison = Compare-TrendSnapshots -CurrentSnapshot $current -PreviousSnapshot $previous

        $comparison.RiskTrend | Should -Be 'Worsening'
        $comparison.HealthScoreChange | Should -Be 3
    }

    It 'returns Improving when health score decreases and critical risk decreases' {
        $previous = New-TrendSnapshot -Mode 'Local' -RawResults @() -Findings @(New-TestTrendFinding -Status 'Red' -Severity 'Critical') -OverallScore (New-TestOverallScore -Score 4 -RedCount 1 -YellowCount 0 -CriticalCount 1) -MaintenanceReadiness $script:Readiness
        $current = New-TrendSnapshot -Mode 'Local' -RawResults @() -Findings @(New-TestTrendFinding) -OverallScore (New-TestOverallScore -Score 0 -RedCount 0 -YellowCount 0 -CriticalCount 0) -MaintenanceReadiness ([pscustomobject]@{ ReadinessStatus = 'Ready' })

        $comparison = Compare-TrendSnapshots -CurrentSnapshot $current -PreviousSnapshot $previous

        $comparison.RiskTrend | Should -Be 'Improving'
        $comparison.HealthScoreChange | Should -Be -4
    }
}
