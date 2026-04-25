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

if ($Mode -ne 'ConfigTest') {
    Write-Information 'Mode is planned for a future phase.' -InformationAction Continue
    return
}

$configLoaderPath = Join-Path $PSScriptRoot 'modules/ConfigLoader.psm1'
Import-Module $configLoaderPath -Force

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
