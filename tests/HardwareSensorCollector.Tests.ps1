Describe 'HardwareSensorCollector' {
    BeforeAll {
        $hardwareModulePath = Join-Path $PSScriptRoot '../src/modules/HardwareSensorCollector.psm1'
        $healthEvaluatorPath = Join-Path $PSScriptRoot '../src/modules/HealthEvaluator.psm1'
        Import-Module $hardwareModulePath -Force
        Import-Module $healthEvaluatorPath -Force
    }

    It 'returns Skipped when no hardware endpoints are enabled' {
        $inventory = @(
            [pscustomobject]@{
                TargetName     = 'LAB-HOST-01'
                Environment    = 'Lab'
                Vendor         = 'Dell'
                ManagementType = 'Redfish'
                Endpoint       = 'https://idrac-lab-host-01.example.local'
                Port           = 443
                UseSsl         = $true
                Enabled        = $false
            }
        )

        $result = @(Invoke-HardwareSensorCheck -HardwareEndpointInventory $inventory)

        $result.Count | Should -Be 1
        $result[0].TargetName | Should -Be 'HardwareSensorCollector'
        $result[0].TargetType | Should -Be 'Hardware'
        $result[0].Status | Should -Be 'Skipped'
        $result[0].Message | Should -Be 'No enabled hardware management endpoints found.'
    }

    It 'returns Skipped readiness for disabled endpoints' {
        $endpoint = [pscustomobject]@{
            TargetName     = 'LAB-HOST-02'
            Environment    = 'Lab'
            Vendor         = 'HPE'
            ManagementType = 'Redfish'
            Endpoint       = 'https://ilo-lab-host-02.example.local'
            Port           = 443
            UseSsl         = $true
            Enabled        = $false
        }

        $result = Get-HardwareEndpointReadiness -HardwareEndpoint $endpoint

        $result.TargetName | Should -Be 'LAB-HOST-02'
        $result.TargetType | Should -Be 'HardwareEndpoint'
        $result.Status | Should -Be 'Skipped'
        $result.EndpointMasked | Should -Be 'https://[redacted-management-endpoint]:443'
    }

    It 'returns Unknown for enabled endpoints with a missing endpoint URI' {
        $endpoint = [pscustomobject]@{
            TargetName     = 'LAB-HOST-03'
            Environment    = 'Lab'
            Vendor         = 'Lenovo'
            ManagementType = 'Redfish'
            Endpoint       = ''
            Port           = 443
            UseSsl         = $true
            Enabled        = $true
        }

        $result = Get-HardwareEndpointReadiness -HardwareEndpoint $endpoint

        $result.Status | Should -Be 'Unknown'
        $result.Message | Should -Match 'no management endpoint URI'
    }

    It 'returns a readiness object with the expected structure' {
        $endpoint = [pscustomobject]@{
            TargetName     = 'LAB-HOST-04'
            Environment    = 'Lab'
            Vendor         = 'Dell'
            ManagementType = 'Redfish'
            Endpoint       = 'https://idrac-lab-host-04.example.local'
            Port           = 443
            UseSsl         = $true
            Enabled        = $true
        }

        $result = Get-HardwareEndpointReadiness -HardwareEndpoint $endpoint
        $propertyNames = @($result.PSObject.Properties.Name)

        $propertyNames | Should -Contain 'TargetName'
        $propertyNames | Should -Contain 'TargetType'
        $propertyNames | Should -Contain 'Vendor'
        $propertyNames | Should -Contain 'ManagementType'
        $propertyNames | Should -Contain 'EndpointMasked'
        $propertyNames | Should -Contain 'Status'
        $propertyNames | Should -Contain 'Message'
        $propertyNames | Should -Contain 'Recommendation'
        $result.Status | Should -Be 'Yellow'
        $result.Message | Should -Match 'future version'
    }

    It 'validates hardware endpoint configuration structure' {
        $inventory = @(
            [pscustomobject]@{
                TargetName     = 'LAB-HOST-05'
                Environment    = 'Lab'
                Vendor         = 'Dell'
                ManagementType = 'Redfish'
                Endpoint       = 'https://idrac-lab-host-05.example.local'
                Port           = 443
                UseSsl         = $true
                Enabled        = $true
            }
        )

        $result = @(Test-HardwareEndpointConfig -HardwareEndpointInventory $inventory)

        $result.Count | Should -Be 1
        $result[0].Status | Should -Be 'Green'
        $result[0].Enabled | Should -Be $true
    }

    It 'creates marked mock hardware sensor test data' {
        $results = @(New-MockHardwareSensorResult -TargetName 'MOCK-HOST-01' -Status 'Red')

        $results.Count | Should -Be 4
        @($results | Where-Object { $_.IsMock -eq $true }).Count | Should -Be 4
        @($results | Where-Object { $_.Source -eq 'TestData' }).Count | Should -Be 4
        @($results.Category) | Should -Contain 'PowerSupply'
        @($results.Category) | Should -Contain 'Fan'
        @($results.Category) | Should -Contain 'Temperature'
        @($results.Category) | Should -Contain 'RAID'
    }

    It 'converts skipped hardware readiness to an informational finding' {
        $result = [pscustomobject]@{
            TargetName     = 'HardwareSensorCollector'
            TargetType     = 'Hardware'
            Vendor         = ''
            ManagementType = ''
            EndpointMasked = ''
            Status         = 'Skipped'
            Message        = 'No enabled hardware management endpoints found.'
            Recommendation = 'Hardware sensor checks are optional.'
        }

        $findings = @(Convert-HardwareSensorResultToFindings -HardwareSensorResult @($result))

        $findings.Count | Should -Be 1
        $findings[0].Category | Should -Be 'Hardware'
        $findings[0].Status | Should -Be 'Skipped'
        $findings[0].Severity | Should -Be 'Informational'
    }

    It 'converts mock critical power supply result to a critical finding' {
        $mockResults = @(New-MockHardwareSensorResult -TargetName 'MOCK-HOST-02' -Status 'Red')
        $powerSupplyResult = @($mockResults | Where-Object { $_.Category -eq 'PowerSupply' })[0]

        $findings = @(Convert-HardwareSensorResultToFindings -HardwareSensorResult @($powerSupplyResult))
        $criticalFinding = @($findings | Where-Object { $_.Category -eq 'PowerSupply' })[0]

        $criticalFinding.Status | Should -Be 'Red'
        $criticalFinding.Severity | Should -Be 'Critical'
        @($findings | Where-Object { $_.CheckName -eq 'Mock Hardware Sensor Data' }).Count | Should -Be 1
    }
}
