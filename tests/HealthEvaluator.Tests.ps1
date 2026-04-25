Describe 'HealthEvaluator' {
    BeforeAll {
        $script:ModulePath = Join-Path $PSScriptRoot '../src/modules/HealthEvaluator.psm1'
        Import-Module $script:ModulePath -Force

        function New-TestFinding {
            param(
                [string]$Category = 'CPU',
                [string]$CheckName = 'CPU Usage',
                [string]$Status = 'Green',
                [string]$Severity = 'Informational',
                [object]$Evidence = ''
            )

            New-HealthFinding `
                -TargetName 'TEST-SERVER' `
                -TargetType 'Local' `
                -Category $Category `
                -CheckName $CheckName `
                -Status $Status `
                -Severity $Severity `
                -Message 'Test finding.' `
                -Recommendation 'Review this finding.' `
                -Evidence $Evidence `
                -ConfidenceLevel 'High'
        }

        $script:MockLocalHealthResult = [pscustomobject]@{
            TargetName    = 'TEST-SERVER'
            TargetType    = 'Local'
            Timestamp     = Get-Date
            OsHealth      = [pscustomobject]@{
                Cpu              = [pscustomobject]@{
                    Category   = 'OS'
                    CheckName  = 'CPU Usage'
                    TargetName = 'TEST-SERVER'
                    Value      = 20
                    Unit       = 'Percent'
                    Status     = 'Green'
                    Message    = 'CPU usage is within threshold.'
                    Evidence   = 'CPU counter'
                }
                Memory           = [pscustomobject]@{
                    Category   = 'OS'
                    CheckName  = 'Memory Usage'
                    TargetName = 'TEST-SERVER'
                    Value      = 91
                    Unit       = 'Percent'
                    Status     = 'Yellow'
                    Message    = 'Memory usage is above warning threshold.'
                    Evidence   = [pscustomobject]@{ TotalGB = 16; FreeGB = 1.4 }
                }
                CriticalServices = @(
                    [pscustomobject]@{
                        Category   = 'OS'
                        CheckName  = 'Critical Service'
                        TargetName = 'TEST-SERVER'
                        Value      = 'Running'
                        Unit       = 'ServiceStatus'
                        Status     = 'Green'
                        Message    = "Critical service 'Spooler' is running."
                        Evidence   = [pscustomobject]@{ ServiceName = 'Spooler'; DisplayName = 'Print Spooler' }
                    }
                )
            }
            StorageHealth = [pscustomobject]@{
                LogicalDisks  = @(
                    [pscustomobject]@{
                        DriveLetter = 'C:'
                        VolumeName  = 'System'
                        TotalGB     = 100
                        FreeGB      = 8
                        FreePercent = 8
                        Status      = 'Yellow'
                        Message     = 'Drive C: free space is below warning threshold.'
                    }
                )
                PhysicalDisks = @(
                    [pscustomobject]@{
                        FriendlyName      = 'Disk0'
                        MediaType         = 'SSD'
                        HealthStatus      = 'Healthy'
                        OperationalStatus = 'OK'
                        SizeGB            = 256
                        Status            = 'Green'
                        Message           = "Physical disk 'Disk0' reports healthy status."
                    }
                )
            }
            NetworkHealth = [pscustomobject]@{
                Adapters = @(
                    [pscustomobject]@{
                        Name                 = 'Ethernet'
                        InterfaceDescription = 'Test Adapter'
                        Status               = 'Up'
                        LinkSpeed            = '1 Gbps'
                        MacAddress           = '00-00-00-00-00-00'
                        StatusEvaluation     = 'Green'
                        Message              = "Network adapter 'Ethernet' is up."
                    }
                )
            }
            EventLogRisk  = @(
                [pscustomobject]@{ LogName = 'System'; EventId = 129; LevelDisplayName = 'Error'; ProviderName = 'disk'; TimeCreated = Get-Date; MessagePreview = 'Risk Indicator: Reset to device.'; RiskCategory = 'Storage'; Status = 'Yellow' },
                [pscustomobject]@{ LogName = 'System'; EventId = 129; LevelDisplayName = 'Error'; ProviderName = 'disk'; TimeCreated = Get-Date; MessagePreview = 'Risk Indicator: Reset to device.'; RiskCategory = 'Storage'; Status = 'Yellow' },
                [pscustomobject]@{ LogName = 'System'; EventId = 5002; LevelDisplayName = 'Error'; ProviderName = 'Tcpip'; TimeCreated = Get-Date; MessagePreview = 'Risk Indicator: Network warning.'; RiskCategory = 'Network'; Status = 'Yellow' }
            )
            PendingReboot = [pscustomobject]@{
                IsPendingReboot = $true
                Reasons         = @('Windows Update reboot required')
                Status          = 'Yellow'
                Message         = 'Pending reboot indicators were found.'
            }
        }
    }

    It 'creates a health finding with the expected object structure and safe defaults' {
        $finding = New-HealthFinding -TargetName 'TEST-SERVER' -TargetType 'Local' -Category 'CPU' -CheckName 'CPU Usage' -Message 'OK'

        $expectedPropertyNames = @(
            'Timestamp'
            'TargetName'
            'TargetType'
            'Category'
            'CheckName'
            'Status'
            'Severity'
            'Message'
            'Recommendation'
            'Evidence'
            'ConfidenceLevel'
        )
        $propertyNames = @($finding.PSObject.Properties.Name)

        ($propertyNames -join ',') | Should -Be ($expectedPropertyNames -join ',')
        $finding.Status | Should -Be 'Unknown'
        $finding.Severity | Should -Be 'Unknown'
        $finding.ConfidenceLevel | Should -Be 'Unknown'
        $finding.Recommendation | Should -Be 'Review this finding.'
    }

    It 'returns Green for greater-than values below the warning threshold' {
        Get-BasicHealthStatus -Value 50 -WarningThreshold 80 -CriticalThreshold 90 -ComparisonType GreaterThan | Should -Be 'Green'
    }

    It 'returns Yellow for greater-than values at or above warning and below critical' {
        Get-BasicHealthStatus -Value 85 -WarningThreshold 80 -CriticalThreshold 90 -ComparisonType GreaterThan | Should -Be 'Yellow'
    }

    It 'returns Red for greater-than values at or above the critical threshold' {
        Get-BasicHealthStatus -Value 95 -WarningThreshold 80 -CriticalThreshold 90 -ComparisonType GreaterThan | Should -Be 'Red'
    }

    It 'returns Green for less-than values above the warning threshold' {
        Get-BasicHealthStatus -Value 30 -WarningThreshold 20 -CriticalThreshold 10 -ComparisonType LessThan | Should -Be 'Green'
    }

    It 'returns Yellow for less-than values at or below warning and above critical' {
        Get-BasicHealthStatus -Value 15 -WarningThreshold 20 -CriticalThreshold 10 -ComparisonType LessThan | Should -Be 'Yellow'
    }

    It 'returns Red for less-than values at or below the critical threshold' {
        Get-BasicHealthStatus -Value 5 -WarningThreshold 20 -CriticalThreshold 10 -ComparisonType LessThan | Should -Be 'Red'
    }

    It 'returns Unknown when inputs cannot be evaluated' {
        Get-BasicHealthStatus -Value $null -WarningThreshold 20 -CriticalThreshold 10 -ComparisonType LessThan | Should -Be 'Unknown'
    }

    It 'returns Green overall health for clean findings' {
        $findings = @(
            New-TestFinding -Category 'CPU' -CheckName 'CPU Usage' -Status 'Green' -Severity 'Informational'
            New-TestFinding -Category 'Memory' -CheckName 'Memory Usage' -Status 'Green' -Severity 'Informational'
        )
        $score = Get-OverallHealthScore -Findings $findings

        $score.OverallStatus | Should -Be 'Green'
        $score.Score | Should -Be 0
        $score.GreenCount | Should -Be 2
    }

    It 'returns Yellow overall health for warning findings' {
        $findings = @(
            New-TestFinding -Category 'CPU' -CheckName 'CPU Usage' -Status 'Green' -Severity 'Informational'
            New-TestFinding -Category 'Memory' -CheckName 'Memory Usage' -Status 'Yellow' -Severity 'Medium'
        )
        $score = Get-OverallHealthScore -Findings $findings

        $score.OverallStatus | Should -Be 'Yellow'
        $score.Score | Should -Be 1
        $score.YellowCount | Should -Be 1
    }

    It 'returns Red overall health when score is high' {
        $findings = @(
            New-TestFinding -Category 'CPU' -CheckName 'CPU Usage' -Status 'Red' -Severity 'High'
            New-TestFinding -Category 'Memory' -CheckName 'Memory Usage' -Status 'Red' -Severity 'High'
        )
        $score = Get-OverallHealthScore -Findings $findings

        $score.OverallStatus | Should -Be 'Red'
        $score.Score | Should -Be 6
    }

    It 'returns Red overall health when a Critical severity finding exists' {
        $findings = @(
            New-TestFinding -Category 'CriticalService' -CheckName 'Critical Service Test' -Status 'Yellow' -Severity 'Critical'
        )
        $score = Get-OverallHealthScore -Findings $findings

        $score.OverallStatus | Should -Be 'Red'
        $score.CriticalCount | Should -Be 1
    }

    It 'returns Ready when there are no maintenance blockers' {
        $findings = @(
            New-TestFinding -Category 'CPU' -CheckName 'CPU Usage' -Status 'Green' -Severity 'Informational'
            New-TestFinding -Category 'Storage' -CheckName 'Logical Disk C:' -Status 'Green' -Severity 'Informational'
        )
        $readiness = Get-MaintenanceReadinessStatus -Findings $findings

        $readiness.ReadinessStatus | Should -Be 'Ready'
    }

    It 'returns ReviewRequired for warning maintenance signals' {
        $findings = @(
            New-TestFinding -Category 'PendingReboot' -CheckName 'Pending Reboot' -Status 'Yellow' -Severity 'Medium'
            New-TestFinding -Category 'Storage' -CheckName 'Logical Disk C:' -Status 'Yellow' -Severity 'Medium'
            New-TestFinding -Category 'EventLog:Storage' -CheckName 'Event Log Risk 129' -Status 'Yellow' -Severity 'Medium'
            New-TestFinding -Category 'EventLog:Network' -CheckName 'Event Log Risk 5002' -Status 'Yellow' -Severity 'Medium'
        )

        $readiness = Get-MaintenanceReadinessStatus -Findings $findings

        $readiness.ReadinessStatus | Should -Be 'ReviewRequired'
        $readiness.Reasons | Should -Contain 'Pending reboot status is Yellow.'
        $readiness.Reasons | Should -Contain 'Disk free space is Yellow.'
        $readiness.Reasons | Should -Contain 'Multiple event log risk indicators are present.'
    }

    It 'returns NotReady for critical maintenance blockers' {
        $findings = @(
            New-TestFinding -Category 'Storage' -CheckName 'Logical Disk C:' -Status 'Red' -Severity 'Critical'
            New-TestFinding -Category 'PendingReboot' -CheckName 'Pending Reboot' -Status 'Red' -Severity 'Critical'
            New-TestFinding -Category 'CriticalService' -CheckName 'Critical Service Test' -Status 'Red' -Severity 'Critical'
        )

        $readiness = Get-MaintenanceReadinessStatus -Findings $findings

        $readiness.ReadinessStatus | Should -Be 'NotReady'
        $readiness.Reasons | Should -Contain 'One or more Critical severity findings are present.'
        $readiness.Reasons | Should -Contain 'A Red disk or storage finding is present.'
        $readiness.Reasons | Should -Contain 'Pending reboot status is Red.'
        $readiness.Reasons | Should -Contain 'A critical service finding is Red.'
    }

    It 'groups event log risk findings by category, log, event ID, and provider' {
        $findings = @(Convert-LocalHealthResultToFindings -LocalHealthResult $script:MockLocalHealthResult)
        $eventFindings = @($findings | Where-Object { $_.Category -like 'EventLog:*' })
        $diskEvent = $eventFindings | Where-Object { $_.Evidence.EventId -eq 129 -and $_.Evidence.ProviderName -eq 'disk' }

        $eventFindings.Count | Should -Be 2
        $diskEvent.Evidence.Count | Should -Be 2
    }
}
