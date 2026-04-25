Describe 'ReportGenerator' {
    BeforeAll {
        $modulePath = Join-Path $PSScriptRoot '../src/modules/ReportGenerator.psm1'
        Import-Module $modulePath -Force
    }

    BeforeEach {
        $testRoot = Join-Path $env:TEMP 'ServerHealthSentinelTests'
        $script:OutputPath = Join-Path $testRoot ([guid]::NewGuid().ToString())
        $null = New-Item -Path $script:OutputPath -ItemType Directory -Force

        $script:RawResult = [pscustomobject]@{
            TargetName = 'TEST-SERVER'
            TargetType = 'Local'
            Timestamp  = Get-Date
        }

        $script:Findings = @(
            [pscustomobject]@{
                Timestamp       = Get-Date
                TargetName      = 'TEST-SERVER'
                TargetType      = 'Local'
                Category        = 'CPU'
                CheckName       = 'CPU Usage'
                Status          = 'Green'
                Severity        = 'Informational'
                Message         = 'CPU usage is within threshold.'
                Recommendation  = 'Continue monitoring.'
                Evidence        = [pscustomobject]@{ Value = 20; Unit = 'Percent' }
                ConfidenceLevel = 'High'
            },
            [pscustomobject]@{
                Timestamp       = Get-Date
                TargetName      = 'TEST-SERVER'
                TargetType      = 'Local'
                Category        = 'Storage'
                CheckName       = 'Logical Disk C:'
                Status          = 'Yellow'
                Severity        = 'Medium'
                Message         = 'Drive C: free space is below warning threshold.'
                Recommendation  = 'Review disk free space.'
                Evidence        = [pscustomobject]@{ DriveLetter = 'C:'; FreePercent = 12 }
                ConfidenceLevel = 'High'
            }
        )

        $script:OverallScore = [pscustomobject]@{
            OverallStatus = 'Yellow'
            Score         = 1
            FindingCount  = 2
            RedCount      = 0
            YellowCount   = 1
            GreenCount    = 1
            UnknownCount  = 0
            CriticalCount = 0
            HighCount     = 0
            MediumCount   = 1
            SummaryMessage = 'One or more findings should be reviewed before routine maintenance.'
        }

        $script:MaintenanceReadiness = [pscustomobject]@{
            ReadinessStatus = 'ReviewRequired'
            Reasons         = @('Disk free space is Yellow.')
            Recommendation  = 'Review warnings before maintenance.'
        }

        $script:TrendComparison = [pscustomobject]@{
            HasPreviousSnapshot        = $true
            PreviousTimestamp          = (Get-Date).AddDays(-7)
            CurrentTimestamp           = Get-Date
            HealthScoreChange          = 1
            RedFindingChange           = 0
            YellowFindingChange        = 1
            UnknownFindingChange       = 0
            CriticalFindingChange      = 0
            HighFindingChange          = 0
            MaintenanceReadinessChange = 'Unchanged'
            RiskTrend                  = 'Worsening'
            SummaryMessage             = 'Trend Indicator: Failure Risk appears to be increasing compared with the previous snapshot.'
        }

        $script:ComponentRisk = @(
            [pscustomobject]@{
                TargetName        = 'TEST-SERVER'
                TargetType        = 'Local'
                ComponentCategory = 'Storage'
                ComponentName     = 'Logical Disk C:'
                RiskLevel         = 'Medium'
                RiskScore         = 2
                EvidenceCount     = 1
                EvidenceSummary   = 'Drive C: free space is below warning threshold.'
                Recommendation    = 'Review storage capacity before maintenance.'
                ConfidenceLevel   = 'High'
            }
        )
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:OutputPath) {
            Remove-Item -LiteralPath $script:OutputPath -Recurse -Force
        }
    }

    It 'creates a timestamped report file path with the expected pattern' {
        $path = New-ReportFileName -Prefix 'local-health-report' -Extension 'html' -OutputPath $script:OutputPath

        Split-Path -Parent $path | Should -Be $script:OutputPath
        Split-Path -Leaf $path | Should -Match '^local-health-report-\d{8}-\d{6}\.html$'
    }

    It 'exports a JSON health report' {
        $path = Export-HealthJsonReport -RawResult $script:RawResult -Findings $script:Findings -OverallScore $script:OverallScore -MaintenanceReadiness $script:MaintenanceReadiness -OutputPath $script:OutputPath

        Test-Path -LiteralPath $path | Should -Be $true
        $json = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $json.ReportType | Should -Be 'LocalHealthFindings'
        $json.Findings.Count | Should -Be 2
    }

    It 'exports a CSV findings report' {
        $path = Export-HealthCsvReport -Findings $script:Findings -OutputPath $script:OutputPath

        Test-Path -LiteralPath $path | Should -Be $true
        $csv = Import-Csv -LiteralPath $path
        $csv.Count | Should -Be 2
        (@($csv[0].PSObject.Properties.Name) -contains 'Evidence') | Should -Be $true
    }

    It 'exports an HTML report with required sections' {
        $path = Export-HealthHtmlReport -RawResult $script:RawResult -Findings $script:Findings -OverallScore $script:OverallScore -MaintenanceReadiness $script:MaintenanceReadiness -OutputPath $script:OutputPath

        Test-Path -LiteralPath $path | Should -Be $true
        $html = Get-Content -LiteralPath $path -Raw
        $html | Should -Match 'Server Health Sentinel'
        $html | Should -Match 'Executive Summary'
        $html | Should -Match 'Maintenance Readiness'
        $html | Should -Match 'Predictive Maintenance'
        $html | Should -Match 'Findings'
    }

    It 'exports an HTML report with trend history and component risk summary' {
        $path = Export-HealthHtmlReport -RawResult $script:RawResult -Findings $script:Findings -OverallScore $script:OverallScore -MaintenanceReadiness $script:MaintenanceReadiness -OutputPath $script:OutputPath -TrendComparison $script:TrendComparison -ComponentRisk $script:ComponentRisk

        Test-Path -LiteralPath $path | Should -Be $true
        $html = Get-Content -LiteralPath $path -Raw
        $html | Should -Match 'Trend History'
        $html | Should -Match 'Predictive Risk'
        $html | Should -Match 'Component risk summary'
        $html | Should -Match 'Logical Disk C:'
        $html | Should -Match 'rule-based trend indicators'
        $html | Should -Not -Match 'will fail'
        $html | Should -Not -Match 'remaining useful life is'
    }

    It 'exports an OnPrem HTML report with target-aware findings' {
        $rawResults = @(
            [pscustomobject]@{ TargetName = 'LAB-MOCK-01'; TargetType = 'OnPrem'; Timestamp = Get-Date },
            [pscustomobject]@{ TargetName = 'LAB-MOCK-02'; TargetType = 'OnPrem'; Timestamp = Get-Date }
        )
        $findings = @(
            [pscustomobject]@{
                Timestamp       = Get-Date
                TargetName      = 'LAB-MOCK-01'
                TargetType      = 'OnPrem'
                Category        = 'Connectivity'
                CheckName       = 'Remote Connectivity'
                Status          = 'Green'
                Severity        = 'Informational'
                Message         = 'Remote connectivity is available.'
                Recommendation  = 'Continue monitoring.'
                Evidence        = [pscustomobject]@{ CimAvailable = $true }
                ConfidenceLevel = 'Medium'
            },
            [pscustomobject]@{
                Timestamp       = Get-Date
                TargetName      = 'LAB-MOCK-02'
                TargetType      = 'OnPrem'
                Category        = 'Connectivity'
                CheckName       = 'Server Unreachable'
                Status          = 'Red'
                Severity        = 'Critical'
                Message         = 'Remote health checks could not be completed.'
                Recommendation  = 'Review remote management access.'
                Evidence        = [pscustomobject]@{ CimAvailable = $false }
                ConfidenceLevel = 'High'
            }
        )

        $path = Export-HealthHtmlReport -RawResult $rawResults -Findings $findings -OverallScore $script:OverallScore -MaintenanceReadiness $script:MaintenanceReadiness -OutputPath $script:OutputPath -Prefix 'onprem-health-report'

        Test-Path -LiteralPath $path | Should -Be $true
        Split-Path -Leaf $path | Should -Match '^onprem-health-report-\d{8}-\d{6}\.html$'
        $html = Get-Content -LiteralPath $path -Raw
        $html | Should -Match 'Targets checked'
        $html | Should -Match 'TargetName'
        $html | Should -Match 'TargetType'
        $html | Should -Match 'LAB-MOCK-02'
        $html | Should -Match 'OnPrem'
    }

    It 'exports a Hybrid HTML report from mock Local OnPrem and Azure findings' {
        $rawResult = [pscustomobject]@{
            Mode                = 'Hybrid'
            Timestamp           = Get-Date
            IncludeLocal        = $true
            TotalTargetsChecked = 3
            LocalTargets        = 1
            OnPremTargets       = 1
            AzureVmTargets      = 1
            ModeSummaries       = @(
                [pscustomobject]@{ Mode = 'Local'; Status = 'Completed'; Targets = 1; FindingCount = 1 }
                [pscustomobject]@{ Mode = 'OnPrem'; Status = 'Completed'; Targets = 1; FindingCount = 1 }
                [pscustomobject]@{ Mode = 'Azure'; Status = 'Completed'; Targets = 1; FindingCount = 1 }
            )
            Results             = @()
        }
        $findings = @(
            [pscustomobject]@{
                Timestamp       = Get-Date
                TargetName      = 'LOCALHOST'
                TargetType      = 'Local'
                Category        = 'Storage'
                CheckName       = 'Logical Disk C:'
                Status          = 'Green'
                Severity        = 'Informational'
                Message         = 'Drive C: free space is within threshold.'
                Recommendation  = 'Continue monitoring.'
                Evidence        = [pscustomobject]@{ DriveLetter = 'C:'; FreePercent = 45 }
                ConfidenceLevel = 'High'
            },
            [pscustomobject]@{
                Timestamp       = Get-Date
                TargetName      = 'LAB-FAKE-01'
                TargetType      = 'OnPrem'
                Category        = 'Connectivity'
                CheckName       = 'Server Unreachable'
                Status          = 'Red'
                Severity        = 'Critical'
                Message         = 'Remote health checks could not be completed.'
                Recommendation  = 'Review remote management access.'
                Evidence        = [pscustomobject]@{ CimAvailable = $false }
                ConfidenceLevel = 'High'
            },
            [pscustomobject]@{
                Timestamp       = Get-Date
                TargetName      = 'AZ-VM-01'
                TargetType      = 'AzureVM'
                Category        = 'AzureGuestHealth'
                CheckName       = 'Guest Event Count System'
                Status          = 'Yellow'
                Severity        = 'Medium'
                Message         = 'Guest System log has warning events.'
                Recommendation  = 'Review guest event log errors before maintenance.'
                Evidence        = [pscustomobject]@{ LogName = 'System'; ErrorOrCriticalCount = 2 }
                ConfidenceLevel = 'Medium'
            }
        )
        $overallScore = [pscustomobject]@{
            OverallStatus      = 'Red'
            Score              = 4
            FindingCount       = 3
            RedCount           = 1
            YellowCount        = 1
            GreenCount         = 1
            UnknownCount       = 0
            CriticalCount      = 1
            HighCount          = 0
            MediumCount        = 1
            LowCount           = 0
            InformationalCount = 1
            SummaryMessage     = 'Significant health findings require administrator review before maintenance.'
        }
        $maintenanceReadiness = [pscustomobject]@{
            ReadinessStatus = 'NotReady'
            Reasons         = @('One or more Critical severity findings are present.')
            Recommendation  = 'Resolve or formally accept Not Ready findings before starting maintenance.'
        }

        $path = Export-HealthHtmlReport -RawResult $rawResult -Findings $findings -OverallScore $overallScore -MaintenanceReadiness $maintenanceReadiness -OutputPath $script:OutputPath -Prefix 'hybrid-health-report' -ReportTitle 'Hybrid Health Report'

        Test-Path -LiteralPath $path | Should -Be $true
        Split-Path -Leaf $path | Should -Match '^hybrid-health-report-\d{8}-\d{6}\.html$'
        $html = Get-Content -LiteralPath $path -Raw
        $html | Should -Match 'Hybrid Health Report'
        $html | Should -Match 'Executive Summary'
        $html | Should -Match 'Target Summary'
        $html | Should -Match 'Maintenance Readiness'
        $html | Should -Match 'Predictive Maintenance'
        $html | Should -Match 'Findings'
        $html | Should -Match 'Local'
        $html | Should -Match 'OnPrem'
        $html | Should -Match 'AzureVM'
    }
}
