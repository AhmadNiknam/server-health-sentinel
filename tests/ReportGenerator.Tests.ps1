Describe 'ReportGenerator' {
    BeforeAll {
        $modulePath = Join-Path $PSScriptRoot '../src/modules/ReportGenerator.psm1'
        Import-Module $modulePath -Force
    }

    BeforeEach {
        $script:OutputPath = Join-Path ([System.IO.Path]::GetTempPath()) "server-health-sentinel-tests-$([guid]::NewGuid())"
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
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:OutputPath) {
            Remove-Item -LiteralPath $script:OutputPath -Recurse -Force
        }
    }

    It 'creates a timestamped report file path with the expected pattern' {
        $path = New-ReportFileName -Prefix 'local-health-report' -Extension 'html' -OutputPath $script:OutputPath

        Split-Path -Parent $path | Should Be $script:OutputPath
        Split-Path -Leaf $path | Should Match '^local-health-report-\d{8}-\d{6}\.html$'
    }

    It 'exports a JSON health report' {
        $path = Export-HealthJsonReport -RawResult $script:RawResult -Findings $script:Findings -OverallScore $script:OverallScore -MaintenanceReadiness $script:MaintenanceReadiness -OutputPath $script:OutputPath

        Test-Path -LiteralPath $path | Should Be $true
        $json = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $json.ReportType | Should Be 'LocalHealthFindings'
        $json.Findings.Count | Should Be 2
    }

    It 'exports a CSV findings report' {
        $path = Export-HealthCsvReport -Findings $script:Findings -OutputPath $script:OutputPath

        Test-Path -LiteralPath $path | Should Be $true
        $csv = Import-Csv -LiteralPath $path
        $csv.Count | Should Be 2
        (@($csv[0].PSObject.Properties.Name) -contains 'Evidence') | Should Be $true
    }

    It 'exports an HTML report with required sections' {
        $path = Export-HealthHtmlReport -RawResult $script:RawResult -Findings $script:Findings -OverallScore $script:OverallScore -MaintenanceReadiness $script:MaintenanceReadiness -OutputPath $script:OutputPath

        Test-Path -LiteralPath $path | Should Be $true
        $html = Get-Content -LiteralPath $path -Raw
        $html | Should Match 'Server Health Sentinel'
        $html | Should Match 'Executive Summary'
        $html | Should Match 'Maintenance Readiness'
        $html | Should Match 'Predictive Maintenance'
        $html | Should Match 'Findings'
    }
}
