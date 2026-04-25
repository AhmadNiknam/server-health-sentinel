<#
AzureVmHealthCollector module.

Planned purpose:
Collect read-only Azure VM metadata and guest health signals using Az PowerShell
and Azure VM Run Command where configured.
#>

function ConvertTo-MaskedAzureId {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value
    )

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    $cleanText = $text.Trim()
    if ($cleanText.Length -le 8) {
        return '****'
    }

    return "$($cleanText.Substring(0, 4))...$($cleanText.Substring($cleanText.Length - 4, 4))"
}

function Test-AzureSampleSubscriptionId {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$SubscriptionId
    )

    $text = [string]$SubscriptionId
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $true
    }

    $trimmed = $text.Trim()
    if ($trimmed -eq '00000000-0000-0000-0000-000000000000') {
        return $true
    }

    $guidValue = [guid]::Empty
    if (-not [guid]::TryParse($trimmed, [ref]$guidValue)) {
        return $true
    }

    return $guidValue -eq [guid]::Empty
}

function Get-AzureHighestHealthStatus {
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

function Get-AzureVmPowerState {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Vm
    )

    $status = @($Vm.Statuses) | Where-Object { [string]$_.Code -like 'PowerState/*' } | Select-Object -First 1
    if ($null -ne $status) {
        if (-not [string]::IsNullOrWhiteSpace([string]$status.DisplayStatus)) {
            return [string]$status.DisplayStatus
        }

        return ([string]$status.Code).Replace('PowerState/', '')
    }

    return $null
}

function Test-AzPowerShellModuleAvailable {
    [CmdletBinding()]
    param(
        [string[]]$ModuleNames = @('Az.Accounts', 'Az.Compute', 'Az.Network')
    )

    foreach ($moduleName in $ModuleNames) {
        $module = Get-Module -ListAvailable -Name $moduleName |
            Sort-Object Version -Descending |
            Select-Object -First 1

        if ($null -eq $module) {
            [pscustomobject]@{
                ModuleName = $moduleName
                Available  = $false
                Version    = $null
                Status     = 'Unknown'
                Message    = "PowerShell module '$moduleName' is not available. Install it before using checks that require it."
            }
            continue
        }

        [pscustomobject]@{
            ModuleName = $moduleName
            Available  = $true
            Version    = [string]$module.Version
            Status     = 'Green'
            Message    = "PowerShell module '$moduleName' is available."
        }
    }
}

