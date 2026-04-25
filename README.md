# Server Health Sentinel

Server Health Sentinel is a read-only hybrid server health and predictive maintenance assistant for Windows Server, Azure VM, and on-prem infrastructure.

## Problem Statement

System and network administrators often need a quick, repeatable way to understand whether servers are healthy before small warning signs become outages. Health data is usually spread across Windows counters, CIM/WMI classes, event logs, storage signals, network adapter state, Azure VM metadata, and optional hardware management interfaces.

Server Health Sentinel aims to collect those signals into clear reports without changing the target systems.

## Why This Tool Is Useful

- Gives administrators a practical health snapshot across local, on-prem, Azure, and hybrid environments.
- Keeps checks read-only so it can be used safely during triage, audits, and routine maintenance.
- Produces HTML, CSV, and JSON outputs for human review and automation pipelines.
- Creates a foundation for early warning indicators based on repeated errors, disk warnings, adapter instability, and hardware sensor alerts.
- Encourages clean operational habits with sample configuration files, tests, script analysis, and CI.

## Main Features

- Local Windows server health checks.
- Storage health checks for logical disks and physical disk indicators where available.
- Network adapter and port health checks.
- Azure VM metadata and guest health checks through Az PowerShell and Azure VM Run Command.
- Optional hardware sensor collection through Redfish, iDRAC, iLO, or vendor-specific tools.
- Predictive maintenance architecture using failure risk indicators rather than unsupported exact failure dates.
- HTML, CSV, and JSON reporting.
- Pester test structure and PSScriptAnalyzer support.

## Supported Modes Planned

- Local
- OnPrem
- Azure
- Hybrid

## Supported Check Categories

- OS health
- Storage health
- Network adapter / port health
- Azure VM health
- Optional physical hardware sensor health
- Predictive maintenance and early warning

## Technology Stack

- PowerShell 7+
- Modular PowerShell design
- CIM/WMI for local and on-prem Windows Server checks
- Az PowerShell module for Azure VM checks
- Azure VM Run Command for in-guest Azure VM checks
- HTML, CSV, and JSON reporting
- Pester tests
- PSScriptAnalyzer
- GitHub Actions CI

## MVP Scope

Version 0.1.0 focuses on local Windows health checks, storage health, network adapter health, basic event log review, and report generation. The first release is intended to establish the project structure, public interface, and reporting flow before adding remote, Azure, hardware, and trend-based features.

## Security Note

Server Health Sentinel is read-only by default. It must not remediate issues, reboot servers, restart services, modify firewall rules, change network settings, alter disks, edit the registry, or modify Azure resources.

Do not commit credentials, secrets, tokens, tenant IDs, subscription IDs, or real server names. Only sample configuration files belong in source control.

## Configuration

The `config/*.sample.*` files are safe examples with fake lab values. Real local configuration files should be created by copying the samples and then editing the copies for your environment:

- Copy `config/servers.sample.csv` to `config/servers.csv`.
- Copy `config/azure-vms.sample.csv` to `config/azure-vms.csv`.
- Copy `config/hardware-endpoints.sample.csv` to `config/hardware-endpoints.csv`.
- Copy `config/thresholds.sample.json` to `config/thresholds.json`.
- Copy `config/predictive-rules.sample.json` to `config/predictive-rules.json`.

Real config files are ignored by Git. Keep only sample config files in source control, and do not store credentials, secrets, tokens, tenant IDs, subscription IDs, or other sensitive values in any config file.

To validate the sample configuration files:

```powershell
pwsh ./src/main.ps1 -Mode ConfigTest
```

## Local Health Check

Local Health Check mode collects a read-only health snapshot from the Windows machine where the script is running. It is intended for quick local triage and baseline reporting without making changes to the system.

It checks CPU usage, memory usage, uptime, configured critical services, pending reboot indicators, fixed logical disks, physical disk health where available, network adapter status, IP configuration, and recent System/Application event log risk indicators.

Example command:

```powershell
pwsh ./src/main.ps1 -Mode Local
```

The raw structured result is saved to a timestamped JSON file under `reports/`.

This mode is read-only and does not perform remediation.

## On-Prem Windows Server Health Check

On-Prem mode collects read-only health signals from Windows servers listed in a server inventory CSV. It uses DNS, ICMP where allowed, and WinRM/CIM remote management to check connectivity, CPU, memory, uptime, fixed logical disks, critical services, pending reboot indicators where available, and network adapters.

Prerequisites:

- Network connectivity from the admin workstation to the target servers.
- DNS resolution for each server name in the inventory.
- WinRM/CIM remote access enabled and allowed by firewall rules.
- Appropriate domain or local administrator permissions where the target Windows Server requires them for remote CIM queries.
- A server inventory based on `config/servers.sample.csv`; keep real server names in local ignored files such as `config/servers.csv`.

Example command:

```powershell
pwsh ./src/main.ps1 -Mode OnPrem -ServersPath ./config/servers.sample.csv
```

Unreachable servers are reported as findings instead of stopping the run. This is expected when using the sample inventory because the sample server names are fake lab values.

This mode does not modify remote servers. It does not reboot, restart services, change registry values, change disk or network settings, adjust firewall rules, or perform remediation. Credentials are not stored, and the current user context is used unless a future version explicitly adds a credential parameter.

Generated OnPrem reports are written under `reports/`, which is ignored by Git:

- `reports/onprem-health-raw-[timestamp].json`
- `reports/onprem-health-findings-[timestamp].json`
- `reports/onprem-health-findings-[timestamp].csv`
- `reports/onprem-health-report-[timestamp].html`

