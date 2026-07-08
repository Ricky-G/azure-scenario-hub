#Requires -Version 7.0
<#
.SYNOPSIS
    Generates the full certificate set for the mTLS passthrough POC.

.DESCRIPTION
    Uses OpenSSL to create:
      - A trusted Root CA
      - client1 and client2 leaf certs (signed by the Root CA, clientAuth EKU)
      - A rogue Root CA + rogue leaf cert (UNtrusted issuer)
      - A self-signed server cert (+ PFX) for the App Gateway HTTPS listener

    It then computes SHA-1 thumbprints, builds the per-client allow list, and
    writes certs/manifest.json which the deploy script consumes.

    All output lands in ./certs which is git-ignored.

.PARAMETER FrontendHostName
    CN/SAN for the App Gateway server certificate. Must match the SNI host
    that clients present (via curl --resolve). Default: api.mtls-poc.local
#>
[CmdletBinding()]
param(
    [string]$FrontendHostName = 'api.mtls-poc.local',
    [string]$PfxPassword = "Poc-$([guid]::NewGuid().ToString('N').Substring(0,12))"
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$certDir = Join-Path $scriptDir 'certs'

# ---- Locate OpenSSL --------------------------------------------------
$opensslCmd = (Get-Command openssl -ErrorAction SilentlyContinue).Source
if (-not $opensslCmd) {
    $candidates = @(
        'C:\Program Files\Git\usr\bin\openssl.exe',
        'C:\Program Files\Git\mingw64\bin\openssl.exe',
        'C:\Program Files (x86)\Git\usr\bin\openssl.exe'
    )
    $opensslCmd = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $opensslCmd) { throw 'OpenSSL not found. Install OpenSSL or Git for Windows.' }
Write-Host "==> Using OpenSSL: $opensslCmd" -ForegroundColor Cyan

function Invoke-OpenSSL {
    param([Parameter(Mandatory = $true, Position = 0)][string[]]$OpenSSLArgs)
    & $opensslCmd @OpenSSLArgs 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "openssl failed: $($OpenSSLArgs -join ' ')" }
}

function Get-Thumbprint {
    param([string]$CertPath)
    $line = & $opensslCmd x509 -in $CertPath -noout -fingerprint -sha1
    if ($LASTEXITCODE -ne 0) { throw "openssl fingerprint failed for $CertPath" }
    # Format: "SHA1 Fingerprint=AA:BB:CC..."
    return ($line -split '=')[1].Replace(':', '').Trim().ToUpper()
}

