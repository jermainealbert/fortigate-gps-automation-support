# Deployment

## Overview

This document describes the deployment requirements and production installation process for the FortiGate GPS automation solution.

The solution has two primary deployment components:

1. FortiGate automation configuration deployed and maintained through FortiManager.
2. Windows validator files installed on the local validator host.

The GitHub repository stores the Windows code, documentation, and a reference copy of the FortiManager script.

The operational FortiManager script is maintained in the FortiManager FE ADOM.

## Prerequisites

Before deployment, verify the following.

### FortiGate

- FortiOS version: 7.6.7
- FortiGate management IP: `10.1.0.1`
- SSH management port: `8446`
- FortiGate can reach the Windows validator at `10.1.0.130`
- FortiGate automation stitch functionality is available
- FortiGate wireless controller is managing the FortiAP-432G
- Root AP is a FortiAP-432G
- Root AP uses Ethernet uplink
- Root AP has mesh hop count 0
- AP management IP may be assigned dynamically by DHCP

### Windows Validator

Validator host:

`10.1.0.130`

Required runtime directory:

`D:\FortiGateGPS\`

Required Windows component:

`C:\Windows\System32\OpenSSH\ssh.exe`

The Windows validator must be able to connect to:

`10.1.0.1:8446`

The validator must also be able to listen on:

`TCP/8080`

## GitHub Repository Files

The Windows deployment files are stored under:

`windows/`

Required files:

- `FortiGateGPS.ps1`
- `SSH-AskPass.ps1`
- `SSH-AskPass.cmd`

The FortiManager reference configuration is stored under:

`fortimanager/fortigate-gps-production-reference.cli`

The FortiManager file in GitHub is informational only.

The production version is maintained in the FortiManager FE ADOM.

## Windows Runtime Files

Copy the following files into:

`D:\FortiGateGPS\`

Required files:

- `FortiGateGPS.ps1`
- `SSH-AskPass.ps1`
- `SSH-AskPass.cmd`

The following runtime file must also exist locally:

`FortiGateSSHPassword.dat`

This file is not stored in GitHub.

Temporary files may be created during execution:

- `GPS-Update-Commands.txt`
- `GPS-GNSS-Commands.txt`

These temporary files are excluded from GitHub by `.gitignore`.

## SSH AskPass Configuration

The Windows validator uses OpenSSH AskPass to provide the FortiGate password without interactive prompting.

Production files:

`SSH-AskPass.ps1`

`SSH-AskPass.cmd`

The main script configures:

`SSH_ASKPASS`

and:

`SSH_ASKPASS_REQUIRE=force`

The encrypted password is read from:

`D:\FortiGateGPS\FortiGateSSHPassword.dat`

The password file must be created or provisioned in the correct Windows user/machine context.

Do not assume the encrypted password file can be copied between unrelated systems and remain usable.

## FortiGate Administrator

The solution uses a dedicated FortiGate administrator:

`gps-automation`

Required settings:

- Access profile: `prof_admin`
- Trusted host: `10.1.0.130/32`
- SSH access through port `8446`

The password should not be stored directly in GitHub.

The FortiManager deployment script should use the approved FortiManager variable for the password.

Example reference:

`{{GPS_AUTOMATION_PASSWORD}}`

The actual FortiManager variable name should match the production FortiManager configuration.

## FortiManager Deployment

The production FortiGate configuration should be deployed through the FortiManager FE ADOM.

The reference file in GitHub is:

`fortimanager/fortigate-gps-production-reference.cli`

The FortiManager configuration creates or updates:

- `gps-automation`
- `GPS-Schedule-0000`
- `GPS-Schedule-0600`
- `GPS-Schedule-1200`
- `GPS-Schedule-1800`
- `GPS-WTP-Discovery`
- `GPS-Send-WTP-Discovery`
- `GPS-Update-0000`
- `GPS-Update-0600`
- `GPS-Update-1200`
- `GPS-Update-1800`

## Scheduled Triggers

The production schedule is:

- 00:00
- 06:00
- 12:00
- 18:00

Each scheduled trigger starts a production automation stitch.

## FortiGate Discovery Action

The discovery action runs:

`diagnose wireless-controller wlac -c wtp`

This collects the current FortiAP WTP information.

The output is passed to the next automation action as:

`%%results%%`

## FortiGate Webhook Action

The WTP discovery output is sent to:

`http://10.1.0.130:8080/api/gps/discovery/`

The webhook body contains the previous action output.

The Windows validator uses this data to identify the root FortiAP and extract the live AP session information.

## Windows Listener

The main production script is:

`D:\FortiGateGPS\FortiGateGPS.ps1`

The listener provides:

`/api/gps/discovery/`

and retains:

`/api/gps/parse/`

The primary production workflow uses:

`/api/gps/discovery/`

To manually start the validator:

`powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\FortiGateGPS\FortiGateGPS.ps1"`

A successful startup should show both listener endpoints and indicate that the script is waiting for FortiGate requests.

## Dynamic FortiAP Discovery

The Windows validator parses the WTP output and requires exactly one root candidate matching:

- FortiAP-432G
- `mesh-uplink: ethernet`
- `mesh hop count: 0`
- `connection state: Connected`

The active connection state contains the runtime AP IP and CAPWAP control source port.

Example:

`Connected (0-10.100.100.241:15246)`

The values in this example are not fixed production values.

The script extracts them dynamically for each run.

## GNSS Query

After discovering the AP session, the Windows validator connects to the FortiGate over OpenSSH.

The GNSS query uses:

`diagnose wireless-controller wlac wtpcmd <AP-IP> <CPORT> r&sh "cw_diag -c gnss get curr-pos"`

The AP IP and CAPWAP port are dynamically populated from the WTP discovery output.

## GNSS Validation

The FortiAP response is returned as hexadecimal data through the FortiGate.

The Windows validator decodes the response into ASCII.

A valid GPS response contains latitude and longitude values.

The script validates:

- Latitude is between -90 and 90
- Longitude is between -180 and 180

If validation fails, the FortiGate coordinates are not changed.

## FortiGate Coordinate Update

When valid coordinates are available, the Windows validator connects to the FortiGate using OpenSSH and applies:

`config system global`

`set gui-device-latitude "<latitude>"`

`set gui-device-longitude "<longitude>"`

`end`

The update is performed only after successful GPS validation.

## Manual Validation

After deployment, a production stitch can be tested manually from the FortiGate.

Example:

`diagnose automation test GPS-Update-0600`

The Windows validator should receive the request and display:

- Root FortiAP discovery
- Dynamic AP IP
- Dynamic CAPWAP port
- GNSS query execution
- Decoded GNSS response

If the AP has no valid GPS fix, the expected result is:

`NO VALID GPS FIX`

and:

`FortiGate coordinates will NOT be changed.`

## Security Requirements

Do not store the following in GitHub:

- `FortiGateSSHPassword.dat`
- FortiGate passwords
- API tokens
- private keys
- temporary command files
- log files containing sensitive data

The repository `.gitignore` excludes the known local runtime files.

## Operational Ownership

GitHub is used for:

- Windows production scripts
- documentation
- FortiManager reference configuration

FortiManager is used for:

- production FortiGate deployment
- maintenance of the operational FortiManager script
- FortiManager password variable handling

The Windows deployment and startup mechanism is handled separately through the approved endpoint-management process.
