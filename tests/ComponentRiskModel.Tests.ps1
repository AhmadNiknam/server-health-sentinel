Describe 'ComponentRiskModel' {
    BeforeAll {
        $modulePath = Join-Path $PSScriptRoot '../src/modules/ComponentRiskModel.psm1'
        Import-Module $modulePath -Force

        function New-TestComponentFinding {
            param(
                [string]$TargetName = 'TEST-SERVER',
                [string]$TargetType = 'Local',
                [string]$Category = 'Storage',
                [string]$CheckName = 'Logical Disk C:',
                [string]$Status = 'Yellow',
                [string]$Severity = 'Medium',
                [string]$Message = 'Test finding.',
                [string]$ConfidenceLevel = 'High'
            )

            [pscustomobject]@{
                Timestamp       = Get-Date
                TargetName      = $TargetName
                TargetType      = $TargetType
                Category        = $Category
                CheckName       = $CheckName
                Status          = $Status
                Severity        = $Severity
                Message         = $Message
                Recommendation  = 'Review this finding.'
                Evidence        = ''
                ConfidenceLevel = $ConfidenceLevel
            }
        }
    }

    It 'creates High or Critical risk for critical storage findings' {
        $findings = @(
            New-TestComponentFinding -Category 'Storage' -CheckName 'Logical Disk C:' -Status 'Red' -Severity 'Critical' -Message 'Drive C: free space is critically low.'
        )

        $risk = @(Get-ComponentRiskScore -Findings $findings)

        $risk.Count | Should -Be 1
        $risk[0].ComponentCategory | Should -Be 'Storage'
        $risk[0].RiskLevel | Should -BeIn @('High', 'Critical')
        $risk[0].RiskScore | Should -BeGreaterOrEqual 4
    }

    It 'creates Medium risk for pending reboot warnings' {
        $findings = @(
            New-TestComponentFinding -Category 'PendingReboot' -CheckName 'Pending Reboot' -Status 'Yellow' -Severity 'Medium' -Message 'Pending reboot indicators were found.'
        )

        $risk = @(Get-ComponentRiskScore -Findings $findings)

        $risk[0].ComponentCategory | Should -Be 'PendingReboot'
        $risk[0].RiskLevel | Should -Be 'Medium'
        $risk[0].RiskScore | Should -Be 2
    }

    It 'creates Unknown risk for unknown hardware sensor status' {
        $findings = @(
            New-TestComponentFinding -Category 'HardwareSensor' -CheckName 'Hardware Sensor Fan' -Status 'Unknown' -Severity 'Unknown' -Message 'Hardware sensor status is unknown.' -ConfidenceLevel 'Unknown'
        )

        $risk = @(Get-ComponentRiskScore -Findings $findings)

        $risk[0].ComponentCategory | Should -Be 'HardwareSensor'
        $risk[0].RiskLevel | Should -Be 'Unknown'
        $risk[0].RiskScore | Should -Be 1
        $risk[0].ConfidenceLevel | Should -Be 'Unknown'
    }
}
