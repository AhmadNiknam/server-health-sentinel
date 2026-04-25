Describe 'NetworkHealthCollector scaffold' {
    It 'has a NetworkHealthCollector module file' {
        $modulePath = Join-Path $PSScriptRoot '../src/modules/NetworkHealthCollector.psm1'
        if (-not (Test-Path $modulePath)) {
            throw "Expected module file at $modulePath"
        }
    }
}
