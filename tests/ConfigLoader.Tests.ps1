Describe 'ConfigLoader scaffold' {
    It 'has a ConfigLoader module file' {
        $modulePath = Join-Path $PSScriptRoot '../src/modules/ConfigLoader.psm1'
        if (-not (Test-Path $modulePath)) {
            throw "Expected module file at $modulePath"
        }
    }

    It 'has sample configuration files' {
        $configPath = Join-Path $PSScriptRoot '../config'
        $serverSamplePath = Join-Path $configPath 'servers.sample.csv'
        $thresholdSamplePath = Join-Path $configPath 'thresholds.sample.json'

        if (-not (Test-Path $serverSamplePath)) {
            throw "Expected sample server config at $serverSamplePath"
        }

        if (-not (Test-Path $thresholdSamplePath)) {
            throw "Expected sample threshold config at $thresholdSamplePath"
        }
    }
}