## Azure VM Health Check

Azure mode collects read-only Azure VM health signals for VMs listed in `config/azure-vms.csv` or the sample inventory. It checks Az PowerShell availability, current Azure authentication context, subscription context, VM metadata, managed disk summary, network interface summary, and Windows in-guest health through Azure VM Run Command when the VM is running and permissions allow it.

Prerequisites:

- PowerShell 7.
- `Az.Accounts`.
- `Az.Compute`.
- `Az.Network` for network interface detail collection.
- Run `Connect-AzAccount` before Azure mode; the tool does not prompt for credentials.
- Reader-level access is enough for metadata checks.
- VM Run Command requires permission to run commands on the VM.

Example command:

```powershell
pwsh ./src/main.ps1 -Mode Azure -AzureVmsPath ./config/azure-vms.sample.csv
```

Azure mode is read-only. It does not start, stop, restart, resize, move, tag, delete, reboot, or modify Azure VMs or related resources, and it does not restart services inside guest VMs.

If Az modules are missing, the user is not authenticated, the sample subscription ID is still present, or a VM cannot be read, Azure mode generates findings that explain the issue instead of crashing. Generated Azure reports are written under `reports/`, which is ignored by Git:

- `reports/azure-health-raw-[timestamp].json`
- `reports/azure-health-findings-[timestamp].json`
- `reports/azure-health-findings-[timestamp].csv`
- `reports/azure-health-report-[timestamp].html`

## Hybrid Health Check

Hybrid mode runs Local, OnPrem, and Azure VM health checks in one execution and generates a combined report for cross-environment review. It is useful before patching, migration planning, maintenance windows, and weekly health reviews where administrators need one read-only summary of local, on-prem, and Azure VM risk signals.

Example command:

```powershell
pwsh ./src/main.ps1 -Mode Hybrid -IncludeLocal -ServersPath ./config/servers.sample.csv -AzureVmsPath ./config/azure-vms.sample.csv
```

Hybrid mode loads thresholds and predictive rules, optionally includes the local machine when `-IncludeLocal` is provided, runs OnPrem checks when the server inventory exists, and runs Azure VM checks when the Azure VM inventory exists. If one mode fails, the Hybrid run continues and adds an execution finding explaining what failed and what to review.

The sample server and Azure VM values are fake. When you run Hybrid mode with sample files, unreachable on-prem servers and unavailable Azure subscription/context values are reported as findings instead of crashing the tool.

Generated Hybrid reports are written under `reports/`, which is ignored by Git:

- `reports/hybrid-health-raw-[timestamp].json`
- `reports/hybrid-health-findings-[timestamp].json`
- `reports/hybrid-health-findings-[timestamp].csv`
- `reports/hybrid-health-report-[timestamp].html`

## Professional Reports

Local mode converts raw health collection data into admin-friendly findings and generates professional reports under `reports/`.

Example command:

```powershell
pwsh ./src/main.ps1 -Mode Local
```

Generated report files include:

- `reports/local-health-raw-[timestamp].json`: raw read-only collector output.
- `reports/local-health-findings-[timestamp].json`: findings, overall score, maintenance readiness, and raw result context for automation.
- `reports/local-health-findings-[timestamp].csv`: flat findings for spreadsheet review, ticket notes, or operational handoff.
- `reports/local-health-report-[timestamp].html`: standalone browser-readable report with embedded CSS and no external CDN dependencies.

The HTML report includes an executive summary, health summary cards, maintenance readiness, a findings table, and a predictive maintenance / early warning section. Maintenance readiness is reported as `Ready`, `ReviewRequired`, or `NotReady` based on critical findings, storage risk, pending reboot status, critical service status, high severity findings, event log risk volume, and disk free space warnings.

Early warning risk indicators are based on observed signals such as disk/storage warnings, repeated event log patterns, and network adapter instability. They are practical risk indicators only; they do not guarantee exact failure dates or exact remaining useful life.

Security note: generated reports may contain local machine names and operational details. Files generated under `reports/` are ignored by Git and should not be committed.

Example generated paths:

```text
reports/local-health-raw-20260424-223500.json
reports/local-health-findings-20260424-223500.json
reports/local-health-findings-20260424-223500.csv
reports/local-health-report-20260424-223500.html
```

## Trend History and Predictive Risk

Server Health Sentinel can store lightweight local trend snapshots under `history/` so a current run can be compared with the previous run of the same mode. Local, OnPrem, Azure, and Hybrid snapshots are matched by mode before comparison, so a Hybrid run is not compared against a Local run. The trend snapshot records summary counts, target summaries, category summaries, and finding summaries that help identify increasing or decreasing operational risk indicators over time.

Trend output uses terms such as `Trend Indicator`, `Failure Risk`, `Early Warning`, `Risk Increasing`, `Risk Stable`, `Risk Decreasing`, and `Confidence Level`. It does not guarantee exact failure dates or exact remaining useful life.

History files use names such as `trend-snapshot-local-[timestamp].json` or `trend-snapshot-hybrid-[timestamp].json` and are ignored by Git because they may contain real environment details such as server names and operational findings. Only `history/.gitkeep` should be committed.

Example command:

```powershell
pwsh ./src/main.ps1 -Mode Hybrid -IncludeLocal -ServersPath ./config/servers.sample.csv -AzureVmsPath ./config/azure-vms.sample.csv -HistoryPath ./history
```

## Roadmap Summary

The roadmap starts with local health checks and reporting, then adds predictive risk rules, on-prem remote checks, Azure VM health, hybrid mode, trend history, and optional hardware sensor integrations.
