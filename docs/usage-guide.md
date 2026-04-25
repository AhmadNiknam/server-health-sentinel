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

## Planned Azure Mode

```powershell
pwsh ./src/main.ps1 -Mode Azure -AzureVmConfig ./config/azure-vms.csv
```

## Planned Hybrid Mode

```powershell
pwsh ./src/main.ps1 -Mode Hybrid
```

## Configuration

Copy sample files from `config/*.sample.*` to local, ignored files before use. Do not commit real server names, tenant IDs, subscription IDs, credentials, tokens, or hardware management endpoints.

## Reports

Generated reports will be written to `reports`. HTML, CSV, and JSON report files are ignored by Git.
