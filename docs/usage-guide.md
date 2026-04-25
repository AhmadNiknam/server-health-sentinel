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

## Planned Hybrid Mode

```powershell
pwsh ./src/main.ps1 -Mode Hybrid
```

## Configuration

Copy sample files from `config/*.sample.*` to local, ignored files before use. Do not commit real server names, tenant IDs, subscription IDs, credentials, tokens, or hardware management endpoints.

## Reports

Generated reports will be written to `reports`. HTML, CSV, and JSON report files are ignored by Git.
