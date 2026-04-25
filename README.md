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

## Roadmap Summary

The roadmap starts with local health checks and reporting, then adds predictive risk rules, on-prem remote checks, Azure VM health, hybrid mode, trend history, and optional hardware sensor integrations.
