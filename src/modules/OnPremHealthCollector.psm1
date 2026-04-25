<#
OnPremHealthCollector module.

Planned purpose:
Coordinate read-only health checks against on-prem Windows servers through
approved remote CIM or WinRM connections.
#>

$healthEvaluatorPath = Join-Path $PSScriptRoot 'HealthEvaluator.psm1'
if (Test-Path -LiteralPath $healthEvaluatorPath -PathType Leaf) {
    Import-Module $healthEvaluatorPath -Force
}

function Get-OnPremHighestHealthStatus {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object[]]$Statuses
    )

    $statusList = @($Statuses | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($statusList -contains 'Red') { return 'Red' }
    if ($statusList -contains 'Yellow') { return 'Yellow' }
    if ($statusList -contains 'Unknown') { return 'Unknown' }
    return 'Green'
}

function Split-OnPremCriticalServiceNames {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InventoryRow,

        [AllowNull()]
        [object]$Thresholds
    )

    $rowServices = if ($null -ne $InventoryRow -and -not [string]::IsNullOrWhiteSpace([string]$InventoryRow.CriticalServices)) {
        @(([string]$InventoryRow.CriticalServices) -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }
    else {
        @()
    }

    if ($rowServices.Count -gt 0) {
        return $rowServices
    }

    return @($Thresholds.services.defaultCriticalServices)
}

function Test-OnPremServerConnectivity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServerName
    )

    $dnsResolved = $false
    $pingSucceeded = $false
    $cimAvailable = $false
    $evidence = [ordered]@{
        Dns       = $null
        Ping      = $null
        CimOrWsMan = $null
    }

    try {
        if (Get-Command -Name Resolve-DnsName -ErrorAction SilentlyContinue) {
            $dnsRecords = @(Resolve-DnsName -Name $ServerName -ErrorAction Stop)
            $dnsResolved = $dnsRecords.Count -gt 0
            $evidence.Dns = "Resolved $($dnsRecords.Count) DNS record(s)."
        }
        else {
            $addresses = [System.Net.Dns]::GetHostAddresses($ServerName)
            $dnsResolved = @($addresses).Count -gt 0
            $evidence.Dns = "Resolved $(@($addresses).Count) address(es)."
        }
    }
    catch {
        $evidence.Dns = "DNS resolution failed: $($_.Exception.Message)"
    }

    try {
        $pingSucceeded = [bool](Test-Connection -ComputerName $ServerName -Count 1 -Quiet -ErrorAction Stop)
        $evidence.Ping = if ($pingSucceeded) { 'ICMP ping succeeded.' } else { 'ICMP ping did not receive a reply.' }
    }
    catch {
        $evidence.Ping = "ICMP ping could not be completed: $($_.Exception.Message)"
    }

    try {
        if (Get-Command -Name Test-WSMan -ErrorAction SilentlyContinue) {
            $null = Test-WSMan -ComputerName $ServerName -ErrorAction Stop
            $cimAvailable = $true
            $evidence.CimOrWsMan = 'WinRM responded to Test-WSMan.'
        }
        else {
            $testSession = New-CimSession -ComputerName $ServerName -ErrorAction Stop
            $null = Get-CimInstance -ClassName Win32_OperatingSystem -CimSession $testSession -ErrorAction Stop
            Remove-CimSession -CimSession $testSession -ErrorAction SilentlyContinue
            $cimAvailable = $true
            $evidence.CimOrWsMan = 'CIM session test succeeded.'
        }
    }
    catch {
        $evidence.CimOrWsMan = "CIM/WinRM connectivity failed: $($_.Exception.Message)"
    }

    $status = if ($cimAvailable) {
        if ($dnsResolved -and $pingSucceeded) { 'Green' } else { 'Yellow' }
    }
    elseif (-not $dnsResolved) {
        'Red'
    }
    elseif ($pingSucceeded) {
        'Yellow'
    }
    else {
        'Red'
    }

    $message = switch ($status) {
        'Green' { "Server '$ServerName' resolved, responded to ping, and WinRM/CIM appears available." }
        'Yellow' {
            if ($cimAvailable) { "Server '$ServerName' has usable CIM/WinRM connectivity, but one basic connectivity signal was unavailable." }
            else { "Server '$ServerName' has partial connectivity but CIM/WinRM is unavailable." }
        }
        default { "Server '$ServerName' is unreachable for remote health collection." }
    }

    [pscustomobject]@{
        ServerName    = $ServerName
        DnsResolved   = $dnsResolved
        PingSucceeded = $pingSucceeded
        CimAvailable  = $cimAvailable
        Status        = $status
        Message       = $message
        Evidence      = [pscustomobject]$evidence
    }
}

