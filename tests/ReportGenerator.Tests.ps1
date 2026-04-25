Describe 'ReportGenerator scaffold' {
    It 'has a ReportGenerator module file' {
        $modulePath = Join-Path $PSScriptRoot '../src/modules/ReportGenerator.psm1'
        if (-not (Test-Path $modulePath)) {
            throw "Expected module file at $modulePath"
        }
    }

    It 'has a reports directory placeholder' {
        $reportPath = Join-Path $PSScriptRoot '../reports/.gitkeep'
        if (-not (Test-Path $reportPath)) {
            throw "Expected reports placeholder at $reportPath"
        }
    }
}
