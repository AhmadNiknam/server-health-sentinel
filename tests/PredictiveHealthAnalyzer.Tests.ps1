Describe 'PredictiveHealthAnalyzer' {
    BeforeAll {
        $modulePath = Join-Path $PSScriptRoot '../src/modules/PredictiveHealthAnalyzer.psm1'
        Import-Module $modulePath -Force

        function New-TestPredictiveFinding {
            param(
                [string]$Category = 'Storage',
                [string]$CheckName = 'Logical Disk C:',
                [string]$Status = 'Yellow',
                [string]$Severity = 'Medium',
                [string]$Message = 'Test finding.'
            )

            [pscustomobject]@{
                Timestamp       = Get-Date
                TargetName      = 'TEST-SERVER'
                TargetType      = 'Local'
                Category        = $Category
                CheckName       = $CheckName
                Status          = $Status
                Severity        = $Severity
                Message         = $Message
                Recommendation  = 'Review this finding.'
                Evidence        = ''
                ConfidenceLevel = 'High'
            }
        }
    }

    It 'has sample predictive rules' {
        $rulesPath = Join-Path $PSScriptRoot '../config/predictive-rules.sample.json'
        if (-not (Test-Path $rulesPath)) {
            throw "Expected sample predictive rules at $rulesPath"
        }
    }

    It 'creates predictive risk indicators for storage findings' {
        $findings = @(
            New-TestPredictiveFinding -Category 'Storage' -CheckName 'Logical Disk C:' -Status 'Red' -Severity 'Critical' -Message 'Drive C: free space is critically low.'
        )

        $indicators = @(Get-PredictiveRiskIndicators -Findings $findings)

        $indicators.Count | Should -Be 1
        $indicators[0].ComponentCategory | Should -Be 'Storage'
        $indicators[0].RiskLevel | Should -Be 'Critical'
        $indicators[0].Message | Should -Match 'Early Warning'
    }

    It 'creates predictive risk indicators for network findings' {
        $findings = @(
            New-TestPredictiveFinding -Category 'Network' -CheckName 'Network Adapter Ethernet' -Status 'Yellow' -Severity 'Medium' -Message 'Network adapter is disconnected or degraded.'
        )

        $indicators = @(Get-PredictiveRiskIndicators -Findings $findings)

        $indicators.Count | Should -Be 1
        $indicators[0].ComponentCategory | Should -Be 'Network'
        $indicators[0].RiskLevel | Should -Be 'Medium'
    }

    It 'returns safely with no findings' {
        $indicators = @(Get-PredictiveRiskIndicators -Findings @())

        $indicators.Count | Should -Be 0
    }
}
