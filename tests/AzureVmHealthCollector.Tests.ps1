Describe 'AzureVmHealthCollector' {
    BeforeAll {
        $script:RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
        $script:AzureModulePath = Join-Path $script:RepoRoot 'src/modules/AzureVmHealthCollector.psm1'
        $script:EvaluatorModulePath = Join-Path $script:RepoRoot 'src/modules/HealthEvaluator.psm1'
        $script:ConfigModulePath = Join-Path $script:RepoRoot 'src/modules/ConfigLoader.psm1'

        Import-Module $script:AzureModulePath -Force
        Import-Module $script:EvaluatorModulePath -Force
        Import-Module $script:ConfigModulePath -Force

        $script:Thresholds = [pscustomobject]@{
            cpu         = [pscustomobject]@{ warningPercent = 80; criticalPercent = 95 }
            memory      = [pscustomobject]@{ warningPercent = 80; criticalPercent = 95 }
            logicalDisk = [pscustomobject]@{ warningFreePercent = 20; criticalFreePercent = 10 }
        }

        $script:MockAzureResult = [pscustomobject]@{
            TargetName     = 'vm-lab-app-01'
            TargetType     = 'AzureVM'
            Timestamp      = Get-Date
            Environment    = 'Lab'
            Role           = 'Application'
            Location       = 'canada-central'
            AzureContext   = [pscustomobject]@{
                Modules      = @(
                    [pscustomobject]@{ ModuleName = 'Az.Accounts'; Available = $false; Version = $null; Status = 'Unknown'; Message = "PowerShell module 'Az.Accounts' is not available." },
                    [pscustomobject]@{ ModuleName = 'Az.Compute'; Available = $false; Version = $null; Status = 'Unknown'; Message = "PowerShell module 'Az.Compute' is not available." }
                )
                Context      = [pscustomobject]@{
                    IsAuthenticated      = $false
                    Account              = $null
                    TenantIdMasked       = $null
                    SubscriptionIdMasked = $null
                    SubscriptionName     = $null
                    Status               = 'Unknown'
                    Message              = 'No Azure context found. Run Connect-AzAccount before using Azure mode.'
                }
                Subscription = [pscustomobject]@{
                    Succeeded            = $false
                    SubscriptionIdMasked = '0000...0000'
                    SubscriptionName     = $null
                    Status               = 'Unknown'
                    Message              = 'SubscriptionId is blank, invalid, or a fake sample value.'
                }
            }
            Metadata       = [pscustomobject]@{
                TargetName = 'vm-lab-app-01'
                TargetType = 'AzureVM'
                Metadata   = [pscustomobject]@{
                    VmName            = 'vm-lab-app-01'
                    ResourceGroupName = 'rg-lab-monitoring'
                    Location          = 'canada-central'
                    PowerState        = $null
                }
                Status     = 'Unknown'
                Message    = 'Azure VM metadata was not collected because no authenticated Azure context is available.'
            }
            DiskSummary    = [pscustomobject]@{
                OsDiskName    = $null
                OsDiskType    = $null
                DataDiskCount = 0
                Disks         = @()
                Status        = 'Unknown'
                Message       = 'Azure VM disk summary was not collected because VM metadata is unavailable.'
            }
            NetworkSummary = [pscustomobject]@{
                NicCount              = 0
                PrivateIPs            = @()
                PublicIPAssociations  = @()
                NetworkInterfaceNames = @()
                AcceleratedNetworking = @()
                Nics                  = @()
                Status                = 'Unknown'
                Message               = 'No network interface IDs were available from Azure VM metadata.'
            }
            GuestHealth    = [pscustomobject]@{
                Attempted = $false
                Status    = 'Unknown'
                Message   = 'Azure VM Run Command guest health was skipped because VM metadata or power state is unavailable.'
                RawOutput = $null
                Parsed    = $null
            }
            Summary        = [pscustomobject]@{
                OverallStatus = 'Unknown'
                Message       = 'Azure VM read-only health check completed with graceful handling for unavailable signals.'
            }
        }
    }

    It 'returns missing module result objects with the expected structure' {
        $result = @(Test-AzPowerShellModuleAvailable -ModuleNames @('Server.Health.Sentinel.Missing.Module'))

        $result.Count | Should -Be 1
        $result[0].ModuleName | Should -Be 'Server.Health.Sentinel.Missing.Module'
        $result[0].Available | Should -BeFalse
        $result[0].Status | Should -Be 'Unknown'
        @($result[0].PSObject.Properties.Name) | Should -Contain 'Message'
    }

    It 'returns a missing context result object when Get-AzContext is unavailable' {
        Mock -ModuleName AzureVmHealthCollector Get-Command { $null } -ParameterFilter { $Name -eq 'Get-AzContext' }

        $context = Get-CurrentAzContextStatus

        $context.IsAuthenticated | Should -BeFalse
        $context.Status | Should -Be 'Unknown'
        $context.Message | Should -Match 'Connect-AzAccount'
    }

    It 'returns Unknown for fake sample subscription IDs without selecting context' {
        $result = Set-AzureSubscriptionContextSafe -SubscriptionId '00000000-0000-0000-0000-000000000000'

        $result.Succeeded | Should -BeFalse
        $result.Status | Should -Be 'Unknown'
        $result.Message | Should -Match 'fake sample value'
    }

    It 'converts an Azure VM result into Azure-specific findings' {
        $findings = @(Convert-AzureVmHealthResultToFindings -AzureVmHealthResult $script:MockAzureResult)
        $categories = @($findings.Category | Sort-Object -Unique)

        $categories | Should -Contain 'AzureContext'
        $categories | Should -Contain 'AzureMetadata'
        $categories | Should -Contain 'AzureDisk'
        $categories | Should -Contain 'AzureNetwork'
        $categories | Should -Contain 'AzureGuestHealth'
        @($findings | Where-Object { $_.TargetType -eq 'AzureVM' }).Count | Should -Be $findings.Count
    }

    It 'converts a batch of Azure VM results into a flat findings list' {
        $second = $script:MockAzureResult.PSObject.Copy()
        $second.TargetName = 'vm-lab-db-01'

        $findings = @(Convert-AzureVmBatchHealthResultToFindings -AzureVmHealthResults @($script:MockAzureResult, $second))

        $findings.Count | Should -BeGreaterThan 5
        @($findings.TargetName | Sort-Object -Unique).Count | Should -Be 2
    }

    It 'runs Azure health check against sample inventory without requiring real Azure access' {
        $azureVmSamplePath = Join-Path $script:RepoRoot 'config/azure-vms.sample.csv'
        $inventory = @(Import-AzureVmInventory -Path $azureVmSamplePath)

        $result = Invoke-AzureVmHealthCheck -AzureVmInventoryRow $inventory[0] -Thresholds $script:Thresholds

        $result.TargetType | Should -Be 'AzureVM'
        $result.TargetName | Should -Be 'vm-lab-app-01'
        $result.AzureContext.Subscription.Status | Should -Be 'Unknown'
        $result.GuestHealth.Attempted | Should -BeFalse
    }
}