function Get-CurrentAzContextStatus {
    [CmdletBinding()]
    param()

    if (-not (Get-Command -Name Get-AzContext -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{
            IsAuthenticated      = $false
            Account              = $null
            TenantIdMasked       = $null
            SubscriptionIdMasked = $null
            SubscriptionName     = $null
            Status               = 'Unknown'
            Message              = "Az.Accounts is not available. Install Az.Accounts and run Connect-AzAccount before using Azure mode."
        }
    }

    try {
        $context = Get-AzContext -ErrorAction Stop
        if ($null -eq $context -or $null -eq $context.Account -or $null -eq $context.Subscription) {
            return [pscustomobject]@{
                IsAuthenticated      = $false
                Account              = $null
                TenantIdMasked       = $null
                SubscriptionIdMasked = $null
                SubscriptionName     = $null
                Status               = 'Unknown'
                Message              = 'No Azure context found. Run Connect-AzAccount before using Azure mode.'
            }
        }

        [pscustomobject]@{
            IsAuthenticated      = $true
            Account              = [string]$context.Account.Id
            TenantIdMasked       = ConvertTo-MaskedAzureId -Value $context.Tenant.Id
            SubscriptionIdMasked = ConvertTo-MaskedAzureId -Value $context.Subscription.Id
            SubscriptionName     = [string]$context.Subscription.Name
            Status               = 'Green'
            Message              = 'Azure context is available.'
        }
    }
    catch {
        [pscustomobject]@{
            IsAuthenticated      = $false
            Account              = $null
            TenantIdMasked       = $null
            SubscriptionIdMasked = $null
            SubscriptionName     = $null
            Status               = 'Unknown'
            Message              = "No Azure context found. Run Connect-AzAccount before using Azure mode. Details: $($_.Exception.Message)"
        }
    }
}

function Set-AzureSubscriptionContextSafe {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$SubscriptionId
    )

    $maskedSubscriptionId = ConvertTo-MaskedAzureId -Value $SubscriptionId
    if (Test-AzureSampleSubscriptionId -SubscriptionId $SubscriptionId) {
        return [pscustomobject]@{
            Succeeded            = $false
            SubscriptionIdMasked = $maskedSubscriptionId
            SubscriptionName     = $null
            Status               = 'Unknown'
            Message              = 'SubscriptionId is blank, invalid, or a fake sample value. Provide a real subscription ID in a local ignored config file.'
        }
    }

    if (-not (Get-Command -Name Set-AzContext -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{
            Succeeded            = $false
            SubscriptionIdMasked = $maskedSubscriptionId
            SubscriptionName     = $null
            Status               = 'Unknown'
            Message              = 'Set-AzContext is not available because Az.Accounts is missing or not loaded.'
        }
    }

    try {
        $context = Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop
        [pscustomobject]@{
            Succeeded            = $true
            SubscriptionIdMasked = $maskedSubscriptionId
            SubscriptionName     = [string]$context.Subscription.Name
            Status               = 'Green'
            Message              = "Azure subscription context was selected for subscription $maskedSubscriptionId."
        }
    }
    catch {
        [pscustomobject]@{
            Succeeded            = $false
            SubscriptionIdMasked = $maskedSubscriptionId
            SubscriptionName     = $null
            Status               = 'Red'
            Message              = "Unable to select Azure subscription ${maskedSubscriptionId}: $($_.Exception.Message)"
        }
    }
}

function Get-AzureVmMetadata {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$SubscriptionId,

        [Parameter(Mandatory)]
        [string]$ResourceGroupName,

        [Parameter(Mandatory)]
        [string]$VmName,

        [AllowNull()]
        [object]$InventoryRow
    )

    if (-not (Get-Command -Name Get-AzVM -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{
            TargetName        = $VmName
            TargetType        = 'AzureVM'
            Environment       = $InventoryRow.Environment
            Role              = $InventoryRow.Role
            Location          = $InventoryRow.Location
            VmObject          = $null
            Metadata          = $null
            Status            = 'Unknown'
            Message           = 'Get-AzVM is not available because Az.Compute is missing or not loaded.'
        }
    }

    try {
        $vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VmName -Status -ErrorAction Stop
        $managedDiskCount = 0
        if ($vm.StorageProfile.OsDisk.ManagedDisk) { $managedDiskCount++ }
        $managedDiskCount += @($vm.StorageProfile.DataDisks | Where-Object { $_.ManagedDisk }).Count
        $nicIds = @($vm.NetworkProfile.NetworkInterfaces | ForEach-Object { $_.Id } | Where-Object { $_ })
        $powerState = Get-AzureVmPowerState -Vm $vm
        $provisioningState = [string]$vm.ProvisioningState

        [pscustomobject]@{
            TargetName  = $VmName
            TargetType  = 'AzureVM'
            Environment = $InventoryRow.Environment
            Role        = $InventoryRow.Role
            Location    = if ($vm.Location) { [string]$vm.Location } else { $InventoryRow.Location }
            VmObject    = $vm
            Metadata    = [pscustomobject]@{
                VmName             = [string]$vm.Name
                ResourceGroupName  = $ResourceGroupName
                Location           = [string]$vm.Location
                VmSize             = [string]$vm.HardwareProfile.VmSize
                OsType             = [string]$vm.StorageProfile.OsDisk.OsType
                ProvisioningState  = $provisioningState
                PowerState         = $powerState
                Tags               = $vm.Tags
                ManagedDiskCount   = $managedDiskCount
                NicCount           = $nicIds.Count
                PrimaryNicId       = @($vm.NetworkProfile.NetworkInterfaces | Where-Object { $_.Primary -eq $true } | Select-Object -First 1).Id
            }
            Status      = if ($provisioningState -eq 'Succeeded') { 'Green' } else { 'Yellow' }
            Message     = "Azure VM '$VmName' metadata was collected."
        }
    }
    catch {
        $message = $_.Exception.Message
        $status = if ($message -match 'authorization|forbidden|denied|unauthorized') { 'Red' } else { 'Unknown' }
        [pscustomobject]@{
            TargetName  = $VmName
            TargetType  = 'AzureVM'
            Environment = $InventoryRow.Environment
            Role        = $InventoryRow.Role
            Location    = $InventoryRow.Location
            VmObject    = $null
            Metadata    = [pscustomobject]@{
                VmName            = $VmName
                ResourceGroupName = $ResourceGroupName
                Location          = $InventoryRow.Location
            }
            Status      = $status
            Message     = "Unable to read Azure VM '$VmName' in resource group '$ResourceGroupName': $message"
        }
    }
}

function Get-AzureVmDiskSummary {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$VmObject
    )

    if ($null -eq $VmObject) {
        return [pscustomobject]@{
            OsDiskName    = $null
            OsDiskType    = $null
            DataDiskCount = 0
            Disks         = @()
            Status        = 'Unknown'
            Message       = 'Azure VM disk summary was not collected because VM metadata is unavailable.'
        }
    }

    try {
        $osDisk = $VmObject.StorageProfile.OsDisk
        $dataDisks = @($VmObject.StorageProfile.DataDisks)
        $diskItems = [System.Collections.Generic.List[object]]::new()
        if ($null -ne $osDisk) {
            $diskItems.Add([pscustomobject]@{
                Name       = [string]$osDisk.Name
                Type       = 'OS'
                DiskSku    = [string]$osDisk.ManagedDisk.StorageAccountType
                SizeGB     = $osDisk.DiskSizeGB
                Caching    = [string]$osDisk.Caching
                CreateMode = [string]$osDisk.CreateOption
            })
        }

        foreach ($disk in $dataDisks) {
            if ($null -eq $disk) { continue }
            $diskItems.Add([pscustomobject]@{
                Name       = [string]$disk.Name
                Type       = 'Data'
                Lun        = $disk.Lun
                DiskSku    = [string]$disk.ManagedDisk.StorageAccountType
                SizeGB     = $disk.DiskSizeGB
                Caching    = [string]$disk.Caching
                CreateMode = [string]$disk.CreateOption
            })
        }

        [pscustomobject]@{
            OsDiskName    = [string]$osDisk.Name
            OsDiskType    = [string]$osDisk.ManagedDisk.StorageAccountType
            DataDiskCount = $dataDisks.Count
            Disks         = @($diskItems)
            Status        = 'Green'
            Message       = 'Azure VM disk summary was collected.'
        }
    }
    catch {
        [pscustomobject]@{
            OsDiskName    = $null
            OsDiskType    = $null
            DataDiskCount = 0
            Disks         = @()
            Status        = 'Unknown'
            Message       = "Unable to collect Azure VM disk summary: $($_.Exception.Message)"
        }
    }
}

