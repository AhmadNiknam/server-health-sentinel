<#
EventLogRiskAnalyzer module.

Planned purpose:
Analyze repeated Windows Event Log errors and warnings as early risk indicators
without claiming exact component failure dates.
#>

function Get-EventLogRiskCategory {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Event
    )

    $storageEventIds = @(55, 98, 129, 153, 157)
    if ($Event.Id -in $storageEventIds) {
        return 'Storage'
    }

    $providerName = [string]$Event.ProviderName
    $message = [string]$Event.Message
    if ($providerName -match 'adapter|network|net|tcpip|ndis|link' -or $message -match 'adapter|network|link|ethernet|nic') {
        return 'Network'
    }

    return 'GeneralEventLog'
}

function Get-LocalEventLogRisk {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Thresholds
    )

    $lookbackHours = [int]$Thresholds.eventLogs.lookbackHours
    $maxEventsPerLog = [int]$Thresholds.eventLogs.maxEventsPerLog
    $monitoredLogs = @($Thresholds.eventLogs.monitoredLogs)
    $startTime = (Get-Date).AddHours(-1 * $lookbackHours)

    foreach ($logName in $monitoredLogs) {
        try {
            $events = @(Get-WinEvent -FilterHashtable @{
                    LogName   = $logName
                    Level     = @(1, 2)
                    StartTime = $startTime
                } -MaxEvents $maxEventsPerLog -ErrorAction Stop)
        }
        catch {
            if ($_.Exception.Message -match 'No events were found') {
                continue
            }

            [pscustomobject]@{
                LogName          = $logName
                EventId          = $null
                LevelDisplayName = 'Unknown'
                ProviderName     = $null
                TimeCreated      = $null
                MessagePreview   = "Unable to read event log '$logName': $($_.Exception.Message)"
                RiskCategory     = 'GeneralEventLog'
                Status           = 'Unknown'
            }
            continue
        }

        foreach ($event in $events) {
            $message = [string]$event.Message
            $messagePreview = if ($message.Length -gt 240) {
                $message.Substring(0, 240)
            }
            else {
                $message
            }

            $status = if ($event.LevelDisplayName -eq 'Critical') {
                'Red'
            }
            else {
                'Yellow'
            }

            [pscustomobject]@{
                LogName          = $event.LogName
                EventId          = $event.Id
                LevelDisplayName = $event.LevelDisplayName
                ProviderName     = $event.ProviderName
                TimeCreated      = $event.TimeCreated
                MessagePreview   = "Risk Indicator: $messagePreview"
                RiskCategory     = Get-EventLogRiskCategory -Event $event
                Status           = $status
            }
        }
    }
}

Export-ModuleMember -Function 'Get-LocalEventLogRisk'