function New-OnPremCimSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServerName,

        [AllowNull()]
        [System.Management.Automation.PSCredential]$Credential
    )

    try {
        $sessionParameters = @{
            ComputerName = $ServerName
            ErrorAction  = 'Stop'
        }

        if ($null -ne $Credential) {
            $sessionParameters.Credential = $Credential
        }

        $session = New-CimSession @sessionParameters
        return [pscustomobject]@{
            Succeeded = $true
            ServerName = $ServerName
            Session   = $session
            Status    = 'Green'
            Message   = "CIM session to '$ServerName' was created."
            Error     = $null
        }
    }
    catch {
        return [pscustomobject]@{
            Succeeded = $false
            ServerName = $ServerName
            Session   = $null
            Status    = 'Red'
            Message   = "Unable to create CIM session to '$ServerName': $($_.Exception.Message)"
            Error     = $_.Exception.Message
        }
    }
}

function Get-RemoteCpuHealth {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$CimSession,

        [Parameter(Mandatory)]
        [string]$ServerName,

        [Parameter(Mandatory)]
        [object]$Thresholds
    )

    try {
        $processor = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_Processor -Filter "Name = '_Total'" -CimSession $CimSession -ErrorAction Stop
        $cpuUsagePercent = [math]::Round([double]$processor.PercentProcessorTime, 2)
        $evidence = 'Win32_PerfFormattedData_PerfOS_Processor.PercentProcessorTime'
    }
    catch {
        try {
            $processor = @(Get-CimInstance -ClassName Win32_Processor -CimSession $CimSession -ErrorAction Stop | Select-Object -First 1)
            $cpuUsagePercent = [math]::Round([double]$processor.LoadPercentage, 2)
            $evidence = 'Win32_Processor.LoadPercentage'
        }
        catch {
            return [pscustomobject]@{
                Category   = 'OS'
                CheckName  = 'CPU Usage'
                TargetName = $ServerName
                Value      = $null
                Unit       = 'Percent'
                Status     = 'Unknown'
                Message    = "Unable to read remote CPU health: $($_.Exception.Message)"
                Evidence   = 'Win32_PerfFormattedData_PerfOS_Processor or Win32_Processor'
            }
        }
    }

    $status = Get-BasicHealthStatus -Value $cpuUsagePercent -WarningThreshold $Thresholds.cpu.warningPercent -CriticalThreshold $Thresholds.cpu.criticalPercent -ComparisonType GreaterThan
    $message = switch ($status) {
        'Green' { 'CPU usage is within threshold.' }
        'Yellow' { 'CPU usage is above warning threshold.' }
        'Red' { 'CPU usage is above critical threshold.' }
        default { 'CPU usage status could not be evaluated.' }
    }

    [pscustomobject]@{
        Category   = 'OS'
        CheckName  = 'CPU Usage'
        TargetName = $ServerName
        Value      = $cpuUsagePercent
        Unit       = 'Percent'
        Status     = $status
        Message    = $message
        Evidence   = $evidence
    }
}

