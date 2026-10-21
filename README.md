# FortiGate GPS Automation

Automated FortiGate/FortiAP GPS location workflow with dynamic FortiAP discovery, GNSS validation, OpenSSH-based FortiGate updates, and FortiManager deployment reference.

## Overview

This solution automates GPS-based location updates for FortiGate devices using a FortiAP-432G with GNSS capability.

The workflow dynamically discovers the connected root FortiAP, determines its current DHCP-assigned IP address and CAPWAP control port, queries the AP for GNSS coordinates, validates the returned data, and updates the FortiGate latitude and longitude only when a valid GPS fix is available.

## Production Workflow

FortiGate scheduled automation
        |
        v
Collect WTP information
        |
        v
Send WTP information to Windows validator
        |
        v
Identify FortiAP-432G root AP
        |
        v
Extract dynamic AP IP and CAPWAP control port
        |
        v
SSH from Windows validator to FortiGate
        |
        v
Run FortiAP GNSS query through FortiGate
        |
        v
Decode and validate GNSS response
        |
        v
Valid GPS   -> Update FortiGate coordinates
Invalid GPS -> No change

## Schedule

The FortiGate automation runs four times per day:

- 00:00
- 06:00
- 12:00
- 18:00

## Repository Structure

fortigate-gps-automation/
|-- README.md
|-- .gitignore
|-- windows/
|   |-- FortiGateGPS.ps1
|   |-- SSH-AskPass.ps1
|   `-- SSH-AskPass.cmd
|-- fortimanager/
|   `-- fortigate-gps-production-reference.cli
`-- docs/

## Windows Components

The Windows validator runs on:

10.1.0.130

Production files:

FortiGateGPS.ps1
SSH-AskPass.ps1
SSH-AskPass.cmd

Runtime installation path:

D:\FortiGateGPS\

The following file is required locally but must not be committed to GitHub:

FortiGateSSHPassword.dat

This file contains locally protected password material used by the OpenSSH AskPass process.

## FortiGate SSH

The Windows validator connects to the FortiGate using:

FortiGate: 10.1.0.1
SSH Port: 8446
SSH User: gps-automation

The `gps-automation` account is restricted to the Windows validator host and uses the `prof_admin` access profile.

## FortiAP Discovery

The FortiGate collects WTP information using:

diagnose wireless-controller wlac -c wtp

The Windows validator identifies the root AP using:

Model: FortiAP-432G
Mesh uplink: ethernet
Mesh hop count: 0
Connection state: Connected

The AP management IP and CAPWAP control port are discovered dynamically.

No FortiAP IP address, serial number, AP name, or CAPWAP source port is hard-coded in the production GPS workflow.

## GNSS Query

After discovery, the Windows validator connects back to the FortiGate and runs:

diagnose wireless-controller wlac wtpcmd <AP-IP> <CPORT> r&sh "cw_diag -c gnss get curr-pos"

The returned hexadecimal output is decoded and validated by `FortiGateGPS.ps1`.

If no valid GPS fix is available, no FortiGate location settings are changed.

If valid coordinates are returned, the script updates:

gui-device-latitude
gui-device-longitude

## FortiManager

The file:

fortimanager/fortigate-gps-production-reference.cli

is included for documentation and reference only.

The production FortiManager copy is maintained in the **FortiManager FE ADOM**.

The FortiManager script uses a variable for the `gps-automation` password instead of storing the password directly in the script.

## Security

Do not commit:

FortiGateSSHPassword.dat
GPS-Update-Commands.txt
GPS-GNSS-Commands.txt
*.log

These are excluded by `.gitignore`.

## Status

The following have been validated:

- Dynamic FortiAP-432G discovery
- Dynamic DHCP IP discovery
- Dynamic CAPWAP control-port discovery
- OpenSSH authentication
- FortiAP GNSS query through FortiGate
- GNSS hexadecimal response decoding
- Invalid GPS fail-safe behavior
- Valid GPS coordinate update
- Scheduled FortiGate automation workflow