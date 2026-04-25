# LinkedIn Post Draft

I recently built **Server Health Sentinel**, a PowerShell-based hybrid server health reporting project for Windows Server, on-prem infrastructure, Azure VMs, and optional hardware sensor readiness.

The goal was practical: give an administrator a quick, read-only way to run pre-maintenance or weekly health checks and generate clear reports without changing the systems being reviewed.

The project supports local, on-prem, Azure, and Hybrid modes. It checks areas such as storage health, network adapter state, event log risk indicators, maintenance readiness, Azure VM context/readiness, trend history, and optional hardware sensor readiness design for platforms like Redfish, iDRAC, and iLO.

Technologies used include PowerShell 7, CIM/WMI concepts, Windows Event Log analysis, Az PowerShell design, HTML/CSV/JSON reporting, Pester tests, and GitHub Actions CI.

One of the main things I focused on was keeping the project honest and safe. It is read-only, does not perform remediation, does not replace enterprise monitoring platforms like PRTG, and does not claim exact hardware failure prediction. Instead, it provides useful point-in-time reporting and rule-based early warning indicators that can complement existing monitoring tools.

This was a good project for practicing IT automation, hybrid infrastructure thinking, report generation, testing, and public GitHub documentation.

I am preparing it as a GitHub-ready portfolio project to demonstrate PowerShell automation, operational awareness, and security-conscious documentation.