function Get-RemoteMemoryHealth {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$CimSession,

        [Parameter(Mandatory)]
        [string]$ServerName,

        [Parameter(Mandatory)]
        [object]$Thresholds
    )

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -CimSession $CimSession -ErrorAction Stop
        $totalGb = [math]::Round(([double]$os.TotalVisibleMemorySize / 1MB), 2)
        $freeGb = [math]::Round(([double]$os.FreePhysicalMemory / 1MB), 2)
        $usedPercent = if ($os.TotalVisibleMemorySize -gt 0) {
            [math]::Round(((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100), 2)
        }
        else {
            $null
        }

        $status = Get-BasicHealthStatus -Value $usedPercent -WarningThreshold $Thresholds.memory.warningPercent -CriticalThreshold $Thresholds.memory.criticalPercent -ComparisonType GreaterThan
        $message = switch ($status) {
            'Green' { 'Memory usage is within threshold.' }
            'Yellow' { 'Memory usage is above warning threshold.' }
            'Red' { 'Memory usage is above critical threshold.' }
            default { 'Memory usage status could not be evaluated.' }
        }

        [pscustomobject]@{
            Category   = 'OS'
            CheckName  = 'Memory Usage'
            TargetName = $ServerName
            Value      = $usedPercent
            Unit       = 'Percent'
            Status     = $status
            Message    = $message
            Evidence   = [pscustomobject]@{
                TotalGB = $totalGb
                FreeGB  = $freeGb
            }
        }
    }
    catch {
        [pscustomobject]@{
            Category   = 'OS'
            CheckName  = 'Memory Usage'
            TargetName = $ServerName
            Value      = $null
            Unit       = 'Percent'
            Status     = 'Unknown'
            Message    = "Unable to read remote memory health: $($_.Exception.Message)"
            Evidence   = 'Win32_OperatingSystem.TotalVisibleMemorySize/FreePhysicalMemory'
        }
    }
}

function Get-RemoteLogicalDiskHealth {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$CimSession,

        [Parameter(Mandatory)]
        [string]$ServerName,

        [Parameter(Mandatory)]
        [object]$Thresholds
    )

    try {
        $disks = @(Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType = 3' -CimSession $CimSession -ErrorAction Stop)
    }
    catch {
        return [pscustomobject]@{
            DriveLetter = $null
            VolumeName  = $null
            TotalGB     = $null
            FreeGB      = $null
            FreePercent = $null
            Status      = 'Unknown'
            Message     = "Unable to read remote logical disk health: $($_.Exception.Message)"
        }
    }

    foreach ($disk in $disks) {
        $totalGb = if ($disk.Size) { [math]::Round(($disk.Size / 1GB), 2) } else { 0 }
        $freeGb = if ($disk.FreeSpace) { [math]::Round(($disk.FreeSpace / 1GB), 2) } else { 0 }
        $freePercent = if ($disk.Size -gt 0) { [math]::Round((($disk.FreeSpace / $disk.Size) * 100), 2) } else { $null }
        $status = Get-BasicHealthStatus -Value $freePercent -WarningThreshold $Thresholds.logicalDisk.warningFreePercent -CriticalThreshold $Thresholds.logicalDisk.criticalFreePercent -ComparisonType LessThan
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

function Get-RemoteUptimeHealth {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$CimSession,

        [Parameter(Mandatory)]
        [string]$ServerName,

        [Parameter(Mandatory)]
        [object]$Thresholds
    )

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -CimSession $CimSession -ErrorAction Stop
        $lastBootTime = $os.LastBootUpTime
        $uptimeDays = [math]::Round(((Get-Date) - $lastBootTime).TotalDays, 2)
        $status = Get-BasicHealthStatus -Value $uptimeDays -WarningThreshold $Thresholds.uptime.warningDays -CriticalThreshold ([double]::MaxValue) -ComparisonType GreaterThan

        [pscustomobject]@{
            Category   = 'OS'
            CheckName  = 'Uptime'
            TargetName = $ServerName
            Value      = $uptimeDays
            Unit       = 'Days'
            Status     = $status
            Message    = if ($status -eq 'Yellow') { 'Uptime is above warning threshold.' } else { 'Uptime is within threshold.' }
            Evidence   = [pscustomobject]@{
                LastBootTime = $lastBootTime
            }
        }
    }
    catch {
        [pscustomobject]@{
            Category   = 'OS'
            CheckName  = 'Uptime'
            TargetName = $ServerName
            Value      = $null
            Unit       = 'Days'
            Status     = 'Unknown'
            Message    = "Unable to read remote uptime health: $($_.Exception.Message)"
            Evidence   = 'Win32_OperatingSystem.LastBootUpTime'
        }
    }
}

