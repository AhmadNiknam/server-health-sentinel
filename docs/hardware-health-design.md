# Hardware Health Design

Physical hardware health is optional in Server Health Sentinel and will be disabled by default.

## Power Supply Health

Power supply health is usually not available from normal Windows OS commands. Windows can expose some hardware-related information through CIM/WMI, but power supply, fan, temperature, and RAID controller status commonly require out-of-band management interfaces or vendor tools.

## Collection Sources

Hardware health should be collected through server management interfaces such as:

- Redfish
- Dell iDRAC
- HPE iLO
- Lenovo XClarity
- Vendor-specific command-line tools or APIs

## Why Management Interfaces Are Needed

OS-level PowerShell can read many Windows health signals through counters, CIM, WMI, event logs, and storage classes, but it cannot reliably read every physical hardware sensor. Power supplies, fan tachometers, chassis temperature probes, battery-backed cache state, RAID/controller detail, and management controller alerts are commonly outside the normal operating system boundary or exposed differently by each vendor.

Out-of-band management interfaces exist to expose those hardware signals consistently without relying on the host OS. Redfish is the preferred design target because it is a vendor-neutral REST-style standard. Vendor platforms such as Dell iDRAC, HPE iLO, and Lenovo XClarity commonly expose Redfish-compatible endpoints or similar read-only APIs.

## Redfish-Style Workflow

The current phase implements readiness only:

1. Load a local hardware endpoint inventory.
2. Validate required columns and endpoint structure.
3. Process only endpoints explicitly marked `Enabled=true`.
4. Return `Skipped` when no endpoints are enabled.
5. Return `Unknown` for missing endpoint values or unsupported management types.
6. Return readiness findings that state authenticated Redfish polling is planned for a future version.

Future polling should authenticate only through an explicit safe mechanism, request read-only sensor resources, normalize results into categories such as power supply, fan, temperature, RAID/controller, and hardware sensor, then report findings without remediation.

## Security Considerations

Hardware management endpoints can control sensitive physical operations in many environments. Server Health Sentinel must remain read-only:

- Do not reboot servers.
- Do not power cycle servers.
- Do not modify BIOS, firmware, RAID, hardware, network, or management controller settings.
- Do not store credentials, tokens, passwords, API keys, or secrets.
- Do not commit real endpoint names, IP addresses, or server names.
- Keep hardware checks optional and disabled by default.

## Optional Module Boundary

The hardware sensor module should remain optional because not every environment exposes hardware management interfaces, and access requirements vary by vendor and organization.

## Credential Handling

No credentials should be stored in files. The project should only commit sample endpoint files. Real endpoint files must remain local and ignored by Git.

Credential principles for future versions:

- No credentials in CSV inventory files.
- No secrets in Git.
- Prefer interactive `PSCredential`, secure vault integration, managed identity where appropriate, or another explicit secret provider.
- Do not log secrets or include them in reports.
- Treat permissions as read-only and least privilege.

## Limitations

- Vendor Redfish implementations can differ by model, firmware version, license tier, and permissions.
- Network and firewall rules must allow access from the admin workstation to the management interface.
- Some sensors may require vendor-specific paths or tooling.
- Azure VMs do not expose the underlying physical host hardware sensors to tenants, so this design is for physical server management endpoints, not Azure VM physical hardware.
- Readiness findings do not prove a server is healthy; they only describe whether optional hardware management checks are configured enough for future sensor polling.

## Committed Files

Only sample endpoint files such as `config/hardware-endpoints.sample.csv` should be committed. Real files such as `config/hardware-endpoints.csv` are ignored.
