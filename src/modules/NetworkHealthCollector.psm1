<#
NetworkHealthCollector module.

Planned purpose:
Collect read-only network adapter status, link speed, MAC address, IP
configuration, DNS servers, gateway, and disconnected adapter indicators.
#>

function ConvertTo-LinkSpeedMbps {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$LinkSpeed
    )

    $text = [string]$LinkSpeed
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    $match = [regex]::Match($text, '([\d\.]+)\s*([KMGTP]?bps)', 'IgnoreCase')
    if (-not $match.Success) {
        return $null
    }

    $value = [double]$match.Groups[1].Value
    switch ($match.Groups[2].Value.ToLowerInvariant()) {
        'kbps' { return $value / 1000 }
        'mbps' { return $value }
        'gbps' { return $value * 1000 }
        'tbps' { return $value * 1000 * 1000 }
        'pbps' { return $value * 1000 * 1000 * 1000 }
        default { return $null }
    }
}

function Get-LocalNetworkAdapterHealth {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Thresholds
    )

    if (-not (Get-Command -Name Get-NetAdapter -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{
            Name                 = $null
            InterfaceDescription = $null
            Status               = 'Unknown'
            LinkSpeed            = $null
            MacAddress           = $null
            StatusEvaluation     = 'Unknown'
            Message              = 'Get-NetAdapter is not available on this system.'
        }
    }

    try {
        $adapters = @(Get-NetAdapter -ErrorAction Stop)
    }
    catch {
        return [pscustomobject]@{
            Name                 = $null
            InterfaceDescription = $null
            Status               = 'Unknown'
            LinkSpeed            = $null
            MacAddress           = $null
            StatusEvaluation     = 'Unknown'
            Message              = "Unable to read local network adapter health: $($_.Exception.Message)"
        }
    }

    foreach ($adapter in $adapters) {
        $linkSpeedMbps = ConvertTo-LinkSpeedMbps -LinkSpeed $adapter.LinkSpeed
        $flagDisconnected = [bool]$Thresholds.network.flagDisconnectedAdapters
        $flagLowSpeed = [bool]$Thresholds.network.flagLowSpeedAdapters
        $minimumLinkSpeedMbps = [double]$Thresholds.network.minimumLinkSpeedMbps

        $statusEvaluation = 'Green'
        $message = "Network adapter '$($adapter.Name)' is up."

        if ($flagDisconnected -and $adapter.Status -ne 'Up') {
            $statusEvaluation = 'Red'
            $message = "Network adapter '$($adapter.Name)' is not up."
        }
        elseif ($flagLowSpeed -and $null -ne $linkSpeedMbps -and $linkSpeedMbps -lt $minimumLinkSpeedMbps) {
            $statusEvaluation = 'Yellow'
            $message = "Network adapter '$($adapter.Name)' link speed is below the configured threshold."
        }
        elseif ($null -eq $linkSpeedMbps) {
            $statusEvaluation = 'Unknown'
            $message = "Network adapter '$($adapter.Name)' link speed could not be evaluated."
        }

        [pscustomobject]@{
            Name                 = $adapter.Name
            InterfaceDescription = $adapter.InterfaceDescription
            Status               = $adapter.Status
            LinkSpeed            = $adapter.LinkSpeed
            MacAddress           = $adapter.MacAddress
            StatusEvaluation     = $statusEvaluation
            Message              = $message
        }
    }
}

function Get-LocalIpConfigurationHealth {
    [CmdletBinding()]
    param()

    if (-not (Get-Command -Name Get-NetIPConfiguration -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{
            InterfaceAlias    = $null
            IPv4Address       = @()
            IPv6Address       = @()
            IPv4DefaultGateway = $null
            DnsServers        = @()
            Message           = 'Get-NetIPConfiguration is not available on this system.'
        }
    }

    try {
        $ipConfigurations = @(Get-NetIPConfiguration -ErrorAction Stop)
    }
    catch {
        return [pscustomobject]@{
            InterfaceAlias    = $null
            IPv4Address       = @()
            IPv6Address       = @()
            IPv4DefaultGateway = $null
            DnsServers        = @()
            Message           = "Unable to read local IP configuration: $($_.Exception.Message)"
        }
    }

    foreach ($configuration in $ipConfigurations) {
        [pscustomobject]@{
            InterfaceAlias    = $configuration.InterfaceAlias
            IPv4Address       = @($configuration.IPv4Address.IPAddress)
            IPv6Address       = @($configuration.IPv6Address.IPAddress)
            IPv4DefaultGateway = @($configuration.IPv4DefaultGateway.NextHop) -join ', '
            DnsServers        = @($configuration.DNSServer.ServerAddresses)
        }
    }
}

function Invoke-LocalNetworkHealthCheck {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Thresholds
    )

    [pscustomobject]@{
        Adapters         = @(Get-LocalNetworkAdapterHealth -Thresholds $Thresholds)
        IpConfigurations = @(Get-LocalIpConfigurationHealth)
    }
}

Export-ModuleMember -Function @(
    'Get-LocalNetworkAdapterHealth',
    'Get-LocalIpConfigurationHealth',
    'Invoke-LocalNetworkHealthCheck'
)