function Get-RemoteCriticalServiceHealth {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$CimSession,

        [Parameter(Mandatory)]
        [string]$ServerName,

        [Parameter(Mandatory)]
        [string[]]$CriticalServices
    )

    foreach ($serviceName in $CriticalServices) {
        try {
            $escapedName = $serviceName.Replace('\', '\\').Replace("'", "''")
            $service = Get-CimInstance -ClassName Win32_Service -Filter "Name = '$escapedName'" -CimSession $CimSession -ErrorAction Stop

            if ($null -eq $service) {
                [pscustomobject]@{
                    Category   = 'OS'
                    CheckName  = 'Critical Service'
                    TargetName = $ServerName
                    Value      = 'NotFound'
                    Unit       = 'ServiceStatus'
                    Status     = 'Unknown'
                    Message    = "Critical service '$serviceName' was not found."
                    Evidence   = [pscustomobject]@{
                        ServiceName = $serviceName
                    }
                }
                continue
            }

            $status = if ($service.State -eq 'Running') { 'Green' } else { 'Red' }
            $message = if ($status -eq 'Green') {
                "Critical service '$serviceName' is running."
            }
            else {
                "Critical service '$serviceName' is $($service.State)."
            }

            [pscustomobject]@{
                Category   = 'OS'
                CheckName  = 'Critical Service'
                TargetName = $ServerName
                Value      = $service.State
                Unit       = 'ServiceStatus'
                Status     = $status
                Message    = $message
                Evidence   = [pscustomobject]@{
                    ServiceName = $service.Name
                    DisplayName = $service.DisplayName
                    StartMode   = $service.StartMode
                }
            }
        }
        catch {
            [pscustomobject]@{
                Category   = 'OS'
                CheckName  = 'Critical Service'
                TargetName = $ServerName
                Value      = 'Unknown'
                Unit       = 'ServiceStatus'
                Status     = 'Unknown'
                Message    = "Unable to read critical service '$serviceName': $($_.Exception.Message)"
                Evidence   = [pscustomobject]@{
                    ServiceName = $serviceName
                }
            }
        }
    }
}

