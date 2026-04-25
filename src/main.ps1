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
    [string]$PredictiveRulesPath = './config/predictive-rules.sample.json',
    [string]$HistoryPath = './history',

    [switch]$IncludeLocal,
    [switch]$IncludeHardware
)

$configLoaderPath = Join-Path $PSScriptRoot 'modules/ConfigLoader.psm1'
Import-Module $configLoaderPath -Force

function New-HybridExecutionFinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ModeName,

        [Parameter(Mandatory)]
        [ValidateSet('Yellow', 'Red')]
        [string]$Status,

        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter(Mandatory)]
        [string]$Recommendation,

        [AllowNull()]
        [object]$Evidence = ''
    )

    $severity = if ($Status -eq 'Red') { 'High' } else { 'Medium' }
    New-HealthFinding `
        -TargetName $ModeName `
        -TargetType 'HybridMode' `
        -Category 'Execution' `
        -CheckName "$ModeName Mode Execution" `
        -Status $Status `
        -Severity $severity `
        -Message $Message `
        -Recommendation $Recommendation `
        -Evidence $Evidence `
        -ConfidenceLevel 'High'
}

function Invoke-TrendAnalytics {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ModeName,

        [AllowNull()]
        [object]$RawResults,

        [AllowNull()]
        [object[]]$Findings,

        [Parameter(Mandatory)]
        [object]$OverallScore,

        [Parameter(Mandatory)]
        [object]$MaintenanceReadiness,

        [AllowNull()]
        [object]$PredictiveRules,

        [Parameter(Mandatory)]
        [string]$HistoryPath
    )

    $currentSnapshot = New-TrendSnapshot -Mode $ModeName -RawResults $RawResults -Findings $Findings -OverallScore $OverallScore -MaintenanceReadiness $MaintenanceReadiness
    $previousSnapshots = @(Get-LatestTrendSnapshots -HistoryPath $HistoryPath -Count 1 -Mode $ModeName)
    $previousSnapshot = if ($previousSnapshots.Count -gt 0) { $previousSnapshots[0] } else { $null }
    $trendComparison = Compare-TrendSnapshots -CurrentSnapshot $currentSnapshot -PreviousSnapshot $previousSnapshot
    $componentRisk = @(Get-ComponentRiskScore -Findings $Findings)
    $predictiveIndicators = @(Get-PredictiveRiskIndicators -Findings $Findings -PredictiveRules $PredictiveRules)
    $predictiveRiskTrend = @(Compare-PredictiveRiskTrend -CurrentComponentRisk $componentRisk -PreviousSnapshot $previousSnapshot)
    $snapshotPath = Save-TrendSnapshot -Snapshot $currentSnapshot -HistoryPath $HistoryPath

    [pscustomobject]@{
        SnapshotPath             = $snapshotPath
        CurrentSnapshot          = $currentSnapshot
        PreviousSnapshot         = $previousSnapshot
        TrendComparison          = $trendComparison
        ComponentRisk            = @($componentRisk)
        PredictiveRiskIndicators = @($predictiveIndicators)
        PredictiveRiskTrend      = @($predictiveRiskTrend)
    }
}

