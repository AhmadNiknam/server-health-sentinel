# Server Health Sentinel

Server Health Sentinel is a read-only PowerShell-based hybrid server health and predictive risk reporting tool for Windows Server, on-prem infrastructure, Azure VMs, and optional hardware sensor readiness.

## Problem Statement

Administrators often need a quick pre-maintenance or weekly health report before patching, migration work, incident review, or routine operational handoff. Important signals can be spread across Windows counters, CIM/WMI classes, event logs, storage status, network adapter state, Azure VM metadata, and optional hardware management interfaces.

Enterprise monitoring platforms are powerful and should remain the source of truth for continuous production monitoring. Sometimes admins also need lightweight, scriptable, customizable, report-focused checks that can be run on demand and reviewed as a maintenance readiness package.

Server Health Sentinel provides admin-friendly health findings, maintenance readiness, and early warning indicators without changing the systems being checked.

## What This Project Is and Is Not

Server Health Sentinel is not a replacement for enterprise monitoring platforms like PRTG, SolarWinds, Zabbix, or Datadog. It does not provide real-time alerting, long-term enterprise telemetry storage, escalation workflows, or full monitoring platform coverage.

It is a lightweight complementary automation and reporting tool designed for read-only health checks, readiness reviews, weekly snapshots, lab validation, and professional portfolio demonstration.

## Features

- Local Windows health check
- On-prem Windows Server health check
- Azure VM metadata and guest readiness design
- Hybrid mode across local, on-prem, and Azure inventory
- Storage health checks
- Network adapter health checks
- Event log risk indicators
- Maintenance readiness scoring
- Predictive risk indicators
- Trend history and comparison snapshots
- Optional hardware sensor readiness
- HTML, CSV, and JSON reports
- Pester tests
- GitHub Actions CI

## Architecture

```text
Configuration -> Collector Modules -> Health Evaluator -> Predictive Risk -> Trend Store -> Report Generator
```

The project uses modular PowerShell components for configuration loading, local/on-prem/Azure/hardware collection, health evaluation, predictive risk indicators, trend storage, and report generation.

## Supported Modes

- `ConfigTest`: validates sample configuration and parser readiness.
- `Local`: checks the Windows machine running the tool.
- `OnPrem`: checks Windows Server targets from a CSV inventory using remote management where available.
- `Azure`: checks Azure VM inventory context, metadata, and guest readiness where permissions allow.
- `Hybrid`: combines local, on-prem, Azure, trend, and optional hardware readiness signals into one report.

## Example Commands

```powershell
pwsh ./src/main.ps1 -Mode ConfigTest

pwsh ./src/main.ps1 -Mode Local -HistoryPath ./history

pwsh ./src/main.ps1 -Mode OnPrem -ServersPath ./config/servers.sample.csv -HistoryPath ./history

pwsh ./src/main.ps1 -Mode Azure -AzureVmsPath ./config/azure-vms.sample.csv -HistoryPath ./history

pwsh ./src/main.ps1 -Mode Hybrid -IncludeLocal -ServersPath ./config/servers.sample.csv -AzureVmsPath ./config/azure-vms.sample.csv -HistoryPath ./history

pwsh ./src/main.ps1 -Mode Hybrid -IncludeLocal -IncludeHardware -ServersPath ./config/servers.sample.csv -AzureVmsPath ./config/azure-vms.sample.csv -HardwareEndpointsPath ./config/hardware-endpoints.sample.csv -HistoryPath ./history
```

The sample inventories use fake lab values. They are safe for public demos and should not be replaced in source control with real server names, machine names, IP addresses, subscription IDs, tenant IDs, usernames, or operational details.

## Report Outputs

Server Health Sentinel writes timestamped outputs under `reports/` and optional trend snapshots under `history/`.

- HTML report for browser-based review and executive summary visibility.
- CSV findings for spreadsheets, tickets, and operational handoff notes.
- JSON raw and finding reports for automation and troubleshooting.
- Trend snapshots for comparing current health indicators with previous runs.

Generated reports and history snapshots can contain real environment details, so they are ignored by Git and should not be committed.

## Security Model

Server Health Sentinel is read-only by design.

- No remediation
- No reboots
- No service restarts
- No firewall, registry, disk, network, BIOS, firmware, or Azure resource changes
- No credentials stored in the repository
- Sample config files only
- Real config, reports, and history files are ignored by Git

Run the tool with the least privilege required for the checks you enable. Azure mode requires an existing Az PowerShell authentication context, and guest readiness checks require appropriate Azure VM Run Command permissions.

## Configuration

Start from the committed sample files:

- `config/servers.sample.csv`
- `config/azure-vms.sample.csv`
- `config/hardware-endpoints.sample.csv`
- `config/thresholds.sample.json`
- `config/predictive-rules.sample.json`

For real environments, copy samples to local ignored files such as `config/servers.csv`, `config/azure-vms.csv`, and `config/hardware-endpoints.csv`. Do not commit real config files.

## Testing

The project includes Pester tests and can run PSScriptAnalyzer if it is available in the local environment. GitHub Actions CI is intended to keep the public repository passing.

```powershell
pwsh ./src/scripts/Invoke-Tests.ps1
```

## Limitations

- Hardware health requires management interfaces such as Redfish, Dell iDRAC, HPE iLO, Lenovo XClarity, or approved vendor tooling.
- Azure guest health requires proper Azure permissions, Az PowerShell modules, and VM Run Command support.
- Trend-based risk is rule-based and does not guarantee exact failure dates or exact remaining useful life.
- Remote Windows checks require network connectivity, DNS, WinRM/CIM availability, and appropriate permissions.
- Sample files use fake servers and fake Azure values.

## Roadmap

Planned improvements include:

- Real authenticated Redfish polling
- Secure vault integration
- Teams/email notification
- Azure Automation Runbook version
- Log Analytics export
- Optional remediation workflow with approval
- Linux support