function Get-RemotePendingRebootStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServerName,

        [AllowNull()]
        [object]$CimSession
    )

    if ($null -eq $CimSession) {
        return [pscustomobject]@{
            IsPendingReboot = $null
            Reasons         = @()
            Status          = 'Unknown'
            Message         = "Pending reboot status for '$ServerName' could not be checked because no CIM session was available."
        }
    }

    try {
        $hklm = 2147483650
        $checks = @(
            @{ Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing'; Key = 'RebootPending'; Reason = 'Component Based Servicing reboot pending' }
            @{ Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update'; Key = 'RebootRequired'; Reason = 'Windows Update reboot required' }
        )

        $reasons = [System.Collections.Generic.List[string]]::new()
        foreach ($check in $checks) {
            $result = Invoke-CimMethod -CimSession $CimSession -Namespace 'root/default' -ClassName 'StdRegProv' -MethodName 'EnumKey' -Arguments @{ hDefKey = $hklm; sSubKeyName = $check.Path } -ErrorAction Stop
            if (@($result.sNames) -contains $check.Key) {
                $reasons.Add($check.Reason)
            }
        }

        $renameResult = Invoke-CimMethod -CimSession $CimSession -Namespace 'root/default' -ClassName 'StdRegProv' -MethodName 'GetMultiStringValue' -Arguments @{ hDefKey = $hklm; sSubKeyName = 'SYSTEM\CurrentControlSet\Control\Session Manager'; sValueName = 'PendingFileRenameOperations' } -ErrorAction Stop
        if (@($renameResult.sValue).Count -gt 0) {
            $reasons.Add('Pending file rename operations')
        }

        $isPendingReboot = $reasons.Count -gt 0
        [pscustomobject]@{
            IsPendingReboot = $isPendingReboot
            Reasons         = @($reasons)
            Status          = if ($isPendingReboot) { 'Yellow' } else { 'Green' }
            Message         = if ($isPendingReboot) { 'Pending reboot indicators were found.' } else { 'No common pending reboot indicators were found.' }
        }
    }
    catch {
        [pscustomobject]@{
            IsPendingReboot = $null
            Reasons         = @()
            Status          = 'Unknown'
            Message         = "Pending reboot status could not be confirmed through read-only remote checks: $($_.Exception.Message)"
        }
    }
}

function Get-RemoteNetworkAdapterHealth {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$CimSession,

        [Parameter(Mandatory)]
        [string]$ServerName,

        [Parameter(Mandatory)]
        [object]$Thresholds
    )

    try {
        $adapters = @(Get-CimInstance -ClassName Win32_NetworkAdapter -Filter 'PhysicalAdapter = True' -CimSession $CimSession -ErrorAction Stop)
    }
    catch {
        return [pscustomobject]@{
            Name                 = $null
            InterfaceDescription = $null
            Status               = 'Unknown'
            LinkSpeed            = $null
            MacAddress           = $null
            StatusEvaluation     = 'Unknown'
            Message              = "Unable to read remote network adapter health: $($_.Exception.Message)"
        }
    }

    foreach ($adapter in $adapters) {
        $speedMbps = if ($adapter.Speed) { [math]::Round(([double]$adapter.Speed / 1000000), 2) } else { $null }
        $statusText = switch ([int]$adapter.NetConnectionStatus) {
            0 { 'Disconnected' }
            1 { 'Connecting' }
            2 { 'Connected' }
            3 { 'Disconnecting' }
            4 { 'HardwareNotPresent' }
            5 { 'HardwareDisabled' }
            6 { 'HardwareMalfunction' }
            7 { 'MediaDisconnected' }
            8 { 'Authenticating' }
            9 { 'AuthenticationSucceeded' }
            10 { 'AuthenticationFailed' }
            11 { 'InvalidAddress' }
            12 { 'CredentialsRequired' }
            default { 'Unknown' }
        }

        $flagDisconnected = [bool]$Thresholds.network.flagDisconnectedAdapters
        $flagLowSpeed = [bool]$Thresholds.network.flagLowSpeedAdapters
        $minimumLinkSpeedMbps = [double]$Thresholds.network.minimumLinkSpeedMbps

        $statusEvaluation = 'Green'
        $message = "Network adapter '$($adapter.Name)' is connected."
        if ($flagDisconnected -and $adapter.NetConnectionStatus -ne 2) {
            $statusEvaluation = 'Red'
            $message = "Network adapter '$($adapter.Name)' is not connected."
        }
        elseif ($flagLowSpeed -and $null -ne $speedMbps -and $speedMbps -lt $minimumLinkSpeedMbps) {
            $statusEvaluation = 'Yellow'
            $message = "Network adapter '$($adapter.Name)' link speed is below the configured threshold."
        }
        elseif ($null -eq $speedMbps) {
            $statusEvaluation = 'Unknown'
            $message = "Network adapter '$($adapter.Name)' link speed could not be evaluated."
        }

        [pscustomobject]@{
            Name                 = $adapter.Name
            InterfaceDescription = $adapter.Description
            Status               = $statusText
            NetConnectionStatus  = $adapter.NetConnectionStatus
            LinkSpeed            = if ($null -ne $speedMbps) { "$speedMbps Mbps" } else { $null }
            SpeedMbps            = $speedMbps
            MacAddress           = $adapter.MACAddress
            StatusEvaluation     = $statusEvaluation
            Message              = $message
        }
    }
}

