# Validation

## Overview

This document describes the validation completed for the FortiGate GPS automation solution.

The goal of validation was to confirm that the workflow can:

- Dynamically identify the correct FortiAP-432G root AP
- Extract the current AP management IP
- Extract the current CAPWAP control port
- Query FortiAP GNSS through the FortiGate
- Decode the FortiAP response
- Reject invalid GPS data
- Update FortiGate coordinates when valid GPS data is available
- Run through the production FortiGate automation workflow

## Environment

Validated components:

- FortiOS: 7.6.7
- FortiGate management IP: `10.1.0.1`
- FortiGate SSH port: `8446`
- Windows validator: `10.1.0.130`
- FortiAP model: FortiAP-432G
- Windows OpenSSH client
- PowerShell validator script

## WTP Discovery Validation

The FortiGate WTP discovery command was validated using:

`diagnose wireless-controller wlac -c wtp`

The output successfully exposed the required runtime information for the connected FortiAP.

Validated fields included:

- FortiAP software/model
- AP name
- Local management IP
- Mesh uplink
- Mesh hop count
- Connection state
- Live WTP session IP and CAPWAP control port

Example validated connection state:

`Connected (0-10.100.100.241:15246)`

This demonstrated that the FortiGate already knows both the current DHCP-assigned AP IP and live CAPWAP control port.

## Dynamic Root AP Selection

The Windows validator successfully identified the correct root AP using:

- Model: `FP432G`
- Mesh uplink: `ethernet`
- Mesh hop count: `0`
- Connection state: `Connected`

The workflow does not rely on:

- A fixed AP IP
- A fixed CAPWAP source port
- A site-specific AP serial number
- A site-specific AP name

## Webhook Validation

The FortiGate successfully sent WTP discovery output to:

`http://10.1.0.130:8080/api/gps/discovery/`

The Windows validator successfully received and parsed the request.

The validator returned a discovery response containing:

- Discovery status
- AP IP
- CAPWAP control port
- AP model
- AP name
- Mesh hop count
- Uplink type

## OpenSSH Validation

The Windows validator successfully connected to the FortiGate using:

- OpenSSH
- SSH port `8446`
- User `gps-automation`
- OpenSSH AskPass
- Locally protected password data

The FortiGate accepted CLI commands provided through redirected stdin with a forced pseudo-terminal.

This validated unattended command execution from the Windows validator.

## Dynamic GNSS Query Validation

The Windows validator successfully built a GNSS query using the discovered AP IP and CAPWAP control port.

Validated command format:

`diagnose wireless-controller wlac wtpcmd <AP-IP> <CPORT> r&sh "cw_diag -c gnss get curr-pos"`

A successful runtime example used:

- AP IP: `10.100.100.241`
- CAPWAP port: `15246`

These values were dynamically discovered and were not hard-coded into the production workflow.

## FortiAP GNSS Response Validation

The FortiAP response was successfully returned through the FortiGate as hexadecimal data.

The Windows validator successfully decoded the hexadecimal bytes into readable ASCII text.

An invalid GPS response was decoded as:

`No valid GPS location data.`

This confirmed that the validator can interpret FortiAP GNSS output returned through `wtpcmd`.

## Invalid GPS Validation

The invalid GPS path was tested end-to-end.

Observed behavior:

- Root FortiAP discovered successfully
- Dynamic AP IP extracted
- Dynamic CAPWAP port extracted
- GNSS query executed successfully
- FortiAP response decoded
- No valid coordinates found
- FortiGate coordinate update was skipped

Expected console result:

`NO VALID GPS FIX`

`FortiGate coordinates will NOT be changed.`

The validator also returned a response indicating:

- `valid = false`
- `discovered = true`
- `updated = false`
- `action = none`

This validates the fail-closed behavior of the solution.

## Valid GPS Validation

The valid GPS path was validated using controlled test coordinates.

Test coordinates:

- Latitude: `31.701869`
- Longitude: `-103.443221`

The validator successfully processed the valid coordinates and executed the FortiGate coordinate update over OpenSSH.

The FortiGate accepted:

`set gui-device-latitude "31.701869"`

`set gui-device-longitude "-103.443221"`

This validated the coordinate-update path.

The temporary forced-valid test override was removed after validation so production operation uses actual GNSS data.

## Coordinate Range Validation

The validator confirms that coordinates fall within valid geographic ranges.

Latitude requirement:

`-90 <= latitude <= 90`

Longitude requirement:

`-180 <= longitude <= 180`

Coordinates outside these ranges are rejected.

## FortiGate Automation Validation

The production workflow uses:

`GPS-WTP-Discovery`

followed by:

`GPS-Send-WTP-Discovery`

The production automation stitches are:

- `GPS-Update-0000`
- `GPS-Update-0600`
- `GPS-Update-1200`
- `GPS-Update-1800`

A production stitch was manually executed using:

`diagnose automation test GPS-Update-0600`

The request successfully reached the Windows validator and followed the expected dynamic discovery and GNSS processing path.

## Schedule Validation

The configured FortiGate schedule runs at:

- 00:00
- 06:00
- 12:00
- 18:00

The scheduled stitches use the same production actions that were validated manually.

## FortiGate CLI Result Chaining Validation

FortiGate automation was tested to determine whether CLI output could be directly reused as executable input in another CLI automation action.

The WTP discovery output was successfully captured as automation action results.

However, when multiline `%%results%%` content was inserted into a subsequent CLI script action, FortiOS detected embedded newline content and sanitized the parameter.

This confirmed that direct FortiGate CLI-to-CLI dynamic command construction was not suitable for this workflow.

The final architecture therefore sends discovery output to the Windows validator, which safely parses the runtime values and constructs the required GNSS query.

## Fail-Safe Behavior

The solution was specifically validated to fail safely.

The FortiGate coordinates are not changed when:

- No FortiAP-432G root candidate is found
- Multiple root candidates are found
- The AP session cannot be identified
- The AP IP cannot be validated
- The CAPWAP control port cannot be validated
- GNSS output cannot be decoded
- No valid GPS coordinates are returned
- Latitude is outside the valid range
- Longitude is outside the valid range

## Production Validation Status

The following items have been successfully validated:

- FortiAP-432G dynamic discovery
- DHCP-assigned AP IP discovery
- CAPWAP control-port discovery
- Root AP selection
- FortiGate-to-Windows webhook delivery
- Windows request parsing
- OpenSSH authentication
- Unattended FortiGate CLI execution
- Dynamic FortiAP GNSS query
- FortiAP hexadecimal response decoding
- Invalid GPS fail-safe behavior
- Valid GPS coordinate update
- FortiGate production automation stitch execution
- Four-times-daily production schedule configuration

## Final Result

The production workflow has been validated end-to-end.

The solution dynamically discovers the FortiAP session at runtime, validates GNSS data before making any changes, and updates the FortiGate location only when a valid GPS fix is available.