function Get-AzureVmNetworkSummary {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$VmObject,

        [AllowNull()]
        [string[]]$NicIds
    )

    $resolvedNicIds = @($NicIds | Where-Object { $_ })
    if ($resolvedNicIds.Count -eq 0 -and $null -ne $VmObject) {
        $resolvedNicIds = @($VmObject.NetworkProfile.NetworkInterfaces | ForEach-Object { $_.Id } | Where-Object { $_ })
    }

    if ($resolvedNicIds.Count -eq 0) {
        return [pscustomobject]@{
            NicCount              = 0
            PrivateIPs            = @()
            PublicIPAssociations  = @()
            NetworkInterfaceNames = @()
            AcceleratedNetworking = @()
            Nics                  = @()
            Status                = 'Unknown'
            Message               = 'No network interface IDs were available from Azure VM metadata.'
        }
    }

    if (-not (Get-Command -Name Get-AzNetworkInterface -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{
            NicCount              = $resolvedNicIds.Count
            PrivateIPs            = @()
            PublicIPAssociations  = @()
            NetworkInterfaceNames = @()
            AcceleratedNetworking = @()
            Nics                  = @()
            Status                = 'Unknown'
            Message               = 'Az.Network is not available, so network interface details were not collected.'
        }
    }

    $nics = [System.Collections.Generic.List[object]]::new()
    $privateIps = [System.Collections.Generic.List[string]]::new()
    $publicIpAssociations = [System.Collections.Generic.List[object]]::new()
    $acceleratedNetworking = [System.Collections.Generic.List[object]]::new()

    foreach ($nicId in $resolvedNicIds) {
        try {
            $nic = Get-AzNetworkInterface -ResourceId $nicId -ErrorAction Stop
            $ipConfigs = @($nic.IpConfigurations)
            foreach ($ipConfig in $ipConfigs) {
                if ($ipConfig.PrivateIpAddress) {
                    $privateIps.Add([string]$ipConfig.PrivateIpAddress)
                }

                if ($ipConfig.PublicIpAddress.Id) {
                    $publicIpAssociations.Add([pscustomobject]@{
                        NicName            = [string]$nic.Name
                        IpConfiguration    = [string]$ipConfig.Name
                        PublicIpResourceId = [string]$ipConfig.PublicIpAddress.Id
                    })
                }
            }

            $acceleratedNetworking.Add([pscustomobject]@{
                NicName = [string]$nic.Name
                Enabled = [bool]$nic.EnableAcceleratedNetworking
            })

            $nics.Add([pscustomobject]@{
                Name                  = [string]$nic.Name
                ResourceGroupName     = [string]$nic.ResourceGroupName
                PrivateIPs            = @($ipConfigs.PrivateIpAddress | Where-Object { $_ })
                HasPublicIpAssociation = @($ipConfigs | Where-Object { $_.PublicIpAddress.Id }).Count -gt 0
                AcceleratedNetworking = [bool]$nic.EnableAcceleratedNetworking
                ProvisioningState     = [string]$nic.ProvisioningState
                MacAddress            = [string]$nic.MacAddress
            })
        }
        catch {
            $nics.Add([pscustomobject]@{
                Name                  = Split-Path -Path $nicId -Leaf
                ResourceGroupName     = $null
                PrivateIPs            = @()
                HasPublicIpAssociation = $null
                AcceleratedNetworking = $null
                ProvisioningState     = 'Unknown'
                MacAddress            = $null
                Status                = 'Unknown'
                Message               = "Unable to read NIC details: $($_.Exception.Message)"
            })
        }
    }

    [pscustomobject]@{
        NicCount              = $resolvedNicIds.Count
        PrivateIPs            = @($privateIps)
        PublicIPAssociations  = @($publicIpAssociations)
        NetworkInterfaceNames = @($nics.Name | Where-Object { $_ })
        AcceleratedNetworking = @($acceleratedNetworking)
        Nics                  = @($nics)
        Status                = if (@($nics | Where-Object { $_.Status -eq 'Unknown' }).Count -gt 0) { 'Unknown' } else { 'Green' }
        Message               = 'Azure VM network summary was collected.'
    }
}

