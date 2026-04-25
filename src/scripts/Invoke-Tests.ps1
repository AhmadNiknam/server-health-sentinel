<#
.SYNOPSIS
    Runs the Server Health Sentinel Pester test suite.
#>

[CmdletBinding()]
param()

Invoke-Pester -Path "$PSScriptRoot/../../tests"
