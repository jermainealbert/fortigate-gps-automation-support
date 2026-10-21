# Architecture

## Overview

The FortiGate GPS automation solution updates the FortiGate device location using GNSS data from a FortiAP-432G.

The design avoids hard-coding the FortiAP management IP address or CAPWAP control port. The FortiGate provides current wireless-controller session information to a Windows validator, which dynamically identifies the root FortiAP and queries it for GNSS coordinates.

The FortiGate location is updated only when a valid GPS fix is returned.

## Components

### FortiGate

The FortiGate performs the following functions:

- Runs the GPS automation on a schedule
- Collects current FortiAP WTP information
- Sends WTP information to the Windows validator
- Accepts SSH connections from the validator
- Relays GNSS commands to the FortiAP
- Stores the validated latitude and longitude values

FortiGate management settings used by the solution:

- Management IP: `10.1.0.1`
- SSH port: `8446`
- Automation administrator: `gps-automation`
- Access profile: `prof_admin`

### FortiAP

The root access point is a FortiAP-432G.

The root AP is identified dynamically using the WTP information reported by the FortiGate.

Selection criteria:

- FortiAP model: `FP432G`
- Mesh uplink: `ethernet`
- Mesh hop count: `0`
- Connection state: `Connected`

The AP management IP address is assigned by DHCP and is not assumed to be consistent across sites.

The CAPWAP control source port is also taken from the active WTP session rather than being hard-coded.

### Windows Validator

The Windows validator runs on:

`10.1.0.130`

The runtime folder is:

`D:\FortiGateGPS\`

Production files:

- `FortiGateGPS.ps1`
- `SSH-AskPass.ps1`
- `SSH-AskPass.cmd`
- `FortiGateSSHPassword.dat`

The encrypted password file is local runtime data and is not stored in GitHub.

The validator listens on TCP port `8080`.

Primary endpoint:

`/api/gps/discovery/`

Fallback endpoint retained in the script:

`/api/gps/parse/`

## Automation Schedule

The FortiGate runs the production workflow four times per day:

- 00:00
- 06:00
- 12:00
- 18:00

Production stitches:

- `GPS-Update-0000`
- `GPS-Update-0600`
- `GPS-Update-1200`
- `GPS-Update-1800`

Each production stitch runs:

1. `GPS-WTP-Discovery`
2. `GPS-Send-WTP-Discovery`

## WTP Discovery

The FortiGate collects current WTP information with:

`diagnose wireless-controller wlac -c wtp`

The output includes information such as:

- FortiAP software/model
- AP name
- Local management IP
- Mesh uplink
- Mesh hop count
- Connection state
- Live CAPWAP session IP and port

The discovery action output is sent to the Windows validator over HTTP.

The validator parses the WTP records and requires exactly one connected FortiAP-432G that has:

- Ethernet uplink
- Mesh hop count 0

The active WTP connection state provides the values used for the GNSS query.

Example:

`Connected (0-10.100.100.241:15246)`

From this value the validator extracts:

- AP IP: `10.100.100.241`
- CAPWAP control port: `15246`

These values are examples only and are discovered dynamically at runtime.

## GNSS Query

After discovering the active FortiAP session, the Windows validator connects to the FortiGate using OpenSSH.

The validator then runs:

`diagnose wireless-controller wlac wtpcmd <AP-IP> <CPORT> r&sh "cw_diag -c gnss get curr-pos"`

The FortiGate sends the command to the FortiAP.

The FortiAP response is returned through the FortiGate as hexadecimal output.

The Windows validator decodes the hexadecimal bytes into ASCII text.

A valid FortiAP GNSS response contains latitude and longitude values in the form:

`31.701869, -103.443221`

An invalid response may contain:

`No valid GPS location data.`

## GPS Validation

The validator checks the returned coordinates before making any FortiGate changes.

Validation requires:

- Latitude between -90 and 90
- Longitude between -180 and 180

If the GNSS response does not contain valid coordinates, the workflow stops without modifying the FortiGate location.

This creates a fail-closed behavior.

## FortiGate Coordinate Update

When a valid GPS fix is available, the Windows validator connects to the FortiGate over OpenSSH and updates:

`gui-device-latitude`

`gui-device-longitude`

The commands are applied under:

`config system global`

No coordinate update is attempted when the GNSS data is invalid.

## SSH Authentication

The validator uses the Windows OpenSSH client:

`C:\Windows\System32\OpenSSH\ssh.exe`

OpenSSH authentication is handled through:

- `SSH-AskPass.ps1`
- `SSH-AskPass.cmd`
- `FortiGateSSHPassword.dat`

The password file is protected locally and is not part of the GitHub repository.

The FortiGate `gps-automation` administrator is restricted to the validator host:

`10.1.0.130`

## Data Flow

FortiGate scheduled automation
        |
        v
Run GPS-WTP-Discovery
        |
        v
Collect current WTP information
        |
        v
Run GPS-Send-WTP-Discovery
        |
        v
HTTP POST to 10.1.0.130:8080
        |
        v
Windows validator parses WTP data
        |
        v
Identify Ethernet FortiAP-432G root
        |
        v
Extract dynamic AP IP and CAPWAP cport
        |
        v
OpenSSH to FortiGate 10.1.0.1:8446
        |
        v
Run dynamic wtpcmd GNSS query
        |
        v
Decode FortiAP hexadecimal response
        |
        v
Validate latitude and longitude
        |
        +-----------------------------+
        |                             |
        v                             v
Invalid GPS                     Valid GPS
        |                             |
        v                             v
No change                   SSH coordinate update
                                      |
                                      v
                           FortiGate location updated

## FortiManager

The production FortiGate configuration is maintained in the FortiManager FE ADOM.

The repository contains:

`fortimanager/fortigate-gps-production-reference.cli`

This file is a reference copy only.

The production FortiManager script should be treated as the operational source for FortiGate deployment.

The FortiManager script uses a variable for the `gps-automation` password instead of storing the password directly in the script.

## Design Principles

The solution was designed around the following requirements:

- No hard-coded FortiAP DHCP address
- No hard-coded CAPWAP control port
- No dependency on a site-specific FortiAP serial number
- No dependency on a site-specific AP name
- Root AP must be a FortiAP-432G
- Invalid GPS data must never overwrite FortiGate coordinates
- Windows-side processing should remain lightweight
- FortiGate scheduling remains local to each site
- FortiManager is used for scalable FortiGate deployment
- GitHub stores code and documentation, but not runtime secrets