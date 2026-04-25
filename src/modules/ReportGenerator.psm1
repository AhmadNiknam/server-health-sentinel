<#
ReportGenerator module.

Planned purpose:
Generate HTML, CSV, and JSON reports from normalized health and risk findings.
#>

function New-ReportFileName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Prefix,

        [Parameter(Mandatory)]
        [string]$Extension,

        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    if (-not (Test-Path -LiteralPath $OutputPath -PathType Container)) {
        $null = New-Item -Path $OutputPath -ItemType Directory -Force
    }

    $cleanExtension = $Extension.TrimStart('.')
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    Join-Path $OutputPath "$Prefix-$timestamp.$cleanExtension"
}

function ConvertTo-ReportText {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return ''
    }

    if ($Value -is [string]) {
        return $Value
    }

    if ($Value -is [System.Array]) {
        return (@($Value) -join '; ')
    }

    try {
        return ($Value | ConvertTo-Json -Depth 6 -Compress)
    }
    catch {
        return [string]$Value
    }
}

function ConvertTo-HtmlText {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value
    )

    [System.Net.WebUtility]::HtmlEncode((ConvertTo-ReportText -Value $Value))
}

function Export-HealthJsonReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$RawResult,

        [Parameter(Mandatory)]
        [object[]]$Findings,

        [Parameter(Mandatory)]
        [object]$OverallScore,

        [Parameter(Mandatory)]
        [object]$MaintenanceReadiness,

        [Parameter(Mandatory)]
        [string]$OutputPath,

        [string]$Prefix = 'local-health-findings',

        [string]$ReportType = 'LocalHealthFindings'
    )

    $path = New-ReportFileName -Prefix $Prefix -Extension 'json' -OutputPath $OutputPath
    $report = [pscustomobject]@{
        ReportType           = $ReportType
        GeneratedAt          = Get-Date
        RawResult            = $RawResult
        Findings             = @($Findings)
        OverallScore         = $OverallScore
        MaintenanceReadiness = $MaintenanceReadiness
    }

    $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path -Encoding utf8
    return $path
}

