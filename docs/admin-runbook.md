# Administrator Runbook

This runbook describes the intended operational use of Server Health Sentinel.

## Before Running

- Review the sample configuration files.
- Create local configuration files from the samples.
- Confirm PowerShell 7+ is installed.
- Confirm required modules are installed for the selected mode.
- Use accounts with read-only access whenever possible.

## During Checks

- Run local checks on the target machine or remote checks through approved administrative channels.
- Review generated reports for warnings, critical findings, and unknown states.
- Treat predictive maintenance output as risk indicators, not exact failure predictions.

## After Checks

- Store reports according to your organization's operational policy.
- Do not commit generated reports if they contain environment details.
- Investigate high and critical findings through normal change management processes.

## Safety Rules

Server Health Sentinel must not perform remediation actions. It should not reboot servers, restart services, alter configuration, modify network settings, change storage state, edit registry values, or modify Azure resources.

## Using Server Health Sentinel for On-Prem Server Checks

Run OnPrem checks before patching windows, during weekly server health reviews, and before migration planning when you need a quick read-only snapshot of reachable Windows servers.

Example command:

```powershell
pwsh ./src/main.ps1 -Mode OnPrem -ServersPath ./config/servers.sample.csv
```

### Before Patching

- Confirm the inventory file contains only the intended maintenance targets.
- Review Red and Yellow findings before approving patch activity.
- Treat pending reboot, stopped critical services, and low disk space as maintenance readiness signals that need administrator review.

### Weekly Server Health Review

- Compare current reports with prior operational notes or monitoring alerts.
- Review disk, memory, CPU, service, and network findings for repeated warning patterns.
- Use Unknown findings to identify gaps in visibility, permissions, or remote management configuration.

### Before Migration

- Use OnPrem reports to identify servers with connectivity, service, storage, or reboot issues before migration planning.
- Resolve or formally accept critical findings before scheduling migration work.
- Keep generated reports with the migration assessment record according to organizational policy.

### Interpreting Findings

Unreachable servers are Red connectivity findings. They usually indicate DNS, routing, firewall, WinRM/CIM, permissions, or host availability issues. Investigate with approved administrative tools before assuming the server itself is unhealthy.

Disk findings show fixed logical disk capacity. Red disk findings should be reviewed before maintenance because low free space can break patching, backups, logging, or application writes.

Critical service findings report whether configured services are running. A stopped critical service is Red, but this tool does not restart it. Confirm expected state, dependencies, and recent change history before taking action.

Network findings report adapter connection state and speed where CIM exposes those values. Review disconnected adapters, unexpected low speed, cabling, switch configuration, and virtualization settings as appropriate.

Pending reboot findings use safe read-only remote checks where possible. Unknown means the signal could not be confirmed remotely; it does not prove that no reboot is pending.

### Acting on Red and Yellow Findings

Red findings require administrator review before maintenance, patching, or migration. Yellow findings should be reviewed and either addressed or accepted with a documented reason.

Recommendations in the report are advisory only. Any remediation, reboot, service restart, firewall change, registry change, storage cleanup, or network change requires normal administrator approval and change control before action.