function Invoke-AzureVmGuestHealthCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ResourceGroupName,

        [Parameter(Mandatory)]
        [string]$VmName,

        [Parameter(Mandatory)]
        [string]$ScriptPath,

        [AllowNull()]
        [object]$Thresholds,

        [AllowNull()]
        [object]$Metadata
    )

    $osType = [string]$Metadata.OsType
    $powerState = [string]$Metadata.PowerState

    if ($null -eq $Metadata -or [string]::IsNullOrWhiteSpace($powerState)) {
        return [pscustomobject]@{
            Attempted = $false
            Status    = 'Unknown'
            Message   = 'Azure VM Run Command guest health was skipped because VM metadata or power state is unavailable.'
            RawOutput = $null
            Parsed    = $null
        }
    }

    if ($osType -and $osType -ne 'Windows') {
        return [pscustomobject]@{
            Attempted = $false
            Status    = 'Unknown'
            Message   = "Azure VM Run Command guest health was skipped because OS type '$osType' is not Windows."
            RawOutput = $null
            Parsed    = $null
        }
    }

    if ($powerState -and $powerState -notmatch 'running') {
        return [pscustomobject]@{
            Attempted = $false
            Status    = 'Yellow'
            Message   = "Azure VM Run Command guest health was skipped because the VM power state is '$powerState'."
            RawOutput = $null
            Parsed    = $null
        }
    }

    if (-not (Get-Command -Name Invoke-AzVMRunCommand -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{
            Attempted = $false
            Status    = 'Unknown'
            Message   = 'Invoke-AzVMRunCommand is not available because Az.Compute is missing or not loaded.'
            RawOutput = $null
            Parsed    = $null
        }
    }

    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        return [pscustomobject]@{
            Attempted = $false
            Status    = 'Unknown'
            Message   = "In-guest health script was not found: $ScriptPath"
            RawOutput = $null
            Parsed    = $null
        }
    }

    try {
        $scriptContent = Get-Content -LiteralPath $ScriptPath -Raw -ErrorAction Stop
        $runResult = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName $VmName -CommandId 'RunPowerShellScript' -ScriptString $scriptContent -ErrorAction Stop
        $messages = @($runResult.Value | ForEach-Object { $_.Message } | Where-Object { $_ })
        $rawOutput = ($messages -join [Environment]::NewLine).Trim()
        $jsonStart = $rawOutput.IndexOf('{')
        $jsonText = if ($jsonStart -ge 0) { $rawOutput.Substring($jsonStart).Trim() } else { $rawOutput }
        $parsed = $null

        try {
            if (-not [string]::IsNullOrWhiteSpace($jsonText)) {
                $parsed = $jsonText | ConvertFrom-Json -ErrorAction Stop
            }
        }
        catch {
            $parsed = $null
        }

        [pscustomobject]@{
            Attempted = $true
            Status    = if ($null -ne $parsed) { 'Green' } else { 'Unknown' }
            Message   = if ($null -ne $parsed) { 'Azure VM Run Command guest health completed.' } else { 'Azure VM Run Command completed, but JSON output could not be parsed.' }
            RawOutput = $rawOutput
            Parsed    = $parsed
        }
    }
    catch {
        [pscustomobject]@{
            Attempted = $true
            Status    = 'Unknown'
            Message   = "Azure VM Run Command guest health failed: $($_.Exception.Message)"
            RawOutput = $null
            Parsed    = $null
        }
    }
}

