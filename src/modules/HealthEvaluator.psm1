<#
HealthEvaluator module.

Planned purpose:
Evaluate collector output against thresholds and produce normalized health
states for reports.
#>

function Get-BasicHealthStatus {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value,

        [AllowNull()]
        [object]$WarningThreshold,

        [AllowNull()]
        [object]$CriticalThreshold,

        [Parameter(Mandatory)]
        [ValidateSet('GreaterThan', 'LessThan')]
        [string]$ComparisonType
    )

    if ($null -eq $Value -or $null -eq $WarningThreshold -or $null -eq $CriticalThreshold) {
        return 'Unknown'
    }

    try {
        $numericValue = [double]$Value
        $numericWarning = [double]$WarningThreshold
        $numericCritical = [double]$CriticalThreshold
    }
    catch {
        return 'Unknown'
    }

    switch ($ComparisonType) {
        'GreaterThan' {
            if ($numericValue -ge $numericCritical) {
                return 'Red'
            }

            if ($numericValue -ge $numericWarning) {
                return 'Yellow'
            }

            return 'Green'
        }
        'LessThan' {
            if ($numericValue -le $numericCritical) {
                return 'Red'
            }

            if ($numericValue -le $numericWarning) {
                return 'Yellow'
            }

            return 'Green'
        }
    }
}

Export-ModuleMember -Function 'Get-BasicHealthStatus'