function Export-HealthCsvReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Findings,

        [Parameter(Mandatory)]
        [string]$OutputPath,

        [string]$Prefix = 'local-health-findings'
    )

    $path = New-ReportFileName -Prefix $Prefix -Extension 'csv' -OutputPath $OutputPath
    @($Findings) | Select-Object `
        Timestamp,
        TargetName,
        TargetType,
        Category,
        CheckName,
        Status,
        Severity,
        Message,
        Recommendation,
        @{ Name = 'Evidence'; Expression = { ConvertTo-ReportText -Value $_.Evidence } },
        ConfidenceLevel |
        Export-Csv -LiteralPath $path -NoTypeInformation -Encoding utf8

    return $path
}

function Get-CategorySummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Findings,

        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [scriptblock]$Filter
    )

    $items = @($Findings | Where-Object $Filter)
    $status = if (@($items | Where-Object { $_.Status -eq 'Red' }).Count -gt 0) {
        'Red'
    }
    elseif (@($items | Where-Object { $_.Status -eq 'Yellow' }).Count -gt 0) {
        'Yellow'
    }
    elseif (@($items | Where-Object { $_.Status -eq 'Unknown' }).Count -gt 0) {
        'Unknown'
    }
    elseif ($items.Count -gt 0) {
        'Green'
    }
    else {
        'Unknown'
    }

    [pscustomobject]@{
        Title  = $Title
        Status = $status
        Count  = $items.Count
    }
}

function Export-HealthHtmlReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$RawResult,

        [Parameter(Mandatory)]
        [object[]]$Findings,

        [Parameter(Mandatory)]
        [object]$OverallScore,

        [Parameter(Mandatory)]
        [object]$MaintenanceReadiness,

        [Parameter(Mandatory)]
        [string]$OutputPath,

        [string]$Prefix = 'local-health-report',

        [string]$ReportTitle = 'Health Report'
    )

    $path = New-ReportFileName -Prefix $Prefix -Extension 'html' -OutputPath $OutputPath
    $rawItems = @($RawResult)
    $targetCount = @($Findings | Select-Object -ExpandProperty TargetName -Unique).Count
    if ($targetCount -eq 0 -and $rawItems.Count -gt 0) {
        $targetCount = $rawItems.Count
    }

    $targetNames = @($Findings | Select-Object -ExpandProperty TargetName -Unique | Sort-Object)
    if ($targetNames.Count -eq 0) {
        $targetNames = @($rawItems.TargetName | Sort-Object -Unique)
    }

    $targetTypes = @($Findings | Select-Object -ExpandProperty TargetType -Unique | Sort-Object)
    if ($targetTypes.Count -eq 0) {
        $targetTypes = @($rawItems.TargetType | Sort-Object -Unique)
    }

    $targetName = ConvertTo-HtmlText -Value $(if ($targetNames.Count -le 3) { $targetNames -join ', ' } else { "$($targetNames.Count) targets" })
    $targetType = ConvertTo-HtmlText -Value ($targetTypes -join ', ')
    $runTimestamp = ConvertTo-HtmlText -Value $(if ($rawItems.Count -eq 1) { $rawItems[0].Timestamp } else { Get-Date })
    $safeReportTitle = ConvertTo-HtmlText -Value $ReportTitle

    $localTargetCount = @($Findings | Where-Object { $_.TargetType -eq 'Local' } | Select-Object -ExpandProperty TargetName -Unique).Count
    $onPremTargetCount = @($Findings | Where-Object { $_.TargetType -eq 'OnPrem' } | Select-Object -ExpandProperty TargetName -Unique).Count
    $azureVmTargetCount = @($Findings | Where-Object { $_.TargetType -eq 'AzureVM' } | Select-Object -ExpandProperty TargetName -Unique).Count
    if ($rawItems.Count -eq 1) {
        if ($null -ne $rawItems[0].LocalTargets) { $localTargetCount = [int]$rawItems[0].LocalTargets }
        if ($null -ne $rawItems[0].OnPremTargets) { $onPremTargetCount = [int]$rawItems[0].OnPremTargets }
        if ($null -ne $rawItems[0].AzureVmTargets) { $azureVmTargetCount = [int]$rawItems[0].AzureVmTargets }
        if ($null -ne $rawItems[0].TotalTargetsChecked) { $targetCount = [int]$rawItems[0].TotalTargetsChecked }
    }

    $summaryCards = @(
        [pscustomobject]@{ Title = 'Targets checked'; Status = if ($targetCount -gt 0) { 'Green' } else { 'Unknown' }; Count = $targetCount }
        Get-CategorySummary -Findings $Findings -Title 'CPU' -Filter { $_.Category -eq 'CPU' }
        Get-CategorySummary -Findings $Findings -Title 'Memory' -Filter { $_.Category -eq 'Memory' }
        Get-CategorySummary -Findings $Findings -Title 'Connectivity' -Filter { $_.Category -eq 'Connectivity' }
        Get-CategorySummary -Findings $Findings -Title 'Pending reboot' -Filter { $_.Category -eq 'PendingReboot' }
        Get-CategorySummary -Findings $Findings -Title 'Logical disks' -Filter { $_.Category -eq 'Storage' -and $_.CheckName -like 'Logical Disk*' }
        Get-CategorySummary -Findings $Findings -Title 'Physical disks' -Filter { $_.Category -eq 'Storage' -and $_.CheckName -like 'Physical Disk*' }
        Get-CategorySummary -Findings $Findings -Title 'Network adapters' -Filter { $_.Category -eq 'Network' }
        Get-CategorySummary -Findings $Findings -Title 'Event log risk indicators' -Filter { $_.Category -like 'EventLog:*' }
        Get-CategorySummary -Findings $Findings -Title 'Azure context' -Filter { $_.Category -eq 'AzureContext' }
        Get-CategorySummary -Findings $Findings -Title 'Azure metadata' -Filter { $_.Category -eq 'AzureMetadata' }
        Get-CategorySummary -Findings $Findings -Title 'Azure disks' -Filter { $_.Category -eq 'AzureDisk' }
        Get-CategorySummary -Findings $Findings -Title 'Azure network' -Filter { $_.Category -eq 'AzureNetwork' }
        Get-CategorySummary -Findings $Findings -Title 'Azure guest health' -Filter { $_.Category -eq 'AzureGuestHealth' }
    )

    $targetSummaryRows = (@('Local', 'OnPrem', 'AzureVM', 'HybridMode') | ForEach-Object {
            $currentTargetType = $_
            $items = @($Findings | Where-Object { $_.TargetType -eq $currentTargetType })
            $targets = @($items | Select-Object -ExpandProperty TargetName -Unique)
            @"
<tr>
  <td>$(ConvertTo-HtmlText -Value $currentTargetType)</td>
  <td>$($targets.Count)</td>
  <td>$($items.Count)</td>
  <td>$(@($items | Where-Object { $_.Status -eq 'Red' }).Count)</td>
  <td>$(@($items | Where-Object { $_.Status -eq 'Yellow' }).Count)</td>
  <td>$(@($items | Where-Object { $_.Status -eq 'Green' }).Count)</td>
  <td>$(@($items | Where-Object { $_.Status -eq 'Unknown' }).Count)</td>
</tr>
"@
        }) -join [Environment]::NewLine

    $cardHtml = ($summaryCards | ForEach-Object {
            "<div class='card'><div class='card-title'>$(ConvertTo-HtmlText -Value $_.Title)</div><div class='badge $($_.Status.ToLowerInvariant())'>$(ConvertTo-HtmlText -Value $_.Status)</div><div class='muted'>Findings: $($_.Count)</div></div>"
        }) -join [Environment]::NewLine

    $reasonHtml = (@($MaintenanceReadiness.Reasons) | ForEach-Object { "<li>$(ConvertTo-HtmlText -Value $_)</li>" }) -join [Environment]::NewLine
    if ([string]::IsNullOrWhiteSpace($reasonHtml)) {
        $reasonHtml = '<li>No readiness reasons were provided.</li>'
    }

    $findingRows = (@($Findings) | Sort-Object TargetName, Category, CheckName | ForEach-Object {
            $evidence = ConvertTo-HtmlText -Value $_.Evidence
            @"
<tr>
  <td>$(ConvertTo-HtmlText -Value $_.Timestamp)</td>
  <td>$(ConvertTo-HtmlText -Value $_.TargetName)</td>
  <td>$(ConvertTo-HtmlText -Value $_.TargetType)</td>
  <td>$(ConvertTo-HtmlText -Value $_.Category)</td>
  <td>$(ConvertTo-HtmlText -Value $_.CheckName)</td>
  <td><span class='badge $($_.Status.ToLowerInvariant())'>$(ConvertTo-HtmlText -Value $_.Status)</span></td>
  <td>$(ConvertTo-HtmlText -Value $_.Severity)</td>
  <td>$(ConvertTo-HtmlText -Value $_.Message)</td>
  <td>$(ConvertTo-HtmlText -Value $_.Recommendation)</td>
  <td><code>$evidence</code></td>
  <td>$(ConvertTo-HtmlText -Value $_.ConfidenceLevel)</td>
</tr>
"@
        }) -join [Environment]::NewLine

    $predictiveFindings = @($Findings | Where-Object {
            ($_.Category -eq 'Storage' -and $_.Status -ne 'Green') -or
            ($_.Category -eq 'EventLogRisk' -and $_.Status -ne 'Green') -or
            ($_.Category -like 'EventLog:*' -and $_.Status -ne 'Green') -or
            ($_.Category -eq 'Network' -and $_.Status -ne 'Green') -or
            ($_.Category -like '*Hardware*' -and $_.Status -ne 'Green') -or
            ($_.Category -eq 'AzureGuestHealth' -and $_.Status -ne 'Green')
        })

    $predictiveHtml = if ($predictiveFindings.Count -gt 0) {
        (@($predictiveFindings) | Select-Object -First 20 | ForEach-Object {
                "<li><strong>$(ConvertTo-HtmlText -Value $_.Category) / $(ConvertTo-HtmlText -Value $_.CheckName):</strong> $(ConvertTo-HtmlText -Value $_.Message)</li>"
            }) -join [Environment]::NewLine
    }
    else {
        '<li>No early warning risk indicators were identified in the current finding set.</li>'
    }

    $html = @"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Server Health Sentinel - $safeReportTitle</title>
  <style>
    body { font-family: "Segoe UI", Arial, sans-serif; margin: 0; background: #f4f6f8; color: #1f2933; }
    header { background: #102a43; color: #fff; padding: 28px 36px; }
    main { padding: 28px 36px; }
    section { background: #fff; border: 1px solid #d9e2ec; border-radius: 10px; padding: 22px; margin-bottom: 22px; box-shadow: 0 1px 2px rgba(16, 42, 67, .08); }
    h1, h2 { margin: 0 0 14px; }
    .meta, .muted { color: #627d98; }
    header .meta { color: #d9e2ec; }
    .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(190px, 1fr)); gap: 14px; }
    .card { border: 1px solid #d9e2ec; border-radius: 8px; padding: 16px; background: #fbfcfd; }
    .card-title { font-weight: 700; margin-bottom: 10px; }
    .badge { display: inline-block; border-radius: 999px; padding: 4px 10px; font-weight: 700; font-size: 12px; text-transform: uppercase; letter-spacing: .03em; }
    .green { color: #0f5132; background: #d1e7dd; }
    .yellow { color: #664d03; background: #fff3cd; }
    .red { color: #842029; background: #f8d7da; }
    .unknown { color: #41464b; background: #e2e3e5; }
    .ready { color: #0f5132; background: #d1e7dd; }
    .reviewrequired { color: #664d03; background: #fff3cd; }
    .notready { color: #842029; background: #f8d7da; }
    table { width: 100%; border-collapse: collapse; font-size: 14px; }
    th, td { border-bottom: 1px solid #d9e2ec; padding: 10px; text-align: left; vertical-align: top; }
    th { background: #eef2f7; }
    code { white-space: pre-wrap; word-break: break-word; }
    footer { color: #627d98; text-align: center; padding: 18px 36px 30px; }
  </style>
</head>
<body>
  <header>
    <h1>Server Health Sentinel</h1>
    <h2>$safeReportTitle</h2>
    <div class="meta">Target: $targetName | Type: $targetType | Run timestamp: $runTimestamp</div>
  </header>
  <main>
    <section>
      <h2>Executive Summary</h2>
      <div class="grid">
        <div class="card"><div class="card-title">Overall status</div><span class="badge $($OverallScore.OverallStatus.ToLowerInvariant())">$(ConvertTo-HtmlText -Value $OverallScore.OverallStatus)</span></div>
        <div class="card"><div class="card-title">Health score</div>$(ConvertTo-HtmlText -Value $OverallScore.Score)</div>
        <div class="card"><div class="card-title">Maintenance readiness</div><span class="badge $($MaintenanceReadiness.ReadinessStatus.ToLowerInvariant())">$(ConvertTo-HtmlText -Value $MaintenanceReadiness.ReadinessStatus)</span></div>
        <div class="card"><div class="card-title">Total targets</div>$(ConvertTo-HtmlText -Value $targetCount)</div>
        <div class="card"><div class="card-title">Local targets</div>$(ConvertTo-HtmlText -Value $localTargetCount)</div>
        <div class="card"><div class="card-title">OnPrem targets</div>$(ConvertTo-HtmlText -Value $onPremTargetCount)</div>
        <div class="card"><div class="card-title">Azure VM targets</div>$(ConvertTo-HtmlText -Value $azureVmTargetCount)</div>
        <div class="card"><div class="card-title">Total findings</div>$(ConvertTo-HtmlText -Value $OverallScore.FindingCount)</div>
        <div class="card"><div class="card-title">Red findings</div>$(ConvertTo-HtmlText -Value $OverallScore.RedCount)</div>
        <div class="card"><div class="card-title">Yellow findings</div>$(ConvertTo-HtmlText -Value $OverallScore.YellowCount)</div>
        <div class="card"><div class="card-title">Green findings</div>$(ConvertTo-HtmlText -Value $OverallScore.GreenCount)</div>
        <div class="card"><div class="card-title">Unknown findings</div>$(ConvertTo-HtmlText -Value $OverallScore.UnknownCount)</div>
        <div class="card"><div class="card-title">Critical findings</div>$(ConvertTo-HtmlText -Value $OverallScore.CriticalCount)</div>
        <div class="card"><div class="card-title">High findings</div>$(ConvertTo-HtmlText -Value $OverallScore.HighCount)</div>
        <div class="card"><div class="card-title">Medium findings</div>$(ConvertTo-HtmlText -Value $OverallScore.MediumCount)</div>
      </div>
      <p>$(ConvertTo-HtmlText -Value $OverallScore.SummaryMessage)</p>
    </section>

    <section>
      <h2>Target Summary</h2>
      <table>
        <thead>
          <tr><th>TargetType</th><th>Targets</th><th>Findings</th><th>Red</th><th>Yellow</th><th>Green</th><th>Unknown</th></tr>
        </thead>
        <tbody>
          $targetSummaryRows
        </tbody>
      </table>
    </section>

    <section>
      <h2>Health Summary Cards</h2>
      <div class="grid">
        $cardHtml
      </div>
    </section>

    <section>
      <h2>Maintenance Readiness</h2>
      <p><span class="badge $($MaintenanceReadiness.ReadinessStatus.ToLowerInvariant())">$(ConvertTo-HtmlText -Value $MaintenanceReadiness.ReadinessStatus)</span></p>
      <ul>$reasonHtml</ul>
      <p><strong>Recommendation:</strong> $(ConvertTo-HtmlText -Value $MaintenanceReadiness.Recommendation)</p>
    </section>

    <section>
      <h2>Findings</h2>
      <table>
        <thead>
          <tr><th>Timestamp</th><th>TargetName</th><th>TargetType</th><th>Category</th><th>CheckName</th><th>Status</th><th>Severity</th><th>Message</th><th>Recommendation</th><th>Evidence</th><th>ConfidenceLevel</th></tr>
        </thead>
        <tbody>
          $findingRows
        </tbody>
      </table>
    </section>

    <section>
      <h2>Predictive Maintenance / Early Warning</h2>
      <p>This report identifies risk indicators and early warning signals. It does not guarantee exact failure dates or exact remaining useful life.</p>
      <ul>$predictiveHtml</ul>
    </section>
  </main>
  <footer>
    Generated by Server Health Sentinel | Read-only health check report
  </footer>
</body>
</html>
"@

    $html | Set-Content -LiteralPath $path -Encoding utf8
    return $path
}

Export-ModuleMember -Function @(
    'New-ReportFileName',
    'Export-HealthJsonReport',
    'Export-HealthCsvReport',
    'Export-HealthHtmlReport'
)
