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

## Using Server Health Sentinel for Azure VM Checks

Run Azure checks before patching windows, platform maintenance, migration planning, or routine Azure VM health reviews when you need a read-only snapshot of VM state and supporting Azure metadata.

Example command:

```powershell
pwsh ./src/main.ps1 -Mode Azure -AzureVmsPath ./config/azure-vms.csv
```

### Pre-Maintenance Azure VM Review

- Confirm `config/azure-vms.csv` includes only the intended maintenance targets.
- Run `Connect-AzAccount` with an account that has the least privilege needed for the review.
- Review Azure context, subscription, metadata, power state, disk, network, and guest health findings before approving work.

### Before Patching Azure VMs

- Treat stopped, deallocated, unknown, or non-succeeded provisioning states as review items.
- Review guest pending reboot, guest disk free space, critical service, CPU, memory, and event count findings when Run Command is available.
- Keep Run Command failures separate from VM health conclusions; they can indicate VM Agent, permission, policy, or guest OS issues.

### Reviewing Stopped Or Deallocated VMs

Stopped or deallocated VMs are reported as findings and guest health is skipped. This tool does not start, stop, restart, or reboot VMs. Confirm the expected power state with the application owner before maintenance decisions.

### Reviewing Azure Network And Disk Summary

Disk findings summarize OS disk, data disk count, disk SKU, and sizes where metadata is available. Network findings summarize NIC count, private IPs, public IP associations, NIC names, and accelerated networking where `Az.Network` is available.

### Security And Permission Notes

Reader-level access is enough for basic VM metadata checks. VM Run Command requires additional permission to run commands on the VM, and the command used by this tool is read-only. Do not store credentials, tokens, tenant IDs, subscription IDs, or secrets in committed files. Use local ignored inventory files for real Azure details.

## Hybrid Infrastructure Health Review

Use Hybrid mode when one review needs to cover the local machine, on-prem Windows servers, and Azure VMs in a single combined report.

Example command:

```powershell
pwsh ./src/main.ps1 -Mode Hybrid -IncludeLocal -ServersPath ./config/servers.csv -AzureVmsPath ./config/azure-vms.csv
```

### Weekly Hybrid Health Review

- Confirm the local server, on-prem inventory, and Azure VM inventory reflect the intended review scope.
- Review the executive summary for overall status, health score, maintenance readiness, target counts, and finding counts.
- Compare repeated Red, Yellow, and Unknown findings with monitoring alerts and prior operational notes.

### Pre-Maintenance Review

- Run Hybrid mode before change windows that affect multiple environments.
- Confirm `MaintenanceReadiness` is acceptable for the planned work.
- Review execution findings first because they may indicate a whole mode did not run.

### Pre-Patching Review

- Review pending reboot, low disk space, stopped critical service, Azure guest health, and event log risk findings before approving patch activity.
- Treat `NotReady` as a blocker unless an administrator formally accepts the risk through normal change control.

### Before Migration

- Use Hybrid reports to identify source server readiness issues, Azure access gaps, and cross-environment health risks before migration planning.
- Keep reports with the migration assessment record according to organizational policy.

### Reviewing Red Findings

Red findings require administrator review before maintenance, patching, or migration. Confirm whether the condition is expected, already tracked, or requires remediation through approved procedures.

### Reviewing Unknown Findings

Unknown findings mean the tool could not evaluate a signal. They do not prove the target is healthy. Common causes include permission gaps, missing modules, blocked network paths, unavailable CIM/WinRM, stopped Azure VM agents, or fake sample inventory values.

### Reviewing Azure Authentication Or Access Issues

Azure context, subscription, metadata, and guest health findings should be reviewed separately. Missing authentication or insufficient access can prevent Azure checks from running even when the VM itself is healthy.

### Reviewing Unreachable On-Prem Servers

Unreachable on-prem servers usually indicate DNS, routing, firewall, WinRM/CIM, permissions, or host availability issues. Investigate reachability with approved administrative tools before drawing health conclusions.

### Action Approval

Recommendations in Hybrid reports are advisory only. Any remediation, reboot, service restart, registry change, disk cleanup, firewall change, Windows setting change, network change, or Azure resource change requires administrator review and approval before action.
