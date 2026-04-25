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

## Trend-Based Risk Detection

Trend history compares the current snapshot with the latest previous snapshot. The comparison focuses on risk movement, not exact failure prediction:

- Health score change
- Red, Yellow, Unknown, Critical, and High finding count changes
- Maintenance readiness change
- Target and category summaries
- Component-level risk changes

Example trend indicators:

- Storage risk increased from Medium to High.
- Event log risk count increased for storage-related events.
- A NIC instability indicator appeared on a target that was previously stable.

## Risk Trend vs Exact Failure Prediction

`RiskTrend` values such as `Worsening`, `Stable`, `Improving`, and `Unknown` describe the direction of observed indicators. They do not claim exact failure dates or exact remaining useful life.

The report should use language such as `Trend Indicator`, `Failure Risk`, `Early Warning`, `Risk Increasing`, `Risk Stable`, `Risk Decreasing`, and `Confidence Level`.

## Confidence Levels

Confidence levels describe how much trust to place in an indicator based on signal quality:

- `High`: The finding came from a direct read-only health check such as disk capacity, service status, or a known Azure context state.
- `Medium`: The finding is useful but may need correlation, such as event log patterns, remote checks, or optional guest health details.
- `Low`: The finding is weak or advisory and should be treated as context.
- `Unknown`: The signal could not be confirmed, often because visibility, permissions, or hardware sensor data were unavailable.

## Security Note

No credentials should be stored. Hardware management endpoints should use sample files only in source control. Real endpoint files must be ignored by Git.
