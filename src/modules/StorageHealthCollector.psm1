<#
StorageHealthCollector module.

Planned purpose:
Collect read-only logical disk capacity, physical disk health where available,
and storage warning indicators.
#>

$healthEvaluatorPath = Join-Path $PSScriptRoot 'HealthEvaluator.psm1'
if (Test-Path -LiteralPath $healthEvaluatorPath -PathType Leaf) {
    Import-Module $healthEvaluatorPath -Force
}

function Get-LocalLogicalDiskHealth {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Thresholds
    )

    try {
        $disks = @(Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType = 3' -ErrorAction Stop)
    }
    catch {
        return [pscustomobject]@{
            DriveLetter = $null
            VolumeName  = $null
            TotalGB     = $null
            FreeGB      = $null
            FreePercent = $null
            Status      = 'Unknown'
            Message     = "Unable to read local logical disk health: $($_.Exception.Message)"
        }
    }

    foreach ($disk in $disks) {
        $totalGb = if ($disk.Size) { [math]::Round(($disk.Size / 1GB), 2) } else { 0 }
        $freeGb = if ($disk.FreeSpace) { [math]::Round(($disk.FreeSpace / 1GB), 2) } else { 0 }
        $freePercent = if ($disk.Size -gt 0) { [math]::Round((($disk.FreeSpace / $disk.Size) * 100), 2) } else { $null }
        $status = Get-BasicHealthStatus `
            -Value $freePercent `
            -WarningThreshold $Thresholds.logicalDisk.warningFreePercent `
            -CriticalThreshold $Thresholds.logicalDisk.criticalFreePercent `
            -ComparisonType LessThan

        $message = switch ($status) {
            'Green' { "Drive $($disk.DeviceID) free space is within threshold." }
            'Yellow' { "Drive $($disk.DeviceID) free space is below warning threshold." }
            'Red' { "Drive $($disk.DeviceID) free space is below critical threshold." }
            default { "Drive $($disk.DeviceID) free space status could not be evaluated." }
        }

        [pscustomobject]@{
            DriveLetter = $disk.DeviceID
            VolumeName  = $disk.VolumeName
            TotalGB     = $totalGb
            FreeGB      = $freeGb
            FreePercent = $freePercent
            Status      = $status
            Message     = $message
        }
    }
}

function Get-LocalPhysicalDiskHealth {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Thresholds
    )

    if (-not (Get-Command -Name Get-PhysicalDisk -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{
            FriendlyName      = $null
            MediaType         = $null
            HealthStatus      = 'Unknown'
            OperationalStatus = $null
            SizeGB            = $null
            Status            = 'Unknown'
            Message           = 'Get-PhysicalDisk is not available on this system.'
        }
    }

    try {
        $physicalDisks = @(Get-PhysicalDisk -ErrorAction Stop)
    }
    catch {
        return [pscustomobject]@{
            FriendlyName      = $null
            MediaType         = $null
            HealthStatus      = 'Unknown'
            OperationalStatus = $null
            SizeGB            = $null
            Status            = 'Unknown'
            Message           = "Unable to read local physical disk health: $($_.Exception.Message)"
        }
    }

    foreach ($disk in $physicalDisks) {
        $healthStatus = [string]$disk.HealthStatus
        $warningStates = @($Thresholds.physicalDisk.warningHealthStates)
        $criticalStates = @($Thresholds.physicalDisk.criticalHealthStates)

        $status = if ($healthStatus -in $criticalStates) {
            'Red'
        }
        elseif ($healthStatus -in $warningStates) {
            'Yellow'
        }
        elseif ($healthStatus -eq 'Healthy') {
            'Green'
        }
        else {
            'Unknown'
        }

        $message = switch ($status) {
            'Green' { "Physical disk '$($disk.FriendlyName)' reports healthy status." }
            'Yellow' { "Physical disk '$($disk.FriendlyName)' reports a warning health state." }
            'Red' { "Physical disk '$($disk.FriendlyName)' reports a critical health state." }
            default { "Physical disk '$($disk.FriendlyName)' health state could not be evaluated." }
        }

        [pscustomobject]@{
            FriendlyName      = $disk.FriendlyName
            MediaType         = $disk.MediaType
            HealthStatus      = $disk.HealthStatus
            OperationalStatus = @($disk.OperationalStatus) -join ', '
            SizeGB            = if ($disk.Size) { [math]::Round(($disk.Size / 1GB), 2) } else { $null }
            Status            = $status
            Message           = $message
        }
    }
}

function Invoke-LocalStorageHealthCheck {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Thresholds
    )

    [pscustomobject]@{
        LogicalDisks  = @(Get-LocalLogicalDiskHealth -Thresholds $Thresholds)
        PhysicalDisks = @(Get-LocalPhysicalDiskHealth -Thresholds $Thresholds)
    }
}

Export-ModuleMember -Function @(
    'Get-LocalLogicalDiskHealth',
    'Get-LocalPhysicalDiskHealth',
    'Invoke-LocalStorageHealthCheck'
)
