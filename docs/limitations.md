# Limitations

Server Health Sentinel is intentionally scoped as a lightweight, read-only reporting tool. The following limitations are part of the current design.

## Not Real-Time Monitoring

The tool runs on demand and produces point-in-time reports. It does not provide continuous polling, live dashboards, alert routing, escalation workflows, or long-term telemetry storage.

## Not a PRTG Replacement

Server Health Sentinel complements enterprise monitoring platforms such as PRTG, SolarWinds, Zabbix, and Datadog. It does not replace their production monitoring, alerting, dashboarding, sensor libraries, or operational integrations.

## Not Exact Failure Prediction

Predictive risk indicators are rule-based early warning signals. They can highlight trends, repeated warnings, and areas needing review, but they do not guarantee exact hardware failure dates or exact remaining useful life.

## Hardware Check Requirements

Physical hardware health usually requires vendor management interfaces such as Redfish, Dell iDRAC, HPE iLO, Lenovo XClarity, or approved vendor tooling. Normal OS-level PowerShell may not expose power supply, fan, temperature, RAID/controller, or chassis sensor data.

The current hardware feature is readiness-focused. Authenticated Redfish sensor polling is planned for a future version.

## Azure Requirements

Azure checks require Az PowerShell modules, an existing Azure authentication context, subscription/resource permissions, and VM Run Command support for guest readiness checks. Missing modules, fake sample subscription IDs, or insufficient permissions are reported as findings.

## Remote Windows Requirements

Remote checks require DNS resolution, network connectivity, WinRM/CIM availability, firewall access, and appropriate permissions on the target systems. If those prerequisites are missing, the tool reports the visibility gap instead of treating the missing data as confirmed health.

## Public Repository Hygiene

Generated reports, history snapshots, real config files, credentials, tenant IDs, subscription IDs, server names, machine names, usernames, IP addresses, and operational screenshots should not be committed.
