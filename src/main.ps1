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
        'StorageHealthCollector.psm1',
        'NetworkHealthCollector.psm1',
        'EventLogRiskAnalyzer.psm1',
        'LocalHealthCollector.psm1',
        'HealthEvaluator.psm1',
        'ReportGenerator.psm1'
    )

    foreach ($moduleName in $moduleNames) {
        $modulePath = Join-Path $PSScriptRoot "modules/$moduleName"
        Import-Module $modulePath -Force
    }

    $thresholds = Import-HealthThresholds -Path $ThresholdsPath
    $predictiveRules = Import-PredictiveRules -Path $PredictiveRulesPath
    $localHealth = Invoke-LocalHealthCheck -Thresholds $thresholds -PredictiveRules $predictiveRules
    $findings = @(Convert-LocalHealthResultToFindings -LocalHealthResult $localHealth)
    $overallScore = Get-OverallHealthScore -Findings $findings
    $maintenanceReadiness = Get-MaintenanceReadinessStatus -Findings $findings

    $reportsPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'reports'
    if (-not (Test-Path -LiteralPath $reportsPath -PathType Container)) {
        $null = New-Item -Path $reportsPath -ItemType Directory -Force
    }

    $rawReportPath = New-ReportFileName -Prefix 'local-health-raw' -Extension 'json' -OutputPath $reportsPath
    $localHealth | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $rawReportPath -Encoding utf8
    $jsonReportPath = Export-HealthJsonReport -RawResult $localHealth -Findings $findings -OverallScore $overallScore -MaintenanceReadiness $maintenanceReadiness -OutputPath $reportsPath
    $csvReportPath = Export-HealthCsvReport -Findings $findings -OutputPath $reportsPath
    $htmlReportPath = Export-HealthHtmlReport -RawResult $localHealth -Findings $findings -OverallScore $overallScore -MaintenanceReadiness $maintenanceReadiness -OutputPath $reportsPath

    Write-Information 'Server Health Sentinel local health check completed.' -InformationAction Continue
    Write-Information "TargetName: $($localHealth.TargetName)" -InformationAction Continue
    Write-Information "Timestamp: $($localHealth.Timestamp)" -InformationAction Continue
    Write-Information "OverallStatus: $($overallScore.OverallStatus)" -InformationAction Continue
    Write-Information "HealthScore: $($overallScore.Score)" -InformationAction Continue
    Write-Information "MaintenanceReadiness: $($maintenanceReadiness.ReadinessStatus)" -InformationAction Continue
    Write-Information "TotalFindings: $($overallScore.FindingCount)" -InformationAction Continue
    Write-Information "RedFindings: $($overallScore.RedCount)" -InformationAction Continue
    Write-Information "YellowFindings: $($overallScore.YellowCount)" -InformationAction Continue
    Write-Information "RawReportPath: $rawReportPath" -InformationAction Continue
    Write-Information "HtmlReportPath: $htmlReportPath" -InformationAction Continue
    Write-Information "CsvReportPath: $csvReportPath" -InformationAction Continue
    Write-Information "JsonReportPath: $jsonReportPath" -InformationAction Continue
    return
}

if ($Mode -eq 'OnPrem') {
    $moduleNames = @(
        'OnPremHealthCollector.psm1',
        'ReportGenerator.psm1',
        'HealthEvaluator.psm1'
    )

    foreach ($moduleName in $moduleNames) {
        $modulePath = Join-Path $PSScriptRoot "modules/$moduleName"
        Import-Module $modulePath -Force
    }

    $thresholds = Import-HealthThresholds -Path $ThresholdsPath
    $serverInventory = @(Import-ServerInventory -Path $ServersPath)
    $onPremHealthResults = @(Invoke-OnPremHealthCheckBatch -ServerInventory $serverInventory -Thresholds $thresholds)
    $findings = @(Convert-OnPremBatchHealthResultToFindings -OnPremHealthResults $onPremHealthResults)
    $overallScore = Get-OverallHealthScore -Findings $findings
    $maintenanceReadiness = Get-MaintenanceReadinessStatus -Findings $findings

    $reportsPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'reports'
    if (-not (Test-Path -LiteralPath $reportsPath -PathType Container)) {
        $null = New-Item -Path $reportsPath -ItemType Directory -Force
    }

    $rawReportPath = New-ReportFileName -Prefix 'onprem-health-raw' -Extension 'json' -OutputPath $reportsPath
    $onPremHealthResults | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $rawReportPath -Encoding utf8
    $jsonReportPath = Export-HealthJsonReport -RawResult $onPremHealthResults -Findings $findings -OverallScore $overallScore -MaintenanceReadiness $maintenanceReadiness -OutputPath $reportsPath -Prefix 'onprem-health-findings' -ReportType 'OnPremHealthFindings'
    $csvReportPath = Export-HealthCsvReport -Findings $findings -OutputPath $reportsPath -Prefix 'onprem-health-findings'
    $htmlReportPath = Export-HealthHtmlReport -RawResult $onPremHealthResults -Findings $findings -OverallScore $overallScore -MaintenanceReadiness $maintenanceReadiness -OutputPath $reportsPath -Prefix 'onprem-health-report'

    Write-Information 'Server Health Sentinel on-prem health check completed.' -InformationAction Continue
    Write-Information 'Mode: OnPrem' -InformationAction Continue
    Write-Information "TotalServersLoaded: $($serverInventory.Count)" -InformationAction Continue
    Write-Information "TotalServersChecked: $($onPremHealthResults.Count)" -InformationAction Continue
    Write-Information "TotalFindings: $($overallScore.FindingCount)" -InformationAction Continue
    Write-Information "RedFindings: $($overallScore.RedCount)" -InformationAction Continue
    Write-Information "YellowFindings: $($overallScore.YellowCount)" -InformationAction Continue
    Write-Information "OverallStatus: $($overallScore.OverallStatus)" -InformationAction Continue
    Write-Information "MaintenanceReadiness: $($maintenanceReadiness.ReadinessStatus)" -InformationAction Continue
    Write-Information "HtmlReportPath: $htmlReportPath" -InformationAction Continue
    Write-Information "CsvReportPath: $csvReportPath" -InformationAction Continue
    Write-Information "JsonReportPath: $jsonReportPath" -InformationAction Continue
    Write-Information "RawReportPath: $rawReportPath" -InformationAction Continue
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
