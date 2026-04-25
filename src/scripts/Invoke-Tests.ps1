<#
.SYNOPSIS
    Runs the Server Health Sentinel Pester test suite.
#>

[CmdletBinding()]
param()

$pesterModule = Get-Module -ListAvailable -Name Pester |
    Where-Object { $_.Version -ge [version]'5.0.0' } |
    Sort-Object Version -Descending |
    Select-Object -First 1

if ($null -eq $pesterModule) {
    throw 'Pester 5 or later is required. Install it with: Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck'
}

Remove-Module -Name Pester -Force -ErrorAction SilentlyContinue
Import-Module $pesterModule.Path -Force

$testResult = Invoke-Pester -Path "$PSScriptRoot/../../tests" -Output Detailed -PassThru
if ($testResult.FailedCount -gt 0) {
    throw "$($testResult.FailedCount) Pester test(s) failed."
}