# ---- Fresh cert directory -------------------------------------------
if (Test-Path $certDir) { Remove-Item $certDir -Recurse -Force }
New-Item -ItemType Directory -Path $certDir | Out-Null
Push-Location $certDir
try {
    # Extension config files
    @'
basicConstraints = CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth
subjectKeyIdentifier = hash
'@ | Set-Content -Path 'client_ext.cnf' -Encoding ascii

    Write-Host '==> Generating trusted Root CA...' -ForegroundColor Cyan
    Invoke-OpenSSL @('genrsa', '-out', 'rootCA.key', '4096')
    Invoke-OpenSSL @('req', '-x509', '-new', '-nodes', '-key', 'rootCA.key', '-sha256', '-days', '3650', '-out', 'rootCA.crt',
        '-subj', '/CN=mTLS POC Root CA/O=AzureScenarioHub/C=US',
        '-addext', 'basicConstraints=critical,CA:TRUE',
        '-addext', 'keyUsage=critical,keyCertSign,cRLSign')

    foreach ($c in @('client1', 'client2', 'client3')) {
        Write-Host "==> Generating $c (signed by trusted Root CA)..." -ForegroundColor Cyan
        Invoke-OpenSSL @('genrsa', '-out', "$c.key", '2048')
        Invoke-OpenSSL @('req', '-new', '-key', "$c.key", '-out', "$c.csr", '-subj', "/CN=$c.mtls-poc.local/O=Legacy Client $c/C=US")
        Invoke-OpenSSL @('x509', '-req', '-in', "$c.csr", '-CA', 'rootCA.crt', '-CAkey', 'rootCA.key', '-CAcreateserial',
            '-out', "$c.crt", '-days', '825', '-sha256', '-extfile', 'client_ext.cnf')
    }

    Write-Host '==> Generating ROGUE CA + rogue client (untrusted issuer)...' -ForegroundColor Cyan
    Invoke-OpenSSL @('genrsa', '-out', 'rogueCA.key', '4096')
    Invoke-OpenSSL @('req', '-x509', '-new', '-nodes', '-key', 'rogueCA.key', '-sha256', '-days', '3650', '-out', 'rogueCA.crt',
        '-subj', '/CN=Rogue Untrusted CA/O=RogueCorp/C=US',
        '-addext', 'basicConstraints=critical,CA:TRUE',
        '-addext', 'keyUsage=critical,keyCertSign,cRLSign')
    Invoke-OpenSSL @('genrsa', '-out', 'rogue.key', '2048')
    Invoke-OpenSSL @('req', '-new', '-key', 'rogue.key', '-out', 'rogue.csr', '-subj', '/CN=rogue.mtls-poc.local/O=Rogue Client/C=US')
    Invoke-OpenSSL @('x509', '-req', '-in', 'rogue.csr', '-CA', 'rogueCA.crt', '-CAkey', 'rogueCA.key', '-CAcreateserial',
        '-out', 'rogue.crt', '-days', '825', '-sha256', '-extfile', 'client_ext.cnf')

    # SPOOFED issuer: a DIFFERENT CA key that copies the trusted Root CA's exact
    # subject DN ("CN=mTLS POC Root CA..."). Its leaf therefore has an identical
    # issuer *string* to a genuine cert but a signature the real Root CA never
    # produced. This is the cert that separates a name-compare (would ACCEPT it)
    # from real signature verification (chain mode REJECTS it as NOT_CA_SIGNED).
    Write-Host '==> Generating SPOOFED-issuer client (same issuer DN, wrong key)...' -ForegroundColor Cyan
    Invoke-OpenSSL @('genrsa', '-out', 'spoofCA.key', '4096')
    Invoke-OpenSSL @('req', '-x509', '-new', '-nodes', '-key', 'spoofCA.key', '-sha256', '-days', '3650', '-out', 'spoofCA.crt',
        '-subj', '/CN=mTLS POC Root CA/O=AzureScenarioHub/C=US',
        '-addext', 'basicConstraints=critical,CA:TRUE',
        '-addext', 'keyUsage=critical,keyCertSign,cRLSign')
    Invoke-OpenSSL @('genrsa', '-out', 'spoofed.key', '2048')
    Invoke-OpenSSL @('req', '-new', '-key', 'spoofed.key', '-out', 'spoofed.csr', '-subj', '/CN=client1.mtls-poc.local/O=Legacy Client client1/C=US')
    Invoke-OpenSSL @('x509', '-req', '-in', 'spoofed.csr', '-CA', 'spoofCA.crt', '-CAkey', 'spoofCA.key', '-CAcreateserial',
        '-out', 'spoofed.crt', '-days', '825', '-sha256', '-extfile', 'client_ext.cnf')

    Write-Host "==> Generating App Gateway server cert (CN=$FrontendHostName)..." -ForegroundColor Cyan
    Invoke-OpenSSL @('genrsa', '-out', 'appgw-server.key', '2048')
    Invoke-OpenSSL @('req', '-x509', '-new', '-nodes', '-key', 'appgw-server.key', '-sha256', '-days', '825', '-out', 'appgw-server.crt',
        '-subj', "/CN=$FrontendHostName/O=AppGw POC/C=US",
        '-addext', "subjectAltName=DNS:$FrontendHostName",
        '-addext', 'keyUsage=critical,digitalSignature,keyEncipherment',
        '-addext', 'extendedKeyUsage=serverAuth',
        '-addext', 'basicConstraints=CA:FALSE')
    # Modern PKCS#12 encoding (AES-256 / PBKDF2 / SHA-256). Do NOT use the
    # legacy PBE-SHA1-3DES flags: Application Gateway runs on OpenSSL 3.x,
    # which cannot load legacy SHA1-3DES PFX files without the legacy
    # provider, so the gateway would accept TCP but fail the TLS handshake.
    Invoke-OpenSSL @('pkcs12', '-export', '-out', 'appgw-server.pfx', '-inkey', 'appgw-server.key', '-in', 'appgw-server.crt',
        '-passout', "pass:$PfxPassword")

    # Root CA in DER for the APIM policy (base64, single line)
    Invoke-OpenSSL @('x509', '-in', 'rootCA.crt', '-outform', 'DER', '-out', 'rootCA.der')

    # ---- Compute thumbprints + manifest ------------------------------
    $tp1 = Get-Thumbprint 'client1.crt'
    $tp2 = Get-Thumbprint 'client2.crt'
    $tp3 = Get-Thumbprint 'client3.crt'
    $tpRogue = Get-Thumbprint 'rogue.crt'
    $tpSpoof = Get-Thumbprint 'spoofed.crt'

    $manifest = [ordered]@{
        frontendHostName     = $FrontendHostName
        serverCertPassword   = $PfxPassword
        serverCertPfxB64     = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $certDir 'appgw-server.pfx')))
        trustedRootCaDerB64  = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $certDir 'rootCA.der')))
        rootCaCertB64        = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $certDir 'rootCA.crt')))
        client1Thumbprint    = $tp1
        client2Thumbprint    = $tp2
        client3Thumbprint    = $tp3
        rogueThumbprint      = $tpRogue
        spoofedThumbprint    = $tpSpoof
        # client3 is CA-signed but deliberately NOT allow-listed: it is the
        # discriminator that proves pinned mode (403) differs from chain mode (200).
        clientCertAllowlist  = "client1:$tp1|client2:$tp2"
    }
    $manifest | ConvertTo-Json | Set-Content -Path (Join-Path $certDir 'manifest.json') -Encoding ascii

    Write-Host ''
    Write-Host '==> Certificate set generated.' -ForegroundColor Green
    Write-Host ("    client1 thumbprint : {0} (allow-listed)" -f $tp1)
    Write-Host ("    client2 thumbprint : {0} (allow-listed)" -f $tp2)
    Write-Host ("    client3 thumbprint : {0} (CA-signed, NOT allow-listed)" -f $tp3)
    Write-Host ("    rogue   thumbprint : {0} (untrusted issuer)" -f $tpRogue)
    Write-Host ("    spoofed thumbprint : {0} (same issuer DN, forged signature)" -f $tpSpoof)
    Write-Host ("    manifest           : {0}" -f (Join-Path $certDir 'manifest.json'))
}
finally {
    Pop-Location
}
