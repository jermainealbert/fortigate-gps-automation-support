# ============================================================
# FortiGate / FortiAP GPS Validator
#
# Production design
#
# FortiGate:   10.1.0.1
# SSH port:    8446
# SSH user:    gps-automation
# Parser:      10.1.0.130:8080
#
# /api/gps/discovery/
#   1. Receive WTP information from FortiGate
#   2. Locate connected Ethernet FortiAP-432G root
#   3. Extract dynamic AP IP and CAPWAP cport
#   4. Query AP GNSS through FortiGate using OpenSSH
#   5. Validate GPS
#   6. Update FortiGate coordinates only if GPS is valid
#
# /api/gps/parse/
#   Existing/fallback direct GNSS parser
# ============================================================


# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

$FortiGate = "10.1.0.1"
$SSHPort   = 8446
$SSHUser   = "gps-automation"

$SSHExe =
    "C:\Windows\System32\OpenSSH\ssh.exe"

$AskPass =
    "D:\FortiGateGPS\SSH-AskPass.cmd"

$ListenPort = 8080

$GPSListenPath =
    "/api/gps/parse/"

$DiscoveryListenPath =
    "/api/gps/discovery/"

$GPSListenerURL =
    "http://+:$ListenPort$GPSListenPath"

$DiscoveryListenerURL =
    "http://+:$ListenPort$DiscoveryListenPath"

$CommandFile =
    "D:\FortiGateGPS\GPS-Update-Commands.txt"

$GNSSCommandFile =
    "D:\FortiGateGPS\GPS-GNSS-Commands.txt"


# ------------------------------------------------------------
# Validate required files
# ------------------------------------------------------------

if (-not (Test-Path $SSHExe)) {

    Write-Host "ERROR: OpenSSH client not found:"
    Write-Host $SSHExe
    exit 1
}

if (-not (Test-Path $AskPass)) {

    Write-Host "ERROR: SSH AskPass helper not found:"
    Write-Host $AskPass
    exit 1
}


# ------------------------------------------------------------
# Configure OpenSSH AskPass
# ------------------------------------------------------------

$env:SSH_ASKPASS = $AskPass
$env:SSH_ASKPASS_REQUIRE = "force"


# ------------------------------------------------------------
# Helper: Decode FortiGate wtpcmd hexadecimal output
# ------------------------------------------------------------

function Get-FortiAPDecodedText {

    param (
        [string]$InputText
    )

    $hexBytes =
        New-Object System.Collections.Generic.List[byte]

    foreach (
        $line in ($InputText -split "`r?`n")
    ) {

        if (
            $line -match
            '0x[0-9A-Fa-f]{4}:\s+((?:[0-9A-Fa-f]{2}\s+)+)'
        ) {

            $hexPart =
                $matches[1]

            foreach (
                $hex in ($hexPart -split '\s+')
            ) {

                if (
                    $hex -match
                    '^[0-9A-Fa-f]{2}$'
                ) {

                    $hexBytes.Add(
                        [Convert]::ToByte(
                            $hex,
                            16
                        )
                    )
                }
            }
        }
    }

    if ($hexBytes.Count -gt 0) {

        return (
            [System.Text.Encoding]::ASCII.GetString(
                $hexBytes.ToArray()
            ).Trim()
        )
    }

    return ""
}


# ------------------------------------------------------------
# Helper: Parse and validate GPS coordinates
# ------------------------------------------------------------

function Get-ValidatedGPS {

    param (
        [string]$GPSText
    )

    $result = [PSCustomObject]@{
        Valid     = $false
        Latitude  = $null
        Longitude = $null
    }

    if (
        $GPSText -match
        '(-?\d{1,2}\.\d+)\s*,\s*(-?\d{1,3}\.\d+)'
    ) {

        try {

            $latitude =
                [double]$matches[1]

            $longitude =
                [double]$matches[2]

            if (
                $latitude -ge -90 -and
                $latitude -le 90 -and
                $longitude -ge -180 -and
                $longitude -le 180
            ) {

                $result.Valid = $true
                $result.Latitude = $latitude
                $result.Longitude = $longitude
            }
        }
        catch {

            $result.Valid = $false
        }
    }

    return $result
}