if ($Mode -eq 'Local') {
    $moduleNames = @(
        'StorageHealthCollector.psm1',
        'NetworkHealthCollector.psm1',
        'EventLogRiskAnalyzer.psm1',
        'LocalHealthCollector.psm1',
        'HealthEvaluator.psm1',
        'ReportGenerator.psm1',
        'TrendStore.psm1',
        'ComponentRiskModel.psm1',
        'PredictiveHealthAnalyzer.psm1'
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
    $trendAnalytics = Invoke-TrendAnalytics -ModeName 'Local' -RawResults $localHealth -Findings $findings -OverallScore $overallScore -MaintenanceReadiness $maintenanceReadiness -PredictiveRules $predictiveRules -HistoryPath $HistoryPath

    $reportsPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'reports'
    if (-not (Test-Path -LiteralPath $reportsPath -PathType Container)) {
        $null = New-Item -Path $reportsPath -ItemType Directory -Force
    }

    $rawReportPath = New-ReportFileName -Prefix 'local-health-raw' -Extension 'json' -OutputPath $reportsPath
    $localHealth | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $rawReportPath -Encoding utf8
    $jsonReportPath = Export-HealthJsonReport -RawResult $localHealth -Findings $findings -OverallScore $overallScore -MaintenanceReadiness $maintenanceReadiness -OutputPath $reportsPath
    $csvReportPath = Export-HealthCsvReport -Findings $findings -OutputPath $reportsPath
    $htmlReportPath = Export-HealthHtmlReport -RawResult $localHealth -Findings $findings -OverallScore $overallScore -MaintenanceReadiness $maintenanceReadiness -OutputPath $reportsPath -TrendComparison $trendAnalytics.TrendComparison -ComponentRisk $trendAnalytics.ComponentRisk -PredictiveRiskIndicators $trendAnalytics.PredictiveRiskIndicators

    Write-Information 'Server Health Sentinel local health check completed.' -InformationAction Continue
    Write-Information "TargetName: $($localHealth.TargetName)" -InformationAction Continue
    Write-Information "Timestamp: $($localHealth.Timestamp)" -InformationAction Continue
    Write-Information "OverallStatus: $($overallScore.OverallStatus)" -InformationAction Continue
    Write-Information "HealthScore: $($overallScore.Score)" -InformationAction Continue
    Write-Information "MaintenanceReadiness: $($maintenanceReadiness.ReadinessStatus)" -InformationAction Continue
    Write-Information "TotalFindings: $($overallScore.FindingCount)" -InformationAction Continue
    Write-Information "RedFindings: $($overallScore.RedCount)" -InformationAction Continue
    Write-Information "YellowFindings: $($overallScore.YellowCount)" -InformationAction Continue
    Write-Information "TrendSnapshotPath: $($trendAnalytics.SnapshotPath)" -InformationAction Continue
    Write-Information "RiskTrend: $($trendAnalytics.TrendComparison.RiskTrend)" -InformationAction Continue
    Write-Information "TrendReason: $($trendAnalytics.TrendComparison.SummaryMessage)" -InformationAction Continue
    Write-Information "HealthScoreChange: $($trendAnalytics.TrendComparison.HealthScoreChange)" -InformationAction Continue
    Write-Information "RedFindingChange: $($trendAnalytics.TrendComparison.RedFindingChange)" -InformationAction Continue
    Write-Information "CriticalFindingChange: $($trendAnalytics.TrendComparison.CriticalFindingChange)" -InformationAction Continue
    Write-Information "HighFindingChange: $($trendAnalytics.TrendComparison.HighFindingChange)" -InformationAction Continue
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
        'HealthEvaluator.psm1',
        'TrendStore.psm1',
        'ComponentRiskModel.psm1',
        'PredictiveHealthAnalyzer.psm1'
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
    $trendAnalytics = Invoke-TrendAnalytics -ModeName 'OnPrem' -RawResults $onPremHealthResults -Findings $findings -OverallScore $overallScore -MaintenanceReadiness $maintenanceReadiness -PredictiveRules $null -HistoryPath $HistoryPath

    $reportsPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'reports'
    if (-not (Test-Path -LiteralPath $reportsPath -PathType Container)) {
        $null = New-Item -Path $reportsPath -ItemType Directory -Force
    }

    $rawReportPath = New-ReportFileName -Prefix 'onprem-health-raw' -Extension 'json' -OutputPath $reportsPath
    $onPremHealthResults | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $rawReportPath -Encoding utf8
    $jsonReportPath = Export-HealthJsonReport -RawResult $onPremHealthResults -Findings $findings -OverallScore $overallScore -MaintenanceReadiness $maintenanceReadiness -OutputPath $reportsPath -Prefix 'onprem-health-findings' -ReportType 'OnPremHealthFindings'
    $csvReportPath = Export-HealthCsvReport -Findings $findings -OutputPath $reportsPath -Prefix 'onprem-health-findings'
    $htmlReportPath = Export-HealthHtmlReport -RawResult $onPremHealthResults -Findings $findings -OverallScore $overallScore -MaintenanceReadiness $maintenanceReadiness -OutputPath $reportsPath -Prefix 'onprem-health-report' -TrendComparison $trendAnalytics.TrendComparison -ComponentRisk $trendAnalytics.ComponentRisk -PredictiveRiskIndicators $trendAnalytics.PredictiveRiskIndicators

    Write-Information 'Server Health Sentinel on-prem health check completed.' -InformationAction Continue
    Write-Information 'Mode: OnPrem' -InformationAction Continue
    Write-Information "TotalServersLoaded: $($serverInventory.Count)" -InformationAction Continue
    Write-Information "TotalServersChecked: $($onPremHealthResults.Count)" -InformationAction Continue
    Write-Information "TotalFindings: $($overallScore.FindingCount)" -InformationAction Continue
    Write-Information "RedFindings: $($overallScore.RedCount)" -InformationAction Continue
    Write-Information "YellowFindings: $($overallScore.YellowCount)" -InformationAction Continue
    Write-Information "OverallStatus: $($overallScore.OverallStatus)" -InformationAction Continue
    Write-Information "MaintenanceReadiness: $($maintenanceReadiness.ReadinessStatus)" -InformationAction Continue
    Write-Information "TrendSnapshotPath: $($trendAnalytics.SnapshotPath)" -InformationAction Continue
    Write-Information "RiskTrend: $($trendAnalytics.TrendComparison.RiskTrend)" -InformationAction Continue
    Write-Information "TrendReason: $($trendAnalytics.TrendComparison.SummaryMessage)" -InformationAction Continue
    Write-Information "HealthScoreChange: $($trendAnalytics.TrendComparison.HealthScoreChange)" -InformationAction Continue
    Write-Information "RedFindingChange: $($trendAnalytics.TrendComparison.RedFindingChange)" -InformationAction Continue
    Write-Information "CriticalFindingChange: $($trendAnalytics.TrendComparison.CriticalFindingChange)" -InformationAction Continue
    Write-Information "HighFindingChange: $($trendAnalytics.TrendComparison.HighFindingChange)" -InformationAction Continue
    Write-Information "HtmlReportPath: $htmlReportPath" -InformationAction Continue
    Write-Information "CsvReportPath: $csvReportPath" -InformationAction Continue
    Write-Information "JsonReportPath: $jsonReportPath" -InformationAction Continue
    Write-Information "RawReportPath: $rawReportPath" -InformationAction Continue
    return
}

if ($Mode -eq 'Azure') {
    $moduleNames = @(
        'AzureVmHealthCollector.psm1',
        'ReportGenerator.psm1',
        'HealthEvaluator.psm1',
        'TrendStore.psm1',
        'ComponentRiskModel.psm1',
        'PredictiveHealthAnalyzer.psm1'
    )

    foreach ($moduleName in $moduleNames) {
        $modulePath = Join-Path $PSScriptRoot "modules/$moduleName"
        Import-Module $modulePath -Force
    }

    $thresholds = Import-HealthThresholds -Path $ThresholdsPath
    $predictiveRules = Import-PredictiveRules -Path $PredictiveRulesPath
    $azureVmInventory = @(Import-AzureVmInventory -Path $AzureVmsPath)
    $azureHealthResults = @(Invoke-AzureVmHealthCheckBatch -AzureVmInventory $azureVmInventory -Thresholds $thresholds -PredictiveRules $predictiveRules)
    $findings = @(Convert-AzureVmBatchHealthResultToFindings -AzureVmHealthResults $azureHealthResults)
    $overallScore = Get-OverallHealthScore -Findings $findings
    $maintenanceReadiness = Get-MaintenanceReadinessStatus -Findings $findings
    $trendAnalytics = Invoke-TrendAnalytics -ModeName 'Azure' -RawResults $azureHealthResults -Findings $findings -OverallScore $overallScore -MaintenanceReadiness $maintenanceReadiness -PredictiveRules $predictiveRules -HistoryPath $HistoryPath

    $reportsPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'reports'
    if (-not (Test-Path -LiteralPath $reportsPath -PathType Container)) {
        $null = New-Item -Path $reportsPath -ItemType Directory -Force
    }

    $rawReportPath = New-ReportFileName -Prefix 'azure-health-raw' -Extension 'json' -OutputPath $reportsPath
    $azureHealthResults | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $rawReportPath -Encoding utf8
    $jsonReportPath = Export-HealthJsonReport -RawResult $azureHealthResults -Findings $findings -OverallScore $overallScore -MaintenanceReadiness $maintenanceReadiness -OutputPath $reportsPath -Prefix 'azure-health-findings' -ReportType 'AzureVmHealthFindings'
    $csvReportPath = Export-HealthCsvReport -Findings $findings -OutputPath $reportsPath -Prefix 'azure-health-findings'
    $htmlReportPath = Export-HealthHtmlReport -RawResult $azureHealthResults -Findings $findings -OverallScore $overallScore -MaintenanceReadiness $maintenanceReadiness -OutputPath $reportsPath -Prefix 'azure-health-report' -TrendComparison $trendAnalytics.TrendComparison -ComponentRisk $trendAnalytics.ComponentRisk -PredictiveRiskIndicators $trendAnalytics.PredictiveRiskIndicators

    Write-Information 'Server Health Sentinel Azure VM health check completed.' -InformationAction Continue
    Write-Information 'Mode: Azure' -InformationAction Continue
    Write-Information "TotalAzureVmsLoaded: $($azureVmInventory.Count)" -InformationAction Continue
    Write-Information "TotalAzureVmsChecked: $($azureHealthResults.Count)" -InformationAction Continue
    Write-Information "TotalFindings: $($overallScore.FindingCount)" -InformationAction Continue
    Write-Information "RedFindings: $($overallScore.RedCount)" -InformationAction Continue
    Write-Information "YellowFindings: $($overallScore.YellowCount)" -InformationAction Continue
    Write-Information "OverallStatus: $($overallScore.OverallStatus)" -InformationAction Continue
    Write-Information "MaintenanceReadiness: $($maintenanceReadiness.ReadinessStatus)" -InformationAction Continue
    Write-Information "TrendSnapshotPath: $($trendAnalytics.SnapshotPath)" -InformationAction Continue
    Write-Information "RiskTrend: $($trendAnalytics.TrendComparison.RiskTrend)" -InformationAction Continue
    Write-Information "TrendReason: $($trendAnalytics.TrendComparison.SummaryMessage)" -InformationAction Continue
    Write-Information "HealthScoreChange: $($trendAnalytics.TrendComparison.HealthScoreChange)" -InformationAction Continue
    Write-Information "RedFindingChange: $($trendAnalytics.TrendComparison.RedFindingChange)" -InformationAction Continue
    Write-Information "CriticalFindingChange: $($trendAnalytics.TrendComparison.CriticalFindingChange)" -InformationAction Continue
    Write-Information "HighFindingChange: $($trendAnalytics.TrendComparison.HighFindingChange)" -InformationAction Continue
    Write-Information "HtmlReportPath: $htmlReportPath" -InformationAction Continue
    Write-Information "CsvReportPath: $csvReportPath" -InformationAction Continue
    Write-Information "JsonReportPath: $jsonReportPath" -InformationAction Continue
    Write-Information "RawReportPath: $rawReportPath" -InformationAction Continue
    return
}

if ($Mode -eq 'Hybrid') {
    $moduleNames = @(
        'StorageHealthCollector.psm1',
        'NetworkHealthCollector.psm1',
        'EventLogRiskAnalyzer.psm1',
        'LocalHealthCollector.psm1',
        'OnPremHealthCollector.psm1',
        'AzureVmHealthCollector.psm1',
        'HardwareSensorCollector.psm1',
        'HealthEvaluator.psm1',
        'ReportGenerator.psm1',
        'TrendStore.psm1',
        'ComponentRiskModel.psm1',
        'PredictiveHealthAnalyzer.psm1'
    )

    foreach ($moduleName in $moduleNames) {
        $modulePath = Join-Path $PSScriptRoot "modules/$moduleName"
        Import-Module $modulePath -Force
    }

    $thresholds = Import-HealthThresholds -Path $ThresholdsPath
    $predictiveRules = Import-PredictiveRules -Path $PredictiveRulesPath

    $allRawResults = [System.Collections.Generic.List[object]]::new()
    $allFindings = [System.Collections.Generic.List[object]]::new()
    $modeSummaries = [System.Collections.Generic.List[object]]::new()

    $localTargetCount = 0
    $onPremTargetCount = 0
    $azureVmTargetCount = 0
    $hardwareEndpointTargetCount = 0

    if ($IncludeLocal.IsPresent) {
        try {
            $localHealth = Invoke-LocalHealthCheck -Thresholds $thresholds -PredictiveRules $predictiveRules
            $localFindings = @(Convert-LocalHealthResultToFindings -LocalHealthResult $localHealth)
            $allRawResults.Add($localHealth)
            foreach ($finding in $localFindings) { $allFindings.Add($finding) }
            $localTargetCount = 1
            $modeSummaries.Add([pscustomobject]@{
                    Mode         = 'Local'
                    Status       = 'Completed'
                    Targets      = $localTargetCount
                    FindingCount = $localFindings.Count
                    Message      = 'Local health check completed.'
                })
        }
        catch {
            $finding = New-HybridExecutionFinding `
                -ModeName 'Local' `
                -Status 'Red' `
                -Message "Hybrid Local mode failed: $($_.Exception.Message)" `
                -Recommendation 'Review local collector prerequisites and run Local mode separately for focused troubleshooting.' `
                -Evidence ([pscustomobject]@{ Mode = 'Local'; ErrorType = $_.Exception.GetType().FullName })
            $allFindings.Add($finding)
            $modeSummaries.Add([pscustomobject]@{
                    Mode         = 'Local'
                    Status       = 'Failed'
                    Targets      = 0
                    FindingCount = 1
                    Message      = $finding.Message
                })
        }
    }
    else {
        $modeSummaries.Add([pscustomobject]@{
                Mode         = 'Local'
                Status       = 'Skipped'
                Targets      = 0
                FindingCount = 0
                Message      = 'Local health check was skipped because -IncludeLocal was not provided.'
            })
    }

    if (Test-Path -LiteralPath $ServersPath -PathType Leaf) {
        try {
            $serverInventory = @(Import-ServerInventory -Path $ServersPath)
            $onPremHealthResults = @(Invoke-OnPremHealthCheckBatch -ServerInventory $serverInventory -Thresholds $thresholds)
            $onPremFindings = @(Convert-OnPremBatchHealthResultToFindings -OnPremHealthResults $onPremHealthResults)
            foreach ($result in $onPremHealthResults) { $allRawResults.Add($result) }
            foreach ($finding in $onPremFindings) { $allFindings.Add($finding) }
            $onPremTargetCount = $onPremHealthResults.Count
            $modeSummaries.Add([pscustomobject]@{
                    Mode         = 'OnPrem'
                    Status       = 'Completed'
                    Targets      = $onPremTargetCount
                    FindingCount = $onPremFindings.Count
                    Message      = 'OnPrem health check batch completed.'
                })
        }
        catch {
            $finding = New-HybridExecutionFinding `
                -ModeName 'OnPrem' `
                -Status 'Red' `
                -Message "Hybrid OnPrem mode failed: $($_.Exception.Message)" `
                -Recommendation 'Review the server inventory path, CSV columns, DNS, network connectivity, and WinRM/CIM access, then run OnPrem mode separately if needed.' `
                -Evidence ([pscustomobject]@{ Mode = 'OnPrem'; ServersPath = $ServersPath; ErrorType = $_.Exception.GetType().FullName })
            $allFindings.Add($finding)
            $modeSummaries.Add([pscustomobject]@{
                    Mode         = 'OnPrem'
                    Status       = 'Failed'
                    Targets      = 0
                    FindingCount = 1
                    Message      = $finding.Message
                })
        }
    }
    else {
        $finding = New-HybridExecutionFinding `
            -ModeName 'OnPrem' `
            -Status 'Yellow' `
            -Message "Hybrid OnPrem mode was skipped because the server inventory file was not found: $ServersPath" `
            -Recommendation 'Provide a valid -ServersPath file to include on-prem servers in the Hybrid run.' `
            -Evidence ([pscustomobject]@{ Mode = 'OnPrem'; ServersPath = $ServersPath })
        $allFindings.Add($finding)
        $modeSummaries.Add([pscustomobject]@{
                Mode         = 'OnPrem'
                Status       = 'Skipped'
                Targets      = 0
                FindingCount = 1
                Message      = $finding.Message
            })
    }

    if (Test-Path -LiteralPath $AzureVmsPath -PathType Leaf) {
        try {
            $azureVmInventory = @(Import-AzureVmInventory -Path $AzureVmsPath)
            $azureHealthResults = @(Invoke-AzureVmHealthCheckBatch -AzureVmInventory $azureVmInventory -Thresholds $thresholds -PredictiveRules $predictiveRules)
            $azureFindings = @(Convert-AzureVmBatchHealthResultToFindings -AzureVmHealthResults $azureHealthResults)
            foreach ($result in $azureHealthResults) { $allRawResults.Add($result) }
            foreach ($finding in $azureFindings) { $allFindings.Add($finding) }
            $azureVmTargetCount = $azureHealthResults.Count
            $modeSummaries.Add([pscustomobject]@{
                    Mode         = 'Azure'
                    Status       = 'Completed'
                    Targets      = $azureVmTargetCount
                    FindingCount = $azureFindings.Count
                    Message      = 'Azure VM health check batch completed.'
                })
        }
        catch {
            $finding = New-HybridExecutionFinding `
                -ModeName 'Azure' `
                -Status 'Red' `
                -Message "Hybrid Azure mode failed: $($_.Exception.Message)" `
                -Recommendation 'Review the Azure VM inventory path, CSV columns, Az module availability, authentication context, and read-only access, then run Azure mode separately if needed.' `
                -Evidence ([pscustomobject]@{ Mode = 'Azure'; AzureVmsPath = $AzureVmsPath; ErrorType = $_.Exception.GetType().FullName })
            $allFindings.Add($finding)
            $modeSummaries.Add([pscustomobject]@{
                    Mode         = 'Azure'
                    Status       = 'Failed'
                    Targets      = 0
                    FindingCount = 1
                    Message      = $finding.Message
                })
        }
    }
    else {
        $finding = New-HybridExecutionFinding `
            -ModeName 'Azure' `
            -Status 'Yellow' `
            -Message "Hybrid Azure mode was skipped because the Azure VM inventory file was not found: $AzureVmsPath" `
            -Recommendation 'Provide a valid -AzureVmsPath file to include Azure VMs in the Hybrid run.' `
            -Evidence ([pscustomobject]@{ Mode = 'Azure'; AzureVmsPath = $AzureVmsPath })
        $allFindings.Add($finding)
        $modeSummaries.Add([pscustomobject]@{
                Mode         = 'Azure'
                Status       = 'Skipped'
                Targets      = 0
                FindingCount = 1
                Message      = $finding.Message
            })
    }

    if ($IncludeHardware.IsPresent) {
        if (Test-Path -LiteralPath $HardwareEndpointsPath -PathType Leaf) {
            try {
                $hardwareEndpointInventory = @(Import-HardwareEndpointInventory -Path $HardwareEndpointsPath)
                $hardwareResults = @(Invoke-HardwareSensorCheck -HardwareEndpointInventory $hardwareEndpointInventory)
                $hardwareFindings = @(Convert-HardwareSensorResultToFindings -HardwareSensorResult $hardwareResults)
                foreach ($result in $hardwareResults) { $allRawResults.Add($result) }
                foreach ($finding in $hardwareFindings) { $allFindings.Add($finding) }
                $hardwareEndpointTargetCount = @($hardwareResults | Where-Object { $_.TargetType -eq 'HardwareEndpoint' }).Count
                $modeSummaries.Add([pscustomobject]@{
                        Mode         = 'Hardware'
                        Status       = if (@($hardwareResults | Where-Object { $_.Status -eq 'Skipped' }).Count -eq $hardwareResults.Count) { 'Skipped' } else { 'Completed' }
                        Targets      = $hardwareEndpointTargetCount
                        FindingCount = $hardwareFindings.Count
                        Message      = if ($hardwareEndpointTargetCount -eq 0) { 'Hardware sensor readiness skipped because no enabled endpoints were found.' } else { 'Hardware sensor readiness completed for enabled endpoints.' }
                    })
            }
            catch {
                $finding = New-HybridExecutionFinding `
                    -ModeName 'Hardware' `
                    -Status 'Red' `
                    -Message "Hybrid Hardware mode failed: $($_.Exception.Message)" `
                    -Recommendation 'Review the hardware endpoint inventory path and CSV columns. Hardware checks are optional and should use local ignored config files only.' `
                    -Evidence ([pscustomobject]@{ Mode = 'Hardware'; HardwareEndpointsPath = $HardwareEndpointsPath; ErrorType = $_.Exception.GetType().FullName })
                $allFindings.Add($finding)
                $modeSummaries.Add([pscustomobject]@{
                        Mode         = 'Hardware'
                        Status       = 'Failed'
                        Targets      = 0
                        FindingCount = 1
                        Message      = $finding.Message
                    })
            }
        }
        else {
            $hardwareSkipped = [pscustomobject]@{
                TargetName     = 'HardwareSensorCollector'
                TargetType     = 'Hardware'
                Vendor         = ''
                ManagementType = ''
                EndpointMasked = ''
                Status         = 'Skipped'
                Message        = "Hardware sensor readiness skipped because the hardware endpoint inventory file was not found: $HardwareEndpointsPath"
                Recommendation = 'Provide a local ignored hardware endpoint inventory file only when read-only hardware management checks are intentionally enabled.'
            }
            $hardwareFindings = @(Convert-HardwareSensorResultToFindings -HardwareSensorResult @($hardwareSkipped))
            $allRawResults.Add($hardwareSkipped)
            foreach ($finding in $hardwareFindings) { $allFindings.Add($finding) }
            $modeSummaries.Add([pscustomobject]@{
                    Mode         = 'Hardware'
                    Status       = 'Skipped'
                    Targets      = 0
                    FindingCount = $hardwareFindings.Count
                    Message      = $hardwareSkipped.Message
                })
        }
    }
    else {
        $modeSummaries.Add([pscustomobject]@{
                Mode         = 'Hardware'
                Status       = 'Skipped'
                Targets      = 0
                FindingCount = 0
                Message      = 'Hardware sensor readiness was skipped because -IncludeHardware was not provided.'
            })
    }

    $combinedFindings = @($allFindings)
    $overallScore = Get-OverallHealthScore -Findings $combinedFindings
    $maintenanceReadiness = Get-MaintenanceReadinessStatus -Findings $combinedFindings
    $totalTargetsChecked = $localTargetCount + $onPremTargetCount + $azureVmTargetCount + $hardwareEndpointTargetCount

    $hybridRawResult = [pscustomobject]@{
        Mode                = 'Hybrid'
        Timestamp           = Get-Date
        IncludeLocal        = [bool]$IncludeLocal.IsPresent
        IncludeHardware     = [bool]$IncludeHardware.IsPresent
        TotalTargetsChecked = $totalTargetsChecked
        LocalTargets        = $localTargetCount
        OnPremTargets       = $onPremTargetCount
        AzureVmTargets      = $azureVmTargetCount
        HardwareTargets     = $hardwareEndpointTargetCount
        ModeSummaries       = @($modeSummaries)
        Results             = @($allRawResults)
    }
    $trendAnalytics = Invoke-TrendAnalytics -ModeName 'Hybrid' -RawResults $hybridRawResult -Findings $combinedFindings -OverallScore $overallScore -MaintenanceReadiness $maintenanceReadiness -PredictiveRules $predictiveRules -HistoryPath $HistoryPath

    $reportsPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'reports'
    if (-not (Test-Path -LiteralPath $reportsPath -PathType Container)) {
        $null = New-Item -Path $reportsPath -ItemType Directory -Force
    }

    $rawReportPath = New-ReportFileName -Prefix 'hybrid-health-raw' -Extension 'json' -OutputPath $reportsPath
    $hybridRawResult | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $rawReportPath -Encoding utf8
    $jsonReportPath = Export-HealthJsonReport -RawResult $hybridRawResult -Findings $combinedFindings -OverallScore $overallScore -MaintenanceReadiness $maintenanceReadiness -OutputPath $reportsPath -Prefix 'hybrid-health-findings' -ReportType 'HybridHealthFindings'
    $csvReportPath = Export-HealthCsvReport -Findings $combinedFindings -OutputPath $reportsPath -Prefix 'hybrid-health-findings'
    $htmlReportPath = Export-HealthHtmlReport -RawResult $hybridRawResult -Findings $combinedFindings -OverallScore $overallScore -MaintenanceReadiness $maintenanceReadiness -OutputPath $reportsPath -Prefix 'hybrid-health-report' -ReportTitle 'Hybrid Health Report' -TrendComparison $trendAnalytics.TrendComparison -ComponentRisk $trendAnalytics.ComponentRisk -PredictiveRiskIndicators $trendAnalytics.PredictiveRiskIndicators

    Write-Information 'Server Health Sentinel hybrid health check completed.' -InformationAction Continue
    Write-Information 'Mode: Hybrid' -InformationAction Continue
    Write-Information "LocalIncluded: $([bool]$IncludeLocal.IsPresent)" -InformationAction Continue
    Write-Information "HardwareIncluded: $([bool]$IncludeHardware.IsPresent)" -InformationAction Continue
    Write-Information "TotalTargetsChecked: $totalTargetsChecked" -InformationAction Continue
    Write-Information "LocalTargets: $localTargetCount" -InformationAction Continue
    Write-Information "OnPremTargets: $onPremTargetCount" -InformationAction Continue
    Write-Information "AzureVmTargets: $azureVmTargetCount" -InformationAction Continue
    Write-Information "HardwareEndpointTargets: $hardwareEndpointTargetCount" -InformationAction Continue
    Write-Information "TotalFindings: $($overallScore.FindingCount)" -InformationAction Continue
    Write-Information "GreenFindings: $($overallScore.GreenCount)" -InformationAction Continue
    Write-Information "YellowFindings: $($overallScore.YellowCount)" -InformationAction Continue
    Write-Information "RedFindings: $($overallScore.RedCount)" -InformationAction Continue
    Write-Information "UnknownFindings: $($overallScore.UnknownCount)" -InformationAction Continue
    Write-Information "CriticalFindings: $($overallScore.CriticalCount)" -InformationAction Continue
    Write-Information "HighFindings: $($overallScore.HighCount)" -InformationAction Continue
    Write-Information "MediumFindings: $($overallScore.MediumCount)" -InformationAction Continue
    Write-Information "OverallStatus: $($overallScore.OverallStatus)" -InformationAction Continue
    Write-Information "HealthScore: $($overallScore.Score)" -InformationAction Continue
    Write-Information "MaintenanceReadiness: $($maintenanceReadiness.ReadinessStatus)" -InformationAction Continue
    Write-Information "TrendSnapshotPath: $($trendAnalytics.SnapshotPath)" -InformationAction Continue
    Write-Information "RiskTrend: $($trendAnalytics.TrendComparison.RiskTrend)" -InformationAction Continue
    Write-Information "TrendReason: $($trendAnalytics.TrendComparison.SummaryMessage)" -InformationAction Continue
    Write-Information "HealthScoreChange: $($trendAnalytics.TrendComparison.HealthScoreChange)" -InformationAction Continue
    Write-Information "RedFindingChange: $($trendAnalytics.TrendComparison.RedFindingChange)" -InformationAction Continue
    Write-Information "CriticalFindingChange: $($trendAnalytics.TrendComparison.CriticalFindingChange)" -InformationAction Continue
    Write-Information "HighFindingChange: $($trendAnalytics.TrendComparison.HighFindingChange)" -InformationAction Continue
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
