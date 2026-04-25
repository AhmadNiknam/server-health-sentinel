Describe 'ConfigLoader' {
    BeforeAll {
        $script:RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
        $script:ConfigPath = Join-Path $script:RepoRoot 'config'
        $script:ModulePath = Join-Path $script:RepoRoot 'src/modules/ConfigLoader.psm1'

        Import-Module $script:ModulePath -Force
    }

    It 'validates required server CSV columns' {
        $serverSamplePath = Join-Path $script:ConfigPath 'servers.sample.csv'
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

        Test-CsvRequiredColumns -Path $serverSamplePath -RequiredColumns $requiredColumns | Should -BeTrue
    }

    It 'validates JSON syntax and returns a parsed object' {
        $thresholdSamplePath = Join-Path $script:ConfigPath 'thresholds.sample.json'

        $thresholds = Test-JsonFileValid -Path $thresholdSamplePath

        $thresholds.cpu.warningPercent | Should -Be 80
    }

    It 'imports enabled sample server inventory rows' {
        $serverSamplePath = Join-Path $script:ConfigPath 'servers.sample.csv'

        $servers = @(Import-ServerInventory -Path $serverSamplePath)

        $servers.Count | Should -Be 2
        $servers.ServerName | Should -Contain 'LAB-APP-01'
        $servers.ServerName | Should -Contain 'LAB-DB-01'
        $servers.ServerName | Should -Not -Contain 'LAB-FILE-01'
        $servers[0].Enabled | Should -BeOfType [bool]
    }

    It 'imports enabled sample Azure VM inventory rows' {
        $azureVmSamplePath = Join-Path $script:ConfigPath 'azure-vms.sample.csv'

        $azureVms = @(Import-AzureVmInventory -Path $azureVmSamplePath)

        $azureVms.Count | Should -Be 2
        $azureVms.VmName | Should -Contain 'vm-lab-app-01'
        $azureVms.VmName | Should -Contain 'vm-lab-db-01'
        $azureVms.VmName | Should -Not -Contain 'vm-lab-file-01'
    }

    It 'imports optional hardware endpoints as an empty enabled list by default' {
        $hardwareEndpointSamplePath = Join-Path $script:ConfigPath 'hardware-endpoints.sample.csv'

        $hardwareEndpoints = @(Import-HardwareEndpointInventory -Path $hardwareEndpointSamplePath)

        $hardwareEndpoints.Count | Should -Be 0
    }

    It 'imports thresholds with required major sections' {
        $thresholdSamplePath = Join-Path $script:ConfigPath 'thresholds.sample.json'

        $thresholds = Import-HealthThresholds -Path $thresholdSamplePath
        $sections = @($thresholds.PSObject.Properties.Name)

        $sections | Should -Contain 'cpu'
        $sections | Should -Contain 'memory'
        $sections | Should -Contain 'logicalDisk'
        $sections | Should -Contain 'physicalDisk'
        $sections | Should -Contain 'uptime'
        $sections | Should -Contain 'eventLogs'
        $sections | Should -Contain 'network'
        $sections | Should -Contain 'pendingReboot'
        $sections | Should -Contain 'services'
    }

    It 'imports predictive rules with sample rule groups' {
        $predictiveRulesSamplePath = Join-Path $script:ConfigPath 'predictive-rules.sample.json'

        $predictiveRules = Import-PredictiveRules -Path $predictiveRulesSamplePath
        $ruleGroups = @($predictiveRules.rules.PSObject.Properties.Name)

        $ruleGroups | Should -Contain 'diskStorageTimeouts'
        $ruleGroups | Should -Contain 'diskRetryEvents'
        $ruleGroups | Should -Contain 'fileSystemCorruption'
        $ruleGroups | Should -Contain 'networkLinkIssues'
        $ruleGroups | Should -Contain 'hardwareSensorWarnings'
    }
}
