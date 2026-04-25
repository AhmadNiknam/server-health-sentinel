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

## Optional Module Boundary

The hardware sensor module should remain optional because not every environment exposes hardware management interfaces, and access requirements vary by vendor and organization.

## Credential Handling

No credentials should be stored in files. The project should only commit sample endpoint files. Real endpoint files must remain local and ignored by Git.

## Committed Files

Only sample endpoint files such as `config/hardware-endpoints.sample.csv` should be committed. Real files such as `config/hardware-endpoints.csv` are ignored.
