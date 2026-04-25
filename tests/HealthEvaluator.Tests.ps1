Describe 'HealthEvaluator' {
    BeforeAll {
        $script:ModulePath = Join-Path $PSScriptRoot '../src/modules/HealthEvaluator.psm1'
        Import-Module $script:ModulePath -Force
    }

    It 'returns Green for values below a greater-than warning threshold' {
        Get-BasicHealthStatus -Value 25 -WarningThreshold 80 -CriticalThreshold 95 -ComparisonType GreaterThan | Should -Be 'Green'
    }

    It 'returns Yellow for values above a greater-than warning threshold' {
        Get-BasicHealthStatus -Value 85 -WarningThreshold 80 -CriticalThreshold 95 -ComparisonType GreaterThan | Should -Be 'Yellow'
    }

    It 'returns Red for values above a greater-than critical threshold' {
        Get-BasicHealthStatus -Value 96 -WarningThreshold 80 -CriticalThreshold 95 -ComparisonType GreaterThan | Should -Be 'Red'
    }

    It 'returns Red for values below a less-than critical threshold' {
        Get-BasicHealthStatus -Value 8 -WarningThreshold 20 -CriticalThreshold 10 -ComparisonType LessThan | Should -Be 'Red'
    }

    It 'returns Unknown when inputs cannot be evaluated' {
        Get-BasicHealthStatus -Value $null -WarningThreshold 20 -CriticalThreshold 10 -ComparisonType LessThan | Should -Be 'Unknown'
    }
}
