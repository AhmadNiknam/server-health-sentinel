Describe 'NetworkHealthCollector' {
    BeforeAll {
        $script:ModulePath = Join-Path $PSScriptRoot '../src/modules/NetworkHealthCollector.psm1'
        Import-Module $script:ModulePath -Force
    }

    It 'exports adapter, IP configuration, and network check functions' {
        Get-Command -Name Get-LocalNetworkAdapterHealth -ErrorAction Stop | Should -Not -BeNullOrEmpty
        Get-Command -Name Get-LocalIpConfigurationHealth -ErrorAction Stop | Should -Not -BeNullOrEmpty
        Get-Command -Name Invoke-LocalNetworkHealthCheck -ErrorAction Stop | Should -Not -BeNullOrEmpty
    }

    It 'returns a parent object with adapter and IP configuration collections' {
        $thresholds = [pscustomobject]@{
            network = [pscustomobject]@{
                minimumLinkSpeedMbps     = 1000
                flagDisconnectedAdapters = $true
                flagLowSpeedAdapters     = $true
            }
        }

        $result = Invoke-LocalNetworkHealthCheck -Thresholds $thresholds

        $result.PSObject.Properties.Name | Should -Contain 'Adapters'
        $result.PSObject.Properties.Name | Should -Contain 'IpConfigurations'
    }
}
