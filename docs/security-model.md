# Security Model

Server Health Sentinel is designed as a read-only reporting tool. Its purpose is to collect health signals, evaluate findings, and generate reports without changing the systems being checked.

## Read-Only Execution

The tool must not remediate, reboot, restart services, change firewall rules, modify network settings, alter disks, edit the registry, power cycle hardware, or modify Azure resources.

Checks should use the least privilege needed for visibility. If a target cannot be queried because of permissions or connectivity, the tool should report that limitation as a finding.

## No Remediation

Findings are advisory. Administrators remain responsible for reviewing the report, validating the finding, and choosing any remediation outside the tool.

Future remediation workflows, if added, should require explicit approval gates and remain disabled by default.

## No Secrets in the Repository

Do not commit credentials, passwords, tokens, API keys, tenant IDs, subscription IDs, real server names, real machine names, usernames, management endpoint addresses, or operational details.

The repository should contain safe sample files only.

## Ignored Real Config Files

Real environment files should be local and ignored by Git, including:

- `config/servers.csv`
- `config/azure-vms.csv`
- `config/hardware-endpoints.csv`
- `config/thresholds.json`
- `config/predictive-rules.json`

## Ignored Reports and History

Generated reports and history snapshots can include real machine names, findings, timestamps, and operational context. They should remain local and ignored by Git.

Ignored generated outputs include:

- `reports/*.html`
- `reports/*.csv`
- `reports/*.json`
- `history/*.json`
- `history/*.csv`
- `history/*.html`

## Safe Sample Data

Sample files must use fake server names, fake Azure values, fake locations where needed, and non-sensitive placeholders. They should never be edited to include real infrastructure details.

## Permission Considerations

- Local mode reads health data from the machine running the script.
- OnPrem mode requires network connectivity, DNS, WinRM/CIM availability, and appropriate Windows permissions.
- Azure mode requires Az PowerShell modules, an existing Azure authentication context, resource visibility permissions, and VM Run Command permission for guest readiness checks.
- Hardware readiness should use only approved management interfaces and should not store credentials in CSV files or reports.
