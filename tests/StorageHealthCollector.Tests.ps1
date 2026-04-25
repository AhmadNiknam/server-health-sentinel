Describe 'StorageHealthCollector' {
    BeforeAll {
        $script:ModulePath = Join-Path $PSScriptRoot '../src/modules/StorageHealthCollector.psm1'
        Import-Module $script:ModulePath -Force
    }

    It 'exports logical disk, physical disk, and storage check functions' {
        Get-Command -Name Get-LocalLogicalDiskHealth -ErrorAction Stop | Should -Not -BeNullOrEmpty
        Get-Command -Name Get-LocalPhysicalDiskHealth -ErrorAction Stop | Should -Not -BeNullOrEmpty
        Get-Command -Name Invoke-LocalStorageHealthCheck -ErrorAction Stop | Should -Not -BeNullOrEmpty
    }

    It 'returns a parent object with logical and physical disk collections' {
        $thresholds = [pscustomobject]@{
            logicalDisk  = [pscustomobject]@{
                warningFreePercent  = 20
                criticalFreePercent = 10
            }
            physicalDisk = [pscustomobject]@{
                warningHealthStates  = @('Warning', 'Degraded')
                criticalHealthStates = @('Critical', 'Unhealthy', 'Unknown')
            }
        }

        $result = Invoke-LocalStorageHealthCheck -Thresholds $thresholds

        $result.PSObject.Properties.Name | Should -Contain 'LogicalDisks'
        $result.PSObject.Properties.Name | Should -Contain 'PhysicalDisks'
    }
}
