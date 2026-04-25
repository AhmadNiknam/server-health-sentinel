Describe 'HealthEvaluator scaffold' {
    It 'has a HealthEvaluator module file' {
        $modulePath = Join-Path $PSScriptRoot '../src/modules/HealthEvaluator.psm1'
        if (-not (Test-Path $modulePath)) {
            throw "Expected module file at $modulePath"
        }
    }
}
