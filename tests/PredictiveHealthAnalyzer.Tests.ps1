Describe 'PredictiveHealthAnalyzer scaffold' {
    It 'has a PredictiveHealthAnalyzer module file' {
        $modulePath = Join-Path $PSScriptRoot '../src/modules/PredictiveHealthAnalyzer.psm1'
        if (-not (Test-Path $modulePath)) {
            throw "Expected module file at $modulePath"
        }
    }

    It 'has sample predictive rules' {
        $rulesPath = Join-Path $PSScriptRoot '../config/predictive-rules.sample.json'
        if (-not (Test-Path $rulesPath)) {
            throw "Expected sample predictive rules at $rulesPath"
        }
    }
}
