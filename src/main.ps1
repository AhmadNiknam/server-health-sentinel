<#
.SYNOPSIS
    Entry point for Server Health Sentinel.

.DESCRIPTION
    This script will orchestrate read-only health collection, evaluation, and reporting.
    Full implementation is planned for future versions.
#>

[CmdletBinding()]
param(
    [ValidateSet('Local', 'OnPrem', 'Azure', 'Hybrid', 'ConfigTest')]
    [string]$Mode = 'ConfigTest',

    [string]$ServersPath = './config/servers.sample.csv',
    [string]$AzureVmsPath = './config/azure-vms.sample.csv',
    [string]$HardwareEndpointsPath = './config/hardware-endpoints.sample.csv',
    [string]$ThresholdsPath = './config/thresholds.sample.json',
    [string]$PredictiveRulesPath = './config/predictive-rules.sample.json'
)

$configLoaderPath = Join-Path $PSScriptRoot 'modules/ConfigLoader.psm1'
Import-Module $configLoaderPath -Force

if ($Mode -eq 'Local') {
    $moduleNames = @(
        'HealthEvaluator.psm1',
        'StorageHealthCollector.psm1',
        'NetworkHealthCollector.psm1',
        'EventLogRiskAnalyzer.psm1',
        'LocalHealthCollector.psm1'
    )

    foreach ($moduleName in $moduleNames) {
        $modulePath = Join-Path $PSScriptRoot "modules/$moduleName"
        Import-Module $modulePath -Force
    }

    $thresholds = Import-HealthThresholds -Path $ThresholdsPath
    $predictiveRules = Import-PredictiveRules -Path $PredictiveRulesPath
    $localHealth = Invoke-LocalHealthCheck -Thresholds $thresholds -PredictiveRules $predictiveRules

    $reportsPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'reports'
    if (-not (Test-Path -LiteralPath $reportsPath -PathType Container)) {
        $null = New-Item -Path $reportsPath -ItemType Directory -Force
    }

    $rawReportPath = Join-Path $reportsPath 'local-health-raw.json'
    $localHealth | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $rawReportPath -Encoding utf8

    $cpuStatus = $localHealth.OsHealth.Cpu.Status
    $memoryStatus = $localHealth.OsHealth.Memory.Status
    $logicalDiskCount = @($localHealth.StorageHealth.LogicalDisks).Count
    $physicalDiskCount = @($localHealth.StorageHealth.PhysicalDisks | Where-Object { $_.FriendlyName }).Count
    $physicalDiskSummary = if ($physicalDiskCount -gt 0) { [string]$physicalDiskCount } else { 'Unknown' }
    $networkAdapterCount = @($localHealth.NetworkHealth.Adapters | Where-Object { $_.Name }).Count
    $eventLogRiskCount = @($localHealth.EventLogRisk | Where-Object { $_.Status -ne 'Unknown' }).Count

    Write-Information 'Server Health Sentinel local health check completed.' -InformationAction Continue
    Write-Information "TargetName: $($localHealth.TargetName)" -InformationAction Continue
    Write-Information "Timestamp: $($localHealth.Timestamp)" -InformationAction Continue
    Write-Information "CPU status: $cpuStatus" -InformationAction Continue
    Write-Information "Memory status: $memoryStatus" -InformationAction Continue
    Write-Information "Logical disk count: $logicalDiskCount" -InformationAction Continue
    Write-Information "Physical disk count: $physicalDiskSummary" -InformationAction Continue
    Write-Information "Network adapter count: $networkAdapterCount" -InformationAction Continue
    Write-Information "Pending reboot status: $($localHealth.PendingReboot.Status)" -InformationAction Continue
    Write-Information "Event log risk count: $eventLogRiskCount" -InformationAction Continue
    Write-Information "Raw result saved to: $rawReportPath" -InformationAction Continue
    return
}

if ($Mode -ne 'ConfigTest') {
    Write-Information 'Mode is planned for a future phase.' -InformationAction Continue
    return
}

$serverInventory = @(Import-ServerInventory -Path $ServersPath)
$azureVmInventory = @(Import-AzureVmInventory -Path $AzureVmsPath)
$hardwareEndpointInventory = @(Import-HardwareEndpointInventory -Path $HardwareEndpointsPath)
$thresholds = Import-HealthThresholds -Path $ThresholdsPath
$predictiveRules = Import-PredictiveRules -Path $PredictiveRulesPath

$thresholdSections = @($thresholds.PSObject.Properties.Name)
$predictiveRuleGroups = @($predictiveRules.rules.PSObject.Properties.Name)

Write-Information 'Server Health Sentinel configuration test completed.' -InformationAction Continue
Write-Information "Enabled servers count: $($serverInventory.Count)" -InformationAction Continue
Write-Information "Enabled Azure VMs count: $($azureVmInventory.Count)" -InformationAction Continue
Write-Information "Enabled hardware endpoints count: $($hardwareEndpointInventory.Count)" -InformationAction Continue
Write-Information "Threshold sections loaded: $($thresholdSections -join ', ')" -InformationAction Continue
Write-Information "Predictive rule groups loaded: $($predictiveRuleGroups -join ', ')" -InformationAction Continue
