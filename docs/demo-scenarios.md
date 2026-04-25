# Demo Scenarios

Use these scenarios for GitHub, LinkedIn, resume discussion, or interview walkthroughs. All commands use sample files with fake values.

## Local Pre-Maintenance Health Check

Purpose: Run a quick read-only check on the Windows machine before patching or maintenance.

Command:

```powershell
pwsh ./src/main.ps1 -Mode Local -HistoryPath ./history
```

Expected result: The tool generates local health findings, maintenance readiness, report files, and a trend snapshot.

How an admin would use it: Review the HTML report before starting maintenance to identify pending reboot signals, storage warnings, service issues, network adapter problems, or recent event log risk indicators.

## Hybrid Weekly Health Review

Purpose: Produce one combined report across local, on-prem, and Azure inventory.

Command:

```powershell
pwsh ./src/main.ps1 -Mode Hybrid -IncludeLocal -ServersPath ./config/servers.sample.csv -AzureVmsPath ./config/azure-vms.sample.csv -HistoryPath ./history
```

Expected result: The tool completes the Hybrid run, reports local findings, records expected sample inventory warnings, and writes combined HTML, CSV, JSON, and trend outputs.

How an admin would use it: Share the summary during weekly operations review to discuss current health, unknown visibility gaps, and early warning indicators.

## On-Prem Unreachable Server Review

Purpose: Demonstrate how unreachable or unavailable on-prem targets are handled without stopping the run.

Command:

```powershell
pwsh ./src/main.ps1 -Mode OnPrem -ServersPath ./config/servers.sample.csv -HistoryPath ./history
```

Expected result: Fake sample server names are reported as unreachable or unavailable findings, and the report is still generated.

How an admin would use it: Identify which servers need DNS, network, firewall, WinRM/CIM, or permissions review before maintenance.

## Azure VM Access/Context Issue Report

Purpose: Demonstrate Azure readiness findings when the sample inventory contains fake Azure values or when Az context is missing.

Command:

```powershell
pwsh ./src/main.ps1 -Mode Azure -AzureVmsPath ./config/azure-vms.sample.csv -HistoryPath ./history
```

Expected result: The tool reports Azure module, authentication, subscription context, metadata, or guest readiness findings instead of crashing.

How an admin would use it: Confirm whether the operator has the right Az modules, current authentication context, subscription access, and VM Run Command permissions.

## Trend History Comparison

Purpose: Show directional risk comparison between the current run and the previous snapshot.

Command:

```powershell
pwsh ./src/main.ps1 -Mode Local -HistoryPath ./history
pwsh ./src/main.ps1 -Mode Local -HistoryPath ./history
```

Expected result: The first run creates a baseline snapshot. The second run compares against the previous Local snapshot and reports whether key indicators are improving, stable, worsening, or unknown.

How an admin would use it: Review changes in findings, severity counts, maintenance readiness, and risk indicators over time.

## Hardware Sensor Readiness Design

Purpose: Demonstrate optional hardware readiness without storing credentials or polling real management endpoints.

Command:

```powershell
pwsh ./src/main.ps1 -Mode Hybrid -IncludeLocal -IncludeHardware -ServersPath ./config/servers.sample.csv -AzureVmsPath ./config/azure-vms.sample.csv -HardwareEndpointsPath ./config/hardware-endpoints.sample.csv -HistoryPath ./history
```

Expected result: The sample hardware endpoints are disabled or fake, so the tool reports hardware readiness as skipped or advisory while still completing the Hybrid run.

How an admin would use it: Plan future read-only Redfish/iDRAC/iLO sensor polling and verify that hardware management endpoint data stays out of public source control.
