# Predictive Maintenance Design

## Current Health Check vs Predictive Maintenance

A current health check describes what is happening now, such as CPU usage, free disk space, network adapter state, service status, and recent critical events.

Predictive maintenance looks for patterns that may indicate increasing failure risk. It compares repeated warnings, hardware signals, historical trends, and known risk indicators to help administrators prioritize investigation before an outage occurs.

## Remaining Useful Life

Exact Remaining Useful Life is not guaranteed in version 0.1.0. Reliable failure date prediction requires enough historical data, consistent telemetry, component-specific failure models, and often vendor-provided hardware signals. Server Health Sentinel should use honest language such as Failure Risk, Early Warning, Risk Indicator, and Confidence Level.

## Risk Inputs

The tool can estimate component risk using:

- Repeated Windows Event Log errors
- Disk health status
- SMART or vendor health indicators where available
- Network adapter link flaps or speed degradation
- Power supply, fan, and temperature status through Redfish, iDRAC, iLO, or vendor interfaces where available

## Initial Risk Levels

- Low
- Medium
- High
- Critical
- Unknown

## Example Findings

- Disk has repeated storage timeout events.
- NIC link speed dropped from 10 Gbps to 1 Gbps.
- Power supply status is Warning from Redfish.
- Temperature sensor is above threshold.

## Security Note

No credentials should be stored. Hardware management endpoints should use sample files only in source control. Real endpoint files must be ignored by Git.