function Invoke-OnPremServerHealthCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$ServerInventoryRow,

        [Parameter(Mandatory)]
        [object]$Thresholds
    )

    $serverName = [string]$ServerInventoryRow.ServerName
    $connectivity = Test-OnPremServerConnectivity -ServerName $serverName

    if (-not $connectivity.CimAvailable) {
        return [pscustomobject]@{
            TargetName    = $serverName
            TargetType    = 'OnPrem'
            Timestamp     = Get-Date
            Environment   = $ServerInventoryRow.Environment
            Role          = $ServerInventoryRow.Role
            Location      = $ServerInventoryRow.Location
            Connectivity  = $connectivity
            OsHealth      = [pscustomobject]@{
                Cpu              = $null
                Memory           = $null
                Uptime           = $null
                CriticalServices = @()
            }
            StorageHealth = [pscustomobject]@{
                LogicalDisks = @()
            }
            NetworkHealth = [pscustomobject]@{
                Adapters = @()
            }
            PendingReboot = [pscustomobject]@{
                IsPendingReboot = $null
                Reasons         = @()
                Status          = 'Unknown'
                Message         = 'Pending reboot was not checked because the server was unreachable by CIM/WinRM.'
            }
            Summary       = [pscustomobject]@{
                OverallStatus       = 'Red'
                LogicalDiskCount    = 0
                NetworkAdapterCount = 0
                Message             = 'Remote checks were skipped because CIM/WinRM connectivity was unavailable.'
            }
        }
    }

    $sessionResult = New-OnPremCimSession -ServerName $serverName
    if (-not $sessionResult.Succeeded) {
        $connectivity.CimAvailable = $false
        $connectivity.Status = 'Red'
        $connectivity.Message = $sessionResult.Message

        return [pscustomobject]@{
            TargetName    = $serverName
            TargetType    = 'OnPrem'
            Timestamp     = Get-Date
            Environment   = $ServerInventoryRow.Environment
            Role          = $ServerInventoryRow.Role
            Location      = $ServerInventoryRow.Location
            Connectivity  = $connectivity
            OsHealth      = [pscustomobject]@{
                Cpu              = $null
                Memory           = $null
                Uptime           = $null
                CriticalServices = @()
            }
            StorageHealth = [pscustomobject]@{
                LogicalDisks = @()
            }
            NetworkHealth = [pscustomobject]@{
                Adapters = @()
            }
            PendingReboot = [pscustomobject]@{
                IsPendingReboot = $null
                Reasons         = @()
                Status          = 'Unknown'
                Message         = 'Pending reboot was not checked because CIM session creation failed.'
            }
            Summary       = [pscustomobject]@{
                OverallStatus       = 'Red'
                LogicalDiskCount    = 0
                NetworkAdapterCount = 0
                Message             = $sessionResult.Message
            }
        }
    }

    $session = $sessionResult.Session
    try {
        $criticalServices = Split-OnPremCriticalServiceNames -InventoryRow $ServerInventoryRow -Thresholds $Thresholds
        $cpuHealth = Get-RemoteCpuHealth -CimSession $session -ServerName $serverName -Thresholds $Thresholds
        $memoryHealth = Get-RemoteMemoryHealth -CimSession $session -ServerName $serverName -Thresholds $Thresholds
        $uptimeHealth = Get-RemoteUptimeHealth -CimSession $session -ServerName $serverName -Thresholds $Thresholds
        $serviceHealth = @(Get-RemoteCriticalServiceHealth -CimSession $session -ServerName $serverName -CriticalServices $criticalServices)
        $logicalDisks = @(Get-RemoteLogicalDiskHealth -CimSession $session -ServerName $serverName -Thresholds $Thresholds)
        $pendingReboot = Get-RemotePendingRebootStatus -ServerName $serverName -CimSession $session
        $networkAdapters = @(Get-RemoteNetworkAdapterHealth -CimSession $session -ServerName $serverName -Thresholds $Thresholds)

        $allStatuses = @(
            $connectivity.Status
            $cpuHealth.Status
            $memoryHealth.Status
            $uptimeHealth.Status
            $serviceHealth.Status
            $logicalDisks.Status
            $pendingReboot.Status
            $networkAdapters.StatusEvaluation
        )

        [pscustomobject]@{
            TargetName    = $serverName
            TargetType    = 'OnPrem'
            Timestamp     = Get-Date
            Environment   = $ServerInventoryRow.Environment
            Role          = $ServerInventoryRow.Role
            Location      = $ServerInventoryRow.Location
            Connectivity  = $connectivity
            OsHealth      = [pscustomobject]@{
                Cpu              = $cpuHealth
                Memory           = $memoryHealth
                Uptime           = $uptimeHealth
                CriticalServices = $serviceHealth
            }
            StorageHealth = [pscustomobject]@{
                LogicalDisks = $logicalDisks
            }
            NetworkHealth = [pscustomobject]@{
                Adapters = $networkAdapters
            }
            PendingReboot = $pendingReboot
            Summary       = [pscustomobject]@{
                OverallStatus       = Get-OnPremHighestHealthStatus -Statuses $allStatuses
                LogicalDiskCount    = @($logicalDisks).Count
                NetworkAdapterCount = @($networkAdapters | Where-Object { $_.Name }).Count
                Message             = 'Remote read-only health checks completed.'
            }
        }
    }
    catch {
        [pscustomobject]@{
            TargetName    = $serverName
            TargetType    = 'OnPrem'
            Timestamp     = Get-Date
            Environment   = $ServerInventoryRow.Environment
            Role          = $ServerInventoryRow.Role
            Location      = $ServerInventoryRow.Location
            Connectivity  = $connectivity
            OsHealth      = [pscustomobject]@{
                Cpu              = $null
                Memory           = $null
                Uptime           = $null
                CriticalServices = @()
            }
            StorageHealth = [pscustomobject]@{
                LogicalDisks = @()
            }
            NetworkHealth = [pscustomobject]@{
                Adapters = @()
            }
            PendingReboot = [pscustomobject]@{
                IsPendingReboot = $null
                Reasons         = @()
                Status          = 'Unknown'
                Message         = 'Pending reboot was not checked because the remote health check failed.'
            }
            Summary       = [pscustomobject]@{
                OverallStatus       = 'Red'
                LogicalDiskCount    = 0
                NetworkAdapterCount = 0
                Message             = "Remote health checks failed: $($_.Exception.Message)"
            }
        }
    }
    finally {
        if ($null -ne $session) {
            Remove-CimSession -CimSession $session -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-OnPremHealthCheckBatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$ServerInventory,

        [Parameter(Mandatory)]
        [object]$Thresholds
    )

    $enabledServers = @($ServerInventory | Where-Object { $_.Enabled -eq $true -or [string]$_.Enabled -eq 'True' })
    $results = [System.Collections.Generic.List[object]]::new()
    $total = $enabledServers.Count
    $index = 0

    foreach ($server in $enabledServers) {
        $index++
        $serverName = [string]$server.ServerName
        Write-Progress -Activity 'On-prem server health checks' -Status "Checking $serverName ($index of $total)" -PercentComplete $(if ($total -gt 0) { ($index / $total) * 100 } else { 100 })
        Write-Host "Checking on-prem server $serverName ($index of $total)..."

        try {
            $results.Add((Invoke-OnPremServerHealthCheck -ServerInventoryRow $server -Thresholds $Thresholds))
        }
        catch {
            $results.Add([pscustomobject]@{
                TargetName    = $serverName
                TargetType    = 'OnPrem'
                Timestamp     = Get-Date
                Environment   = $server.Environment
                Role          = $server.Role
                Location      = $server.Location
                Connectivity  = [pscustomobject]@{
                    ServerName    = $serverName
                    DnsResolved   = $false
                    PingSucceeded = $false
                    CimAvailable  = $false
                    Status        = 'Red'
                    Message       = "On-prem health check failed before remote checks completed: $($_.Exception.Message)"
                    Evidence      = $_.Exception.Message
                }
                OsHealth      = [pscustomobject]@{ Cpu = $null; Memory = $null; Uptime = $null; CriticalServices = @() }
                StorageHealth = [pscustomobject]@{ LogicalDisks = @() }
                NetworkHealth = [pscustomobject]@{ Adapters = @() }
                PendingReboot = [pscustomobject]@{ IsPendingReboot = $null; Reasons = @(); Status = 'Unknown'; Message = 'Pending reboot was not checked because the server check failed.' }
                Summary       = [pscustomobject]@{ OverallStatus = 'Red'; LogicalDiskCount = 0; NetworkAdapterCount = 0; Message = 'Server check failed gracefully.' }
            })
        }
    }

    Write-Progress -Activity 'On-prem server health checks' -Completed
    return @($results)
}

Export-ModuleMember -Function @(
    'Test-OnPremServerConnectivity',
    'New-OnPremCimSession',
    'Get-RemoteCpuHealth',
    'Get-RemoteMemoryHealth',
    'Get-RemoteLogicalDiskHealth',
    'Get-RemoteUptimeHealth',
    'Get-RemoteCriticalServiceHealth',
    'Get-RemotePendingRebootStatus',
    'Get-RemoteNetworkAdapterHealth',
    'Invoke-OnPremServerHealthCheck',
    'Invoke-OnPremHealthCheckBatch'
)
