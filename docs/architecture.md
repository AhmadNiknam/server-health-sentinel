# Architecture

Server Health Sentinel uses a modular PowerShell design. The entry point in `src/main.ps1` will load configuration, call one or more collectors, evaluate health findings, analyze early warning indicators, and generate reports.

## Planned Flow

1. Load sample-based configuration from the `config` directory.
2. Run read-only collectors for the selected mode.
3. Normalize collector output into health findings.
4. Evaluate thresholds and risk indicators.
5. Write HTML, CSV, and JSON reports to the `reports` directory.

## Module Groups

- Configuration: `ConfigLoader.psm1`
- Logging: `Logger.psm1`
- Collection: local, on-prem, Azure VM, storage, network, and hardware sensor collectors
- Analysis: event log risk, predictive health, trend store, and component risk model
- Evaluation and reporting: `HealthEvaluator.psm1` and `ReportGenerator.psm1`

## Safety Boundary

The first version is read-only. Modules must not remediate, reboot, restart services, modify firewall or network settings, change disks, edit the registry, or modify Azure resources.
