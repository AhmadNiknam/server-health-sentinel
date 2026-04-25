<#
HardwareSensorCollector module.

Provides optional, read-only hardware management endpoint readiness checks.
This phase does not authenticate to, poll, modify, reboot, or power-cycle
physical servers or management controllers.
#>

function ConvertTo-HardwareBoolean {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($Value -is [bool]) {
        return $Value
    }

    $textValue = [string]$Value
    if ([string]::IsNullOrWhiteSpace($textValue)) {
        return $false
    }

    switch ($textValue.Trim().ToLowerInvariant()) {
        'true' { return $true }
        '1' { return $true }
        'yes' { return $true }
        'enabled' { return $true }
        default { return $false }
    }
}

function Get-MaskedHardwareEndpoint {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Endpoint,

        [AllowNull()]
        [object]$Port
    )

    $endpointText = [string]$Endpoint
    if ([string]::IsNullOrWhiteSpace($endpointText)) {
        return ''
    }

    try {
        $uri = [System.Uri]$endpointText
        $portText = if ($uri.IsDefaultPort) {
            if (-not [string]::IsNullOrWhiteSpace([string]$Port)) { [string]$Port } else { '' }
        }
        else {
            [string]$uri.Port
        }

        if ([string]::IsNullOrWhiteSpace($portText)) {
            return "$($uri.Scheme)://[redacted-management-endpoint]"
        }

        return "$($uri.Scheme)://[redacted-management-endpoint]:$portText"
    }
    catch {
        return '[redacted-management-endpoint]'
    }
}

function Test-HardwareEndpointConfig {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object[]]$HardwareEndpointInventory
    )

    $requiredFields = @(
        'TargetName',
        'Environment',
        'Vendor',
        'ManagementType',
        'Endpoint',
        'Port',
        'UseSsl',
        'Enabled'
    )

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($endpoint in @($HardwareEndpointInventory)) {
        if ($null -eq $endpoint) {
            $results.Add([pscustomobject]@{
                    TargetName     = ''
                    Vendor         = ''
                    ManagementType = ''
                    Endpoint       = ''
                    Enabled        = $false
                    Status         = 'Unknown'
                    Message        = 'Hardware endpoint inventory entry was null.'
                })
            continue
        }

        $propertyNames = @($endpoint.PSObject.Properties.Name)
        $missingFields = @($requiredFields | Where-Object { $_ -notin $propertyNames })
        $enabled = ConvertTo-HardwareBoolean -Value $endpoint.Enabled
        $status = 'Green'
        $message = 'Hardware endpoint configuration has the required structure.'

        if ($missingFields.Count -gt 0) {
            $status = 'Unknown'
            $message = "Hardware endpoint configuration is missing required field(s): $($missingFields -join ', ')."
        }
        elseif (-not $enabled) {
            $status = 'Skipped'
            $message = 'Hardware endpoint is disabled by configuration.'
        }
        elseif ([string]::IsNullOrWhiteSpace([string]$endpoint.TargetName) -or [string]::IsNullOrWhiteSpace([string]$endpoint.ManagementType)) {
            $status = 'Unknown'
            $message = 'Hardware endpoint configuration is missing a target name or management type.'
        }

        $results.Add([pscustomobject]@{
                TargetName     = [string]$endpoint.TargetName
                Vendor         = [string]$endpoint.Vendor
                ManagementType = [string]$endpoint.ManagementType
                Endpoint       = Get-MaskedHardwareEndpoint -Endpoint $endpoint.Endpoint -Port $endpoint.Port
                Enabled        = $enabled
                Status         = $status
                Message        = $message
            })
    }

    return @($results)
}

