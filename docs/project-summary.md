# Project Summary

## Project Overview

Server Health Sentinel is a read-only PowerShell-based hybrid server health and predictive risk reporting tool for Windows Server, on-prem infrastructure, Azure VMs, and optional hardware sensor readiness.

The project collects practical health signals, evaluates findings, tracks lightweight trend history, and generates HTML, CSV, and JSON reports for administrators who need repeatable pre-maintenance or weekly health reviews.

## Business Value

- Helps administrators prepare for patching, maintenance windows, migrations, and weekly operational reviews.
- Produces clear findings that can support handoff notes, tickets, and management summaries.
- Keeps checks read-only, reducing the risk of accidental operational changes.
- Uses sample configuration files so the repository can be shared publicly without exposing real infrastructure details.

## Technical Value

- Demonstrates modular PowerShell design with separate configuration, collection, evaluation, trend, and reporting responsibilities.
- Supports local, on-prem, Azure, and Hybrid execution modes.
- Produces multiple report formats for both human review and automation workflows.
- Includes Pester tests and GitHub Actions CI for repeatable validation.

## Admin Use Cases

- Run a local pre-maintenance health check before patching a Windows Server.
- Review on-prem server reachability and remote health signals before scheduled work.
- Validate Azure VM context, metadata visibility, and guest readiness.
- Run Hybrid mode for a consolidated weekly health summary.
- Compare trend snapshots to see whether risk indicators are improving, stable, or worsening.
- Document optional hardware sensor readiness for future Redfish/iDRAC/iLO integration.

## Complementing PRTG Instead of Replacing It

Server Health Sentinel is not a replacement for PRTG or other enterprise monitoring platforms. PRTG provides continuous monitoring, alerting, dashboards, sensors, escalation paths, and long-term operational visibility.

This project complements tools like PRTG by providing an on-demand, scriptable, report-focused health review that can be customized, run before maintenance, and shared as a point-in-time readiness artifact.

## Key Technologies Used

- PowerShell 7
- CIM/WMI and Windows health data sources
- Windows Event Log analysis
- Az PowerShell module design for Azure VM checks
- Azure VM Run Command readiness concepts
- HTML, CSV, and JSON report generation
- Pester
- GitHub Actions
- Optional Redfish/iDRAC/iLO hardware readiness design

## What This Project Demonstrates

For IT roles, this project demonstrates practical automation, hybrid infrastructure awareness, documentation discipline, security-conscious repo hygiene, operational reporting, and realistic communication about tool limitations.
