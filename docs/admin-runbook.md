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