# ------------------------------------------------------------
# Helper: Update FortiGate coordinates
# ------------------------------------------------------------

function Set-FortiGateCoordinates {

    param (
        [double]$Latitude,
        [double]$Longitude
    )

    $commands = @(
        "config system global"
        "set gui-device-latitude `"$Latitude`""
        "set gui-device-longitude `"$Longitude`""
        "end"
        "exit"
    )

    $commands |
        Set-Content `
            -Path $CommandFile `
            -Encoding ASCII


    Write-Host ""
    Write-Host "Updating FortiGate coordinates using OpenSSH..."
    Write-Host "Latitude  :" $Latitude
    Write-Host "Longitude :" $Longitude


    $SSHCommand =
        "`"$SSHExe`" " +
        "-tt " +
        "-o BatchMode=no " +
        "-o NumberOfPasswordPrompts=1 " +
        "-p $SSHPort " +
        "$SSHUser@$FortiGate " +
        "< `"$CommandFile`""


    $SSHOutput =
        & cmd.exe /c $SSHCommand 2>&1

    $SSHExitCode =
        $LASTEXITCODE


    Write-Host ""
    Write-Host "Coordinate update SSH output:"
    Write-Host "--------------------------------------------------"

    $SSHOutput |
        ForEach-Object {
            Write-Host $_
        }

    Write-Host "--------------------------------------------------"
    Write-Host "SSH exit code:" $SSHExitCode


    Remove-Item `
        $CommandFile `
        -Force `
        -ErrorAction SilentlyContinue


    return [PSCustomObject]@{
        ExitCode = $SSHExitCode
        Output   = $SSHOutput
    }
}


# ------------------------------------------------------------
# Create HTTP listener
# ------------------------------------------------------------

$listener =
    New-Object System.Net.HttpListener

$listener.Prefixes.Add(
    $GPSListenerURL
)

$listener.Prefixes.Add(
    $DiscoveryListenerURL
)


try {

    $listener.Start()

}
catch {

    Write-Host ""
    Write-Host "ERROR: Unable to start HTTP listener."
    Write-Host $_.Exception.Message
    exit 1
}


Write-Host ""
Write-Host "=================================================="
Write-Host "FortiGate GPS Validator"
Write-Host "=================================================="
Write-Host "GPS Listener       : $GPSListenerURL"
Write-Host "Discovery Listener : $DiscoveryListenerURL"
Write-Host "FortiGate          : $FortiGate"
Write-Host "SSH Port           : $SSHPort"
Write-Host "SSH User           : $SSHUser"
Write-Host ""
Write-Host "Waiting for FortiGate..."
Write-Host ""


# ============================================================
# Main loop
# ============================================================

while ($listener.IsListening) {

    try {

        $context =
            $listener.GetContext()

        $request =
            $context.Request

        $requestPath =
            $request.Url.AbsolutePath.ToLowerInvariant()


        Write-Host ""
        Write-Host "=================================================="
        Write-Host "Incoming FortiGate request"
        Write-Host "=================================================="
        Write-Host "Received     :" (Get-Date)
        Write-Host "Remote       :" $request.RemoteEndPoint
        Write-Host "HTTP Method  :" $request.HttpMethod
        Write-Host "Content-Type :" $request.ContentType
        Write-Host "Path         :" $requestPath
        Write-Host ""


        # ----------------------------------------------------
        # Read HTTP body
        # ----------------------------------------------------

        $reader =
            New-Object System.IO.StreamReader(
                $request.InputStream
            )

        $body =
            $reader.ReadToEnd()

        $reader.Close()


        # ====================================================
        # DISCOVERY + DYNAMIC GNSS FLOW
        # ====================================================

        if ($requestPath -eq $DiscoveryListenPath) {

            Write-Host "WTP DISCOVERY REQUEST"
            Write-Host "--------------------------------------------------"


            # ------------------------------------------------
            # Extract FortiGate action results
            # ------------------------------------------------

            $discoveryText =
                $body

            try {

                $payload =
                    $body |
                        ConvertFrom-Json -ErrorAction Stop

                if ($null -ne $payload.results) {

                    $discoveryText =
                        [string]$payload.results
                }
            }
            catch {

                Write-Host "NOTICE: JSON parsing failed."
                Write-Host "Using raw request body."
            }


            # ------------------------------------------------
            # Split into WTP blocks
            # ------------------------------------------------

            $wtpPattern =
                '(?ms)^-+WTP\s+\d+-+\s*$.*?(?=^-+WTP\s+\d+-+\s*$|^-+Total\s+\d+\s+WTPs-+\s*$|\z)'

            $wtpMatches =
                [regex]::Matches(
                    $discoveryText,
                    $wtpPattern
                )


            $rootCandidates =
                @()


            foreach ($wtpMatch in $wtpMatches) {

                $block =
                    $wtpMatch.Value


                # Require FortiAP-432G
                if (
                    $block -notmatch
                    '(?m)^\s*active sw ver\s*:\s*FP432G-'
                ) {
                    continue
                }


                # Require Ethernet root
                if (
                    $block -notmatch
                    '(?m)^\s*mesh-uplink\s*:\s*ethernet\s*$'
                ) {
                    continue
                }


                # Require zero mesh hops
                if (
                    $block -notmatch
                    '(?m)^\s*mesh hop count\s*:\s*0\s*$'
                ) {
                    continue
                }


                # AP software/model
                $model =
                    "FP432G"

                $versionMatch =
                    [regex]::Match(
                        $block,
                        '(?m)^\s*active sw ver\s*:\s*(\S+)\s*$'
                    )

                if ($versionMatch.Success) {

                    $model =
                        $versionMatch.Groups[1].Value
                }


                # AP name - diagnostic only
                $apName =
                    $null

                $nameMatch =
                    [regex]::Match(
                        $block,
                        '(?m)^\s*name\s*:\s*(\S.*?)\s*$'
                    )

                if ($nameMatch.Success) {

                    $apName =
                        $nameMatch.Groups[1].Value.Trim()
                }


                # Dynamic WTP session
                $connectionMatch =
                    [regex]::Match(
                        $block,
                        '(?m)^\s*connection state\s*:\s*Connected\s+\(0-([0-9]{1,3}(?:\.[0-9]{1,3}){3}):(\d+)\)\s*$'
                    )

                if (-not $connectionMatch.Success) {

                    continue
                }


                $apIP =
                    $connectionMatch.Groups[1].Value

                $cport =
                    [int]$connectionMatch.Groups[2].Value


                # Validate IP
                $parsedIP =
                    $null

                if (
                    -not [System.Net.IPAddress]::TryParse(
                        $apIP,
                        [ref]$parsedIP
                    )
                ) {

                    continue
                }


                # Validate cport
                if (
                    $cport -lt 1 -or
                    $cport -gt 65535
                ) {

                    continue
                }


                $rootCandidates +=
                    [PSCustomObject]@{
                        model = $model
                        name  = $apName
                        ip    = $apIP
                        cport = $cport
                    }
            }


            # ------------------------------------------------
            # Exactly one root candidate required
            # ------------------------------------------------

            if ($rootCandidates.Count -ne 1) {

                if ($rootCandidates.Count -eq 0) {

                    Write-Host ""
                    Write-Host "NO VALID 432G ROOT AP FOUND"

                    $result = @{
                        valid      = $false
                        discovered = $false
                        updated    = $false
                        action     = "none"
                        error      = "No connected Ethernet FortiAP-432G with mesh hop count 0 was found"
                    }

                }
                else {

                    Write-Host ""
                    Write-Host "MULTIPLE 432G ROOT AP CANDIDATES FOUND"

                    $result = @{
                        valid      = $false
                        discovered = $false
                        updated    = $false
                        action     = "none"
                        error      = "Multiple connected Ethernet FortiAP-432G root candidates were found"
                        candidates = $rootCandidates.Count
                    }
                }


                $responseText =
                    $result |
                        ConvertTo-Json -Compress

                $buffer =
                    [System.Text.Encoding]::UTF8.GetBytes(
                        $responseText
                    )

                $context.Response.StatusCode = 200
                $context.Response.ContentType = "application/json"
                $context.Response.ContentLength64 =
                    $buffer.Length

                $context.Response.OutputStream.Write(
                    $buffer,
                    0,
                    $buffer.Length
                )

                $context.Response.OutputStream.Close()

                Write-Host ""
                Write-Host "Response to FortiGate:"
                Write-Host $responseText

                Write-Host ""
                Write-Host "Waiting for next FortiGate request..."

                continue
            }


            # ------------------------------------------------
            # Root AP found
            # ------------------------------------------------

            $rootAP =
                $rootCandidates[0]


            Write-Host ""
            Write-Host "ROOT FORTIAP FOUND"
            Write-Host "Model  :" $rootAP.model
            Write-Host "Name   :" $rootAP.name
            Write-Host "Uplink : ethernet"
            Write-Host "Hop    : 0"
            Write-Host "IP     :" $rootAP.ip
            Write-Host "cport  :" $rootAP.cport


            # ------------------------------------------------
            # Build dynamic GNSS command
            # ------------------------------------------------

            $GNSSCommands = @(
                "diagnose wireless-controller wlac wtpcmd $($rootAP.ip) $($rootAP.cport) r&sh `"cw_diag -c gnss get curr-pos`""
                "exit"
            )

            $GNSSCommands |
                Set-Content `
                    -Path $GNSSCommandFile `
                    -Encoding ASCII


            Write-Host ""
            Write-Host "Running GNSS query through FortiGate..."
            Write-Host "AP IP  :" $rootAP.ip
            Write-Host "cport  :" $rootAP.cport


            $GNSSSSHCommand =
                "`"$SSHExe`" " +
                "-tt " +
                "-o BatchMode=no " +
                "-o NumberOfPasswordPrompts=1 " +
                "-p $SSHPort " +
                "$SSHUser@$FortiGate " +
                "< `"$GNSSCommandFile`""


            $GNSSOutput =
                & cmd.exe /c $GNSSSSHCommand 2>&1

            $GNSSExitCode =
                $LASTEXITCODE


            Remove-Item `
                $GNSSCommandFile `
                -Force `
                -ErrorAction SilentlyContinue


            Write-Host ""
            Write-Host "GNSS SSH output:"
            Write-Host "--------------------------------------------------"

            $GNSSOutput |
                ForEach-Object {
                    Write-Host $_
                }

            Write-Host "--------------------------------------------------"
            Write-Host "GNSS SSH exit code:" $GNSSExitCode


            # ------------------------------------------------
            # Decode GNSS hex response
            # ------------------------------------------------

            $GNSSOutputText =
                ($GNSSOutput -join "`n")

            $gpsText =
                Get-FortiAPDecodedText `
                    -InputText $GNSSOutputText


            Write-Host ""
            Write-Host "Decoded FortiAP GNSS response:"
            Write-Host "--------------------------------------------------"

            if (
                [string]::IsNullOrWhiteSpace(
                    $gpsText
                )
            ) {

                Write-Host "<No FortiAP response decoded>"
            }
            else {

                Write-Host $gpsText
            }

            Write-Host "--------------------------------------------------"


            # ------------------------------------------------
            # Validate GPS
            # ------------------------------------------------

            $gps =
                Get-ValidatedGPS `
                    -GPSText $gpsText



            # =================================================
            # INVALID GPS - DO NOTHING
            # =================================================

            if (-not $gps.Valid) {

                Write-Host ""
                Write-Host "NO VALID GPS FIX"
                Write-Host "FortiGate coordinates will NOT be changed."


                $result = @{
                    valid      = $false
                    discovered = $true
                    updated    = $false
                    action     = "none"
                    ip         = $rootAP.ip
                    cport      = $rootAP.cport
                    model      = $rootAP.model
                }


                $responseText =
                    $result |
                        ConvertTo-Json -Compress


                $buffer =
                    [System.Text.Encoding]::UTF8.GetBytes(
                        $responseText
                    )


                $context.Response.StatusCode = 200
                $context.Response.ContentType = "application/json"
                $context.Response.ContentLength64 =
                    $buffer.Length


                $context.Response.OutputStream.Write(
                    $buffer,
                    0,
                    $buffer.Length
                )


                $context.Response.OutputStream.Close()


                Write-Host ""
                Write-Host "Response to FortiGate:"
                Write-Host $responseText

                Write-Host ""
                Write-Host "Waiting for next FortiGate request..."


                continue
            }


            # =================================================
            # VALID GPS
            # =================================================

            Write-Host ""
            Write-Host "VALID GPS FIX"
            Write-Host "Latitude  :" $gps.Latitude
            Write-Host "Longitude :" $gps.Longitude


            $update =
                Set-FortiGateCoordinates `
                    -Latitude $gps.Latitude `
                    -Longitude $gps.Longitude


            if ($update.ExitCode -eq 0) {

                Write-Host ""
                Write-Host "FORTIGATE LOCATION UPDATE COMPLETED"


                $result = @{
                    valid      = $true
                    discovered = $true
                    updated    = $true
                    latitude   = $gps.Latitude
                    longitude  = $gps.Longitude
                    ip         = $rootAP.ip
                    cport      = $rootAP.cport
                    model      = $rootAP.model
                    method     = "OpenSSH"
                    action     = "coordinates-updated"
                }

            }
            else {

                Write-Host ""
                Write-Host "ERROR: FortiGate coordinate update failed."


                $result = @{
                    valid      = $true
                    discovered = $true
                    updated    = $false
                    latitude   = $gps.Latitude
                    longitude  = $gps.Longitude
                    ip         = $rootAP.ip
                    cport      = $rootAP.cport
                    model      = $rootAP.model
                    method     = "OpenSSH"
                    action     = "update-failed"
                    error      = "SSH coordinate update failed"
                    exitcode   = $update.ExitCode
                }
            }


            # ------------------------------------------------
            # Return discovery/GPS result
            # ------------------------------------------------

            $responseText =
                $result |
                    ConvertTo-Json -Compress


            $buffer =
                [System.Text.Encoding]::UTF8.GetBytes(
                    $responseText
                )


            $context.Response.StatusCode = 200
            $context.Response.ContentType = "application/json"
            $context.Response.ContentLength64 =
                $buffer.Length


            $context.Response.OutputStream.Write(
                $buffer,
                0,
                $buffer.Length
            )


            $context.Response.OutputStream.Close()


            Write-Host ""
            Write-Host "Response to FortiGate:"
            Write-Host $responseText

            Write-Host ""
            Write-Host "=================================================="
            Write-Host "Waiting for next FortiGate request..."

            continue
        }


        # ====================================================
        # EXISTING /api/gps/parse/ FALLBACK
        # ====================================================

        if ($requestPath -eq $GPSListenPath) {

            Write-Host "GPS COLLECTION REQUEST"
            Write-Host "--------------------------------------------------"


            $gpsText =
                Get-FortiAPDecodedText `
                    -InputText $body


            Write-Host "Decoded FortiAP response:"
            Write-Host "--------------------------------------------------"

            if (
                [string]::IsNullOrWhiteSpace(
                    $gpsText
                )
            ) {

                Write-Host "<No FortiAP response decoded>"
            }
            else {

                Write-Host $gpsText
            }

            Write-Host "--------------------------------------------------"


            $gps =
                Get-ValidatedGPS `
                    -GPSText $gpsText


            if (-not $gps.Valid) {

                Write-Host ""
                Write-Host "NO VALID GPS FIX"
                Write-Host "FortiGate coordinates will NOT be changed."


                $result = @{
                    valid   = $false
                    updated = $false
                    action  = "none"
                }

            }
            else {

                Write-Host ""
                Write-Host "VALID GPS FIX"
                Write-Host "Latitude  :" $gps.Latitude
                Write-Host "Longitude :" $gps.Longitude


                $update =
                    Set-FortiGateCoordinates `
                        -Latitude $gps.Latitude `
                        -Longitude $gps.Longitude


                if ($update.ExitCode -eq 0) {

                    $result = @{
                        valid     = $true
                        updated   = $true
                        latitude  = $gps.Latitude
                        longitude = $gps.Longitude
                        method    = "OpenSSH"
                    }

                }
                else {

                    $result = @{
                        valid     = $true
                        updated   = $false
                        latitude  = $gps.Latitude
                        longitude = $gps.Longitude
                        method    = "OpenSSH"
                        error     = "SSH update failed"
                        exitcode  = $update.ExitCode
                    }
                }
            }


            $responseText =
                $result |
                    ConvertTo-Json -Compress


            $buffer =
                [System.Text.Encoding]::UTF8.GetBytes(
                    $responseText
                )


            $context.Response.StatusCode = 200
            $context.Response.ContentType = "application/json"
            $context.Response.ContentLength64 =
                $buffer.Length


            $context.Response.OutputStream.Write(
                $buffer,
                0,
                $buffer.Length
            )


            $context.Response.OutputStream.Close()


            Write-Host ""
            Write-Host "Response to FortiGate:"
            Write-Host $responseText

            Write-Host ""
            Write-Host "Waiting for next FortiGate request..."

            continue
        }


        # ====================================================
        # UNKNOWN ENDPOINT
        # ====================================================

        $result = @{
            valid  = $false
            action = "none"
            error  = "Unknown API endpoint"
        }


        $responseText =
            $result |
                ConvertTo-Json -Compress


        $buffer =
            [System.Text.Encoding]::UTF8.GetBytes(
                $responseText
            )


        $context.Response.StatusCode = 404
        $context.Response.ContentType = "application/json"
        $context.Response.ContentLength64 =
            $buffer.Length


        $context.Response.OutputStream.Write(
            $buffer,
            0,
            $buffer.Length
        )


        $context.Response.OutputStream.Close()

    }


    # ========================================================
    # Unexpected processing error
    # ========================================================

    catch {

        Write-Host ""
        Write-Host "ERROR processing FortiGate request:"
        Write-Host $_.Exception.Message


        try {

            $errorResult = @{
                valid   = $false
                updated = $false
                error   = "GPS validator internal error"
            }


            $errorText =
                $errorResult |
                    ConvertTo-Json -Compress


            $errorBuffer =
                [System.Text.Encoding]::UTF8.GetBytes(
                    $errorText
                )


            $context.Response.StatusCode = 500
            $context.Response.ContentType = "application/json"
            $context.Response.ContentLength64 =
                $errorBuffer.Length


            $context.Response.OutputStream.Write(
                $errorBuffer,
                0,
                $errorBuffer.Length
            )


            $context.Response.OutputStream.Close()

        }
        catch {

            Write-Host "Unable to return HTTP error response."
        }


        Remove-Item `
            $CommandFile `
            -Force `
            -ErrorAction SilentlyContinue

        Remove-Item `
            $GNSSCommandFile `
            -Force `
            -ErrorAction SilentlyContinue


        Write-Host ""
        Write-Host "Waiting for next FortiGate request..."
    }
}