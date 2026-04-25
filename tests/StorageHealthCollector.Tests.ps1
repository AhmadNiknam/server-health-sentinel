Describe 'StorageHealthCollector scaffold' {
    It 'has a StorageHealthCollector module file' {
        $modulePath = Join-Path $PSScriptRoot '../src/modules/StorageHealthCollector.psm1'
        if (-not (Test-Path $modulePath)) {
            throw "Expected module file at $modulePath"
        }
    }
}
