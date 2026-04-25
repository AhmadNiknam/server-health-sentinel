# Usage Guide

This project is currently an initial scaffold. Full command behavior will be added as the collectors are implemented.

## Planned Local Mode

```powershell
pwsh ./src/main.ps1 -Mode Local
```

## Planned On-Prem Mode

```powershell
pwsh ./src/main.ps1 -Mode OnPrem -ServerConfig ./config/servers.csv
```

## Azure Mode

```powershell
pwsh ./src/main.ps1 -Mode Azure -AzureVmsPath ./config/azure-vms.csv
```

Create a local Azure VM inventory from the sample:

```powershell
Copy-Item ./config/azure-vms.sample.csv ./config/azure-vms.csv
```

Fill in `SubscriptionId`, `ResourceGroupName`, `VmName`, `Environment`, `Role`, and `Location` for each VM you want checked. Keep real inventory files local; do not commit `config/azure-vms.csv` because subscription IDs and VM names are environment details.

Authenticate before running Azure mode:

```powershell
Connect-AzAccount
```

Then run:

```powershell
pwsh ./src/main.ps1 -Mode Azure -AzureVmsPath ./config/azure-vms.csv
```

You can also run against the fake sample inventory to validate report generation:

```powershell
pwsh ./src/main.ps1 -Mode Azure -AzureVmsPath ./config/azure-vms.sample.csv
```

Azure findings explain missing prerequisites and access issues:

- Missing module findings mean `Az.Accounts`, `Az.Compute`, or optional `Az.Network` was not available.
- Authentication context findings mean `Connect-AzAccount` has not been run in the current session.
- Subscription context findings mean the subscription ID is blank, fake, invalid, or unavailable to the signed-in account.
- Metadata or access findings mean the VM was not found, the resource group/name is wrong, or the account lacks permission.
- Guest health findings mean Run Command was skipped, unavailable, or failed; metadata checks may still be useful.

Azure mode is read-only. It does not start, stop, restart, resize, move, tag, delete, reboot, or modify Azure resources, and it does not restart services inside VMs.

## Hybrid Mode

```powershell
pwsh ./src/main.ps1 -Mode Hybrid -IncludeLocal -ServersPath ./config/servers.sample.csv -AzureVmsPath ./config/azure-vms.sample.csv
```

### Configuration Preparation

Copy sample inventory files to local ignored files before using real infrastructure:

```powershell
Copy-Item ./config/servers.sample.csv ./config/servers.csv
Copy-Item ./config/azure-vms.sample.csv ./config/azure-vms.csv
Copy-Item ./config/thresholds.sample.json ./config/thresholds.json
Copy-Item ./config/predictive-rules.sample.json ./config/predictive-rules.json
```

Edit the local copies for your environment. Do not commit real server names, tenant IDs, subscription IDs, credentials, tokens, or generated reports.

### Running Hybrid Mode

Use `-IncludeLocal` when the workstation or server running the script should be part of the combined report:

```powershell
pwsh ./src/main.ps1 -Mode Hybrid -IncludeLocal -ServersPath ./config/servers.csv -AzureVmsPath ./config/azure-vms.csv -ThresholdsPath ./config/thresholds.json -PredictiveRulesPath ./config/predictive-rules.json
```

Hybrid mode combines Local, OnPrem, and Azure VM checks. If one source fails or a sample inventory points to fake targets, the run continues and records a structured finding for that mode.

### Interpreting The Combined Report

The Hybrid HTML report includes an executive summary, target summary by `TargetType`, maintenance readiness, all findings, and predictive maintenance / early warning indicators. Review the target counts to confirm the expected Local, OnPrem, and Azure VM scope was checked.

### Understanding Readiness Status

`Ready` means no Red or High findings were detected. `ReviewRequired` means warnings, High findings, pending reboot signals, disk warnings, or event log risk patterns need an operator decision. `NotReady` means Critical findings or hard maintenance blockers are present and should be resolved or formally accepted before work begins.

### Understanding Unknown Findings

Unknown findings usually indicate missing visibility rather than confirmed health. Common causes include missing Az modules, no Azure authentication context, fake sample subscription IDs, unreachable on-prem servers, blocked WinRM/CIM, unavailable counters, or permission gaps.

## Configuration

Copy sample files from `config/*.sample.*` to local, ignored files before use. Do not commit real server names, tenant IDs, subscription IDs, credentials, tokens, or hardware management endpoints.

## Reports

Generated reports will be written to `reports`. HTML, CSV, and JSON report files are ignored by Git.
