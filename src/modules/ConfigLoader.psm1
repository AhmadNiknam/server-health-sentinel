<#
.SYNOPSIS
    Loads and validates Server Health Sentinel configuration files.

.DESCRIPTION
    The functions in this module only read local CSV and JSON configuration
    files. They do not connect to servers, Azure, or hardware management
    endpoints.
#>

function Test-ConfigFileExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        return $true
    }

    Write-Error "Configuration file was not found: $Path"
    return $false
}

function Test-CsvRequiredColumns {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string[]]$RequiredColumns
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "CSV configuration file was not found: $Path"
    }

    $headerLine = Get-Content -LiteralPath $Path -TotalCount 1 -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($headerLine)) {
        throw "CSV configuration file has no header row: $Path"
    }

    $actualColumns = @($headerLine -split ',' | ForEach-Object { $_.Trim().Trim('"') })
    $missingColumns = @($RequiredColumns | Where-Object { $_ -notin $actualColumns })

    if ($missingColumns.Count -gt 0) {
        throw "CSV configuration file '$Path' is missing required column(s): $($missingColumns -join ', ')"
    }

    return $true
}

function Test-JsonFileValid {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "JSON configuration file was not found: $Path"
    }

    try {
        $jsonText = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        return $jsonText | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "JSON configuration file '$Path' is invalid: $($_.Exception.Message)"
    }
}

function ConvertTo-ConfigBoolean {
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
        'false' { return $false }
        '0' { return $false }
        'no' { return $false }
        'disabled' { return $false }
        default { return $false }
    }
}

function Import-EnabledCsvRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string[]]$RequiredColumns
    )

    $null = Test-CsvRequiredColumns -Path $Path -RequiredColumns $RequiredColumns

    $rows = @(Import-Csv -LiteralPath $Path -ErrorAction Stop)
    foreach ($row in $rows) {
        $row.Enabled = ConvertTo-ConfigBoolean -Value $row.Enabled
    }

    return @($rows | Where-Object { $_.Enabled -eq $true })
}

function Import-ServerInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $requiredColumns = @(
        'ServerName',
        'Environment',
        'Role',
        'Location',
        'CheckMode',
        'ExpectedNicSpeedMbps',
        'CriticalServices',
        'Enabled'
    )

    return Import-EnabledCsvRows -Path $Path -RequiredColumns $requiredColumns
}

function Import-AzureVmInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $requiredColumns = @(
        'SubscriptionId',
        'ResourceGroupName',
        'VmName',
        'Environment',
        'Role',
        'Location',
        'ExpectedNicSpeedMbps',
        'Enabled'
    )

    return Import-EnabledCsvRows -Path $Path -RequiredColumns $requiredColumns
}

function Import-HardwareEndpointInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $requiredColumns = @(
        'TargetName',
        'Environment',
        'Vendor',
        'ManagementType',
        'Endpoint',
        'Port',
        'UseSsl',
        'Enabled'
    )

    return Import-EnabledCsvRows -Path $Path -RequiredColumns $requiredColumns
}

function Test-RequiredJsonSections {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$JsonObject,

        [Parameter(Mandatory)]
        [string[]]$RequiredSections,

        [Parameter(Mandatory)]
        [string]$Path
    )

    $actualSections = @($JsonObject.PSObject.Properties.Name)
    $missingSections = @($RequiredSections | Where-Object { $_ -notin $actualSections })

    if ($missingSections.Count -gt 0) {
        throw "JSON configuration file '$Path' is missing required section(s): $($missingSections -join ', ')"
    }
}

function Import-HealthThresholds {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $thresholds = Test-JsonFileValid -Path $Path
    $requiredSections = @(
        'cpu',
        'memory',
        'logicalDisk',
        'physicalDisk',
        'uptime',
        'eventLogs',
        'network',
        'pendingReboot',
        'services'
    )

    Test-RequiredJsonSections -JsonObject $thresholds -RequiredSections $requiredSections -Path $Path
    return $thresholds
}

function Import-PredictiveRules {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $predictiveRules = Test-JsonFileValid -Path $Path

    if (-not $predictiveRules.PSObject.Properties['rules']) {
        throw "JSON configuration file '$Path' is missing required section: rules"
    }

    $ruleGroups = @($predictiveRules.rules.PSObject.Properties.Name)
    if ($ruleGroups.Count -eq 0) {
        throw "JSON configuration file '$Path' must define at least one predictive rule group."
    }

    return $predictiveRules
}

Export-ModuleMember -Function @(
    'Test-ConfigFileExists',
    'Test-CsvRequiredColumns',
    'Test-JsonFileValid',
    'Import-ServerInventory',
    'Import-AzureVmInventory',
    'Import-HardwareEndpointInventory',
    'Import-HealthThresholds',
    'Import-PredictiveRules'
)
