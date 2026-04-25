<#
.SYNOPSIS
    Runs PSScriptAnalyzer against the Server Health Sentinel source tree.
#>

[CmdletBinding()]
param()

Invoke-ScriptAnalyzer -Path "$PSScriptRoot/.." -Recurse
