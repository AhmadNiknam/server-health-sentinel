Describe 'HealthEvaluator' {
    BeforeAll {
        $script:ModulePath = Join-Path $PSScriptRoot '../src/modules/HealthEvaluator.psm1'
        Import-Module $script:ModulePath -Force

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

    It 'returns Green for values below a greater-than warning threshold' {
        Get-BasicHealthStatus -Value 25 -WarningThreshold 80 -CriticalThreshold 95 -ComparisonType GreaterThan | Should Be 'Green'
    }

    It 'returns Yellow for values above a greater-than warning threshold' {
        Get-BasicHealthStatus -Value 85 -WarningThreshold 80 -CriticalThreshold 95 -ComparisonType GreaterThan | Should Be 'Yellow'
    }

    It 'returns Red for values above a greater-than critical threshold' {
        Get-BasicHealthStatus -Value 96 -WarningThreshold 80 -CriticalThreshold 95 -ComparisonType GreaterThan | Should Be 'Red'
    }

    It 'returns Red for values below a less-than critical threshold' {
        Get-BasicHealthStatus -Value 8 -WarningThreshold 20 -CriticalThreshold 10 -ComparisonType LessThan | Should Be 'Red'
    }

    It 'returns Unknown when inputs cannot be evaluated' {
        Get-BasicHealthStatus -Value $null -WarningThreshold 20 -CriticalThreshold 10 -ComparisonType LessThan | Should Be 'Unknown'
    }

    It 'creates a health finding with the expected object structure' {
        $finding = New-HealthFinding -TargetName 'TEST-SERVER' -TargetType 'Local' -Category 'CPU' -CheckName 'CPU Usage' -Status 'Green' -Severity 'Informational' -Message 'OK' -Recommendation 'Continue monitoring.' -Evidence 'sample evidence' -ConfidenceLevel 'High'

        $propertyNames = @($finding.PSObject.Properties.Name)
        ($propertyNames -contains 'Timestamp') | Should Be $true
        ($propertyNames -contains 'TargetName') | Should Be $true
        ($propertyNames -contains 'TargetType') | Should Be $true
        ($propertyNames -contains 'Category') | Should Be $true
        ($propertyNames -contains 'CheckName') | Should Be $true
        ($propertyNames -contains 'Status') | Should Be $true
        ($propertyNames -contains 'Severity') | Should Be $true
        ($propertyNames -contains 'Message') | Should Be $true
        ($propertyNames -contains 'Recommendation') | Should Be $true
        ($propertyNames -contains 'Evidence') | Should Be $true
        ($propertyNames -contains 'ConfidenceLevel') | Should Be $true
        $finding.Status | Should Be 'Green'
    }

    It 'calculates overall health score from statuses and severity' {
        $findings = @(
            New-HealthFinding -TargetName 'TEST-SERVER' -TargetType 'Local' -Category 'CPU' -CheckName 'CPU Usage' -Status 'Green' -Severity 'Informational' -Message 'OK' -Recommendation 'Continue monitoring.' -Evidence $null -ConfidenceLevel 'High'
            New-HealthFinding -TargetName 'TEST-SERVER' -TargetType 'Local' -Category 'Memory' -CheckName 'Memory Usage' -Status 'Yellow' -Severity 'Medium' -Message 'Review' -Recommendation 'Review memory.' -Evidence $null -ConfidenceLevel 'High'
            New-HealthFinding -TargetName 'TEST-SERVER' -TargetType 'Local' -Category 'Storage' -CheckName 'Logical Disk C:' -Status 'Red' -Severity 'High' -Message 'Low disk' -Recommendation 'Review disk.' -Evidence $null -ConfidenceLevel 'High'
        )

        $score = Get-OverallHealthScore -Findings $findings

        $score.Score | Should Be 4
        $score.OverallStatus | Should Be 'Yellow'
        $score.RedCount | Should Be 1
        $score.YellowCount | Should Be 1
    }

    It 'returns Red overall status when a Critical severity finding exists' {
        $findings = @(
            New-HealthFinding -TargetName 'TEST-SERVER' -TargetType 'Local' -Category 'CriticalService' -CheckName 'Critical Service Test' -Status 'Red' -Severity 'Critical' -Message 'Stopped' -Recommendation 'Review service.' -Evidence $null -ConfidenceLevel 'High'
        )

        $score = Get-OverallHealthScore -Findings $findings

        $score.OverallStatus | Should Be 'Red'
        $score.CriticalCount | Should Be 1
    }

    It 'returns NotReady for critical maintenance blockers' {
        $findings = @(
            New-HealthFinding -TargetName 'TEST-SERVER' -TargetType 'Local' -Category 'Storage' -CheckName 'Logical Disk C:' -Status 'Red' -Severity 'Critical' -Message 'Low disk' -Recommendation 'Review disk.' -Evidence $null -ConfidenceLevel 'High'
        )

        $readiness = Get-MaintenanceReadinessStatus -Findings $findings

        $readiness.ReadinessStatus | Should Be 'NotReady'
        ($readiness.Reasons.Count -gt 0) | Should Be $true
    }

    It 'returns ReviewRequired for warning maintenance signals' {
        $findings = @(
            New-HealthFinding -TargetName 'TEST-SERVER' -TargetType 'Local' -Category 'PendingReboot' -CheckName 'Pending Reboot' -Status 'Yellow' -Severity 'Medium' -Message 'Pending' -Recommendation 'Plan reboot.' -Evidence $null -ConfidenceLevel 'High'
        )

        $readiness = Get-MaintenanceReadinessStatus -Findings $findings

        $readiness.ReadinessStatus | Should Be 'ReviewRequired'
    }

    It 'groups event log risk findings by category, log, event ID, and provider' {
        $findings = @(Convert-LocalHealthResultToFindings -LocalHealthResult $script:MockLocalHealthResult)
        $eventFindings = @($findings | Where-Object { $_.Category -like 'EventLog:*' })
        $diskEvent = $eventFindings | Where-Object { $_.Evidence.EventId -eq 129 -and $_.Evidence.ProviderName -eq 'disk' }

        $eventFindings.Count | Should Be 2
        $diskEvent.Evidence.Count | Should Be 2
    }
}