function Get-HardwareEndpointReadiness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$HardwareEndpoint
    )

    $enabled = ConvertTo-HardwareBoolean -Value $HardwareEndpoint.Enabled
    $targetName = if (-not [string]::IsNullOrWhiteSpace([string]$HardwareEndpoint.TargetName)) { [string]$HardwareEndpoint.TargetName } else { 'UnknownHardwareEndpoint' }
    $vendor = [string]$HardwareEndpoint.Vendor
    $managementType = [string]$HardwareEndpoint.ManagementType
    $endpointMasked = Get-MaskedHardwareEndpoint -Endpoint $HardwareEndpoint.Endpoint -Port $HardwareEndpoint.Port
    $supportedManagementTypes = @('Redfish', 'iDRAC', 'iLO', 'XClarity', 'VendorSpecific')

    if (-not $enabled) {
        return [pscustomobject]@{
            TargetName     = $targetName
            TargetType     = 'HardwareEndpoint'
            Vendor         = $vendor
            ManagementType = $managementType
            EndpointMasked = $endpointMasked
            Status         = 'Skipped'
            Message        = 'Hardware endpoint is disabled by configuration.'
            Recommendation = 'Leave disabled unless an administrator intentionally enables read-only hardware readiness checks for this target.'
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$HardwareEndpoint.Endpoint)) {
        return [pscustomobject]@{
            TargetName     = $targetName
            TargetType     = 'HardwareEndpoint'
            Vendor         = $vendor
            ManagementType = $managementType
            EndpointMasked = ''
            Status         = 'Unknown'
            Message        = 'Hardware endpoint is enabled but no management endpoint URI was configured.'
            Recommendation = 'Add a Redfish-style management endpoint URI in a local ignored hardware endpoint inventory file, without credentials.'
        }
    }

    if ([string]::IsNullOrWhiteSpace($managementType) -or $managementType -notin $supportedManagementTypes) {
        return [pscustomobject]@{
            TargetName     = $targetName
            TargetType     = 'HardwareEndpoint'
            Vendor         = $vendor
            ManagementType = $managementType
            EndpointMasked = $endpointMasked
            Status         = 'Unknown'
            Message        = "Hardware management type '$managementType' is not recognized for readiness checks."
            Recommendation = 'Use Redfish for the current readiness design, or validate the vendor-specific management type before enabling this endpoint.'
        }
    }

    [pscustomobject]@{
        TargetName     = $targetName
        TargetType     = 'HardwareEndpoint'
        Vendor         = $vendor
        ManagementType = $managementType
        EndpointMasked = $endpointMasked
        Status         = 'Yellow'
        Message        = 'Hardware management endpoint is configured and enabled, but authenticated Redfish sensor polling is planned for a future version.'
        Recommendation = 'Confirm the management interface, network path, and read-only access model with the hardware administrator before enabling future authenticated polling.'
    }
}

function Invoke-HardwareSensorCheck {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object[]]$HardwareEndpointInventory
    )

    $enabledEndpoints = @($HardwareEndpointInventory | Where-Object { $null -ne $_ -and (ConvertTo-HardwareBoolean -Value $_.Enabled) })
    if ($enabledEndpoints.Count -eq 0) {
        return @([pscustomobject]@{
                TargetName     = 'HardwareSensorCollector'
                TargetType     = 'Hardware'
                Vendor         = ''
                ManagementType = ''
                EndpointMasked = ''
                Status         = 'Skipped'
                Message        = 'No enabled hardware management endpoints found.'
                Recommendation = 'Hardware sensor checks are optional. Enable endpoints only in a local ignored inventory file when read-only management access is approved.'
            })
    }

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($endpoint in $enabledEndpoints) {
        $results.Add((Get-HardwareEndpointReadiness -HardwareEndpoint $endpoint))
    }

    return @($results)
}

function New-MockHardwareSensorResult {
    [CmdletBinding()]
    param(
        [string]$TargetName = 'MOCK-HARDWARE-01',

        [ValidateSet('Green', 'Yellow', 'Red', 'Unknown')]
        [string]$Status = 'Green'
    )

    @(
        [pscustomobject]@{
            TargetName     = $TargetName
            TargetType     = 'HardwareSensor'
            Category       = 'PowerSupply'
            SensorName     = 'Mock Power Supply 1'
            Status         = $Status
            Message        = "Mock power supply status is $Status."
            Recommendation = 'Use mock hardware sensor data only in tests and report rendering validation.'
            IsMock         = $true
            Source         = 'TestData'
        }
        [pscustomobject]@{
            TargetName     = $TargetName
            TargetType     = 'HardwareSensor'
            Category       = 'Fan'
            SensorName     = 'Mock Fan 1'
            Status         = 'Green'
            Message        = 'Mock fan status is Green.'
            Recommendation = 'Use mock hardware sensor data only in tests and report rendering validation.'
            IsMock         = $true
            Source         = 'TestData'
        }
        [pscustomobject]@{
            TargetName     = $TargetName
            TargetType     = 'HardwareSensor'
            Category       = 'Temperature'
            SensorName     = 'Mock Temperature Sensor 1'
            Status         = 'Green'
            Message        = 'Mock temperature status is Green.'
            Recommendation = 'Use mock hardware sensor data only in tests and report rendering validation.'
            IsMock         = $true
            Source         = 'TestData'
        }
        [pscustomobject]@{
            TargetName     = $TargetName
            TargetType     = 'HardwareSensor'
            Category       = 'RAID'
            SensorName     = 'Mock RAID Controller 1'
            Status         = 'Green'
            Message        = 'Mock RAID/controller status is Green.'
            Recommendation = 'Use mock hardware sensor data only in tests and report rendering validation.'
            IsMock         = $true
            Source         = 'TestData'
        }
    )
}

Export-ModuleMember -Function @(
    'Test-HardwareEndpointConfig',
    'Get-HardwareEndpointReadiness',
    'Invoke-HardwareSensorCheck',
    'New-MockHardwareSensorResult'
)