function Invoke-AzureVmHealthCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$AzureVmInventoryRow,

        [Parameter(Mandatory)]
        [object]$Thresholds,

        [AllowNull()]
        [object]$PredictiveRules
    )

    $vmName = [string]$AzureVmInventoryRow.VmName
    $resourceGroupName = [string]$AzureVmInventoryRow.ResourceGroupName
    $moduleStatus = @(Test-AzPowerShellModuleAvailable)
    $contextStatus = Get-CurrentAzContextStatus
    $subscriptionStatus = Set-AzureSubscriptionContextSafe -SubscriptionId ([string]$AzureVmInventoryRow.SubscriptionId)
    $scriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts/Invoke-InGuestHealthCheck.ps1'
    $metadataResult = $null
    $diskSummary = $null
    $networkSummary = $null
    $guestHealth = $null

    if (($moduleStatus | Where-Object { $_.ModuleName -in @('Az.Accounts', 'Az.Compute') -and -not $_.Available }).Count -gt 0) {
        $metadataResult = [pscustomobject]@{
            TargetName  = $vmName
            TargetType  = 'AzureVM'
            Environment = $AzureVmInventoryRow.Environment
            Role        = $AzureVmInventoryRow.Role
            Location    = $AzureVmInventoryRow.Location
            VmObject    = $null
            Metadata    = [pscustomobject]@{ VmName = $vmName; ResourceGroupName = $resourceGroupName; Location = $AzureVmInventoryRow.Location }
            Status      = 'Unknown'
            Message     = 'Required Az modules are missing, so Azure VM metadata was not collected.'
        }
    }
    elseif (-not $contextStatus.IsAuthenticated) {
        $metadataResult = [pscustomobject]@{
            TargetName  = $vmName
            TargetType  = 'AzureVM'
            Environment = $AzureVmInventoryRow.Environment
            Role        = $AzureVmInventoryRow.Role
            Location    = $AzureVmInventoryRow.Location
            VmObject    = $null
            Metadata    = [pscustomobject]@{ VmName = $vmName; ResourceGroupName = $resourceGroupName; Location = $AzureVmInventoryRow.Location }
            Status      = 'Unknown'
            Message     = 'Azure VM metadata was not collected because no authenticated Azure context is available.'
        }
    }
    elseif (-not $subscriptionStatus.Succeeded) {
        $metadataResult = [pscustomobject]@{
            TargetName  = $vmName
            TargetType  = 'AzureVM'
            Environment = $AzureVmInventoryRow.Environment
            Role        = $AzureVmInventoryRow.Role
            Location    = $AzureVmInventoryRow.Location
            VmObject    = $null
            Metadata    = [pscustomobject]@{ VmName = $vmName; ResourceGroupName = $resourceGroupName; Location = $AzureVmInventoryRow.Location }
            Status      = $subscriptionStatus.Status
            Message     = 'Azure VM metadata was not collected because subscription context could not be selected.'
        }
    }
    else {
        $metadataResult = Get-AzureVmMetadata -SubscriptionId ([string]$AzureVmInventoryRow.SubscriptionId) -ResourceGroupName $resourceGroupName -VmName $vmName -InventoryRow $AzureVmInventoryRow
    }

    $diskSummary = Get-AzureVmDiskSummary -VmObject $metadataResult.VmObject
    $networkSummary = Get-AzureVmNetworkSummary -VmObject $metadataResult.VmObject
    $guestHealth = Invoke-AzureVmGuestHealthCheck -ResourceGroupName $resourceGroupName -VmName $vmName -ScriptPath $scriptPath -Thresholds $Thresholds -Metadata $metadataResult.Metadata

    $allStatuses = @(
        $moduleStatus.Status
        $contextStatus.Status
        $subscriptionStatus.Status
        $metadataResult.Status
        $diskSummary.Status
        $networkSummary.Status
        $guestHealth.Status
    )

    [pscustomobject]@{
        TargetName     = $vmName
        TargetType     = 'AzureVM'
        Timestamp      = Get-Date
        Environment    = $AzureVmInventoryRow.Environment
        Role           = $AzureVmInventoryRow.Role
        Location       = if ($metadataResult.Location) { $metadataResult.Location } else { $AzureVmInventoryRow.Location }
        AzureContext   = [pscustomobject]@{
            Modules      = @($moduleStatus)
            Context      = $contextStatus
            Subscription = $subscriptionStatus
        }
        Metadata       = $metadataResult
        DiskSummary    = $diskSummary
        NetworkSummary = $networkSummary
        GuestHealth    = $guestHealth
        Summary        = [pscustomobject]@{
            OverallStatus = Get-AzureHighestHealthStatus -Statuses $allStatuses
            Message       = 'Azure VM read-only health check completed with graceful handling for unavailable signals.'
        }
    }
}

function Invoke-AzureVmHealthCheckBatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$AzureVmInventory,

        [Parameter(Mandatory)]
        [object]$Thresholds,

        [AllowNull()]
        [object]$PredictiveRules
    )

    $enabledVms = @($AzureVmInventory | Where-Object { $_.Enabled -eq $true -or [string]$_.Enabled -eq 'True' })
    $results = [System.Collections.Generic.List[object]]::new()
    $total = $enabledVms.Count
    $index = 0

    foreach ($vm in $enabledVms) {
        $index++
        $vmName = [string]$vm.VmName
        Write-Progress -Activity 'Azure VM health checks' -Status "Checking $vmName ($index of $total)" -PercentComplete $(if ($total -gt 0) { ($index / $total) * 100 } else { 100 })
        Write-Host "Checking Azure VM $vmName ($index of $total)..."

        try {
            $results.Add((Invoke-AzureVmHealthCheck -AzureVmInventoryRow $vm -Thresholds $Thresholds -PredictiveRules $PredictiveRules))
        }
        catch {
            $results.Add([pscustomobject]@{
                TargetName     = $vmName
                TargetType     = 'AzureVM'
                Timestamp      = Get-Date
                Environment    = $vm.Environment
                Role           = $vm.Role
                Location       = $vm.Location
                AzureContext   = [pscustomobject]@{
                    Modules      = @()
                    Context      = [pscustomobject]@{ IsAuthenticated = $false; Status = 'Unknown'; Message = 'Azure context was not checked because the VM check failed early.' }
                    Subscription = [pscustomobject]@{ Succeeded = $false; SubscriptionIdMasked = ConvertTo-MaskedAzureId -Value $vm.SubscriptionId; Status = 'Unknown'; Message = 'Subscription context was not checked because the VM check failed early.' }
                }
                Metadata       = [pscustomobject]@{ TargetName = $vmName; TargetType = 'AzureVM'; Metadata = [pscustomobject]@{ VmName = $vmName; ResourceGroupName = $vm.ResourceGroupName }; Status = 'Red'; Message = "Azure VM health check failed: $($_.Exception.Message)" }
                DiskSummary    = [pscustomobject]@{ Status = 'Unknown'; Message = 'Disk summary was not collected because the VM check failed.' }
                NetworkSummary = [pscustomobject]@{ Status = 'Unknown'; Message = 'Network summary was not collected because the VM check failed.' }
                GuestHealth    = [pscustomobject]@{ Attempted = $false; Status = 'Unknown'; Message = 'Guest health was not collected because the VM check failed.' }
                Summary        = [pscustomobject]@{ OverallStatus = 'Red'; Message = 'Azure VM check failed gracefully.' }
            })
        }
    }

    Write-Progress -Activity 'Azure VM health checks' -Completed
    return @($results)
}

Export-ModuleMember -Function @(
    'Test-AzPowerShellModuleAvailable',
    'Get-CurrentAzContextStatus',
    'Set-AzureSubscriptionContextSafe',
    'Get-AzureVmMetadata',
    'Get-AzureVmDiskSummary',
    'Get-AzureVmNetworkSummary',
    'Invoke-AzureVmGuestHealthCheck',
    'Invoke-AzureVmHealthCheck',
    'Invoke-AzureVmHealthCheckBatch'
)
