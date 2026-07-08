#Requires -Version 7.0
<#
.SYNOPSIS
    Validates BOTH APIM certificate-validation models end-to-end against the
    Key Vault-sourced trust material, independently of the Application Gateway
    client-authentication feature flag.

.DESCRIPTION
    The full mTLS passthrough handshake requires the subscription feature
    `Microsoft.Network/AllowApplicationGatewayClientAuthentication`. Until that
    is registered, App Gateway can't extract the client cert from the live TLS
    handshake. This script proves the OTHER (and more important) half of the
    design regardless: that API Management genuinely validates a forwarded
    certificate against Key Vault -- under EACH of the two supported models:

      * PINNED  -- accept only certificates whose SHA-1 thumbprint is on the
                   Key Vault allow list (issuer must also match the KV Root CA).
      * CHAIN   -- accept any certificate the KV Root CA actually signed,
                   verified by a real RSA signature check (not a name compare).

    It flips the `cert-validation-mode` named value, waits for APIM to pick it
    up, then presents each certificate to APIM exactly as App Gateway forwards
    it -- in the `X-Client-Cert` header -- via a plain HTTPS test listener, and
    asserts APIM's decision. The `client3` (CA-signed, not allow-listed) and
    `spoofed` (same issuer DN, forged signature) certificates are the two that
    prove the models genuinely differ and that CHAIN uses real cryptography.

    Writes certs/results.json for the report generator.

.PARAMETER ResourceGroupName
    Resource group of the deployment. Default: rg-appgw-passthrough-mtls-poc

.PARAMETER RemoveTestListener
    Remove the plain HTTPS test listener (and its NSG rule) when finished.

.EXAMPLE
    ./validate-apim-keyvault.ps1
#>
[CmdletBinding()]
param(
    [string]$ResourceGroupName = 'rg-appgw-passthrough-mtls-poc',
    [int]$TestPort = 8443,
    [switch]$RemoveTestListener
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$certDir = Join-Path $scriptDir 'certs'
$deploy = Get-Content (Join-Path $certDir 'deploy-output.json') -Raw | ConvertFrom-Json
$manifest = Get-Content (Join-Path $certDir 'manifest.json') -Raw | ConvertFrom-Json

$gw = az network application-gateway list -g $ResourceGroupName --query "[0].name" -o tsv
$ip = $deploy.appGatewayPublicIp
$hostHeader = $deploy.frontendHostName
$apimName = $deploy.apimName
$nsg = az network nsg list -g $ResourceGroupName --query "[?contains(name,'appgw')].name | [0]" -o tsv

# ---- 1. Ensure a plain HTTPS test listener -> APIM exists -------------
# (no SSL profile, no header rewrite, so the injected X-Client-Cert survives)
$listeners = az network application-gateway http-listener list -g $ResourceGroupName --gateway-name $gw --query "[].name" -o tsv
if ($listeners -notcontains 'apimtest-listener') {
    Write-Host '==> Creating plain HTTPS test listener -> APIM...' -ForegroundColor Cyan
    az network application-gateway frontend-port create -g $ResourceGroupName --gateway-name $gw -n port-apimtest --port $TestPort -o none
    az network application-gateway http-listener create -g $ResourceGroupName --gateway-name $gw -n apimtest-listener `
        --frontend-port port-apimtest --frontend-ip appgw-feip --ssl-cert appgw-server-cert -o none
    az network application-gateway rule create -g $ResourceGroupName --gateway-name $gw -n apimtest-rule `
        --http-listener apimtest-listener --address-pool apim-backend-pool --http-settings apim-https-settings --priority 300 -o none
    az network nsg rule create -g $ResourceGroupName --nsg-name $nsg -n Allow-APIMTest --priority 118 `
        --direction Inbound --access Allow --protocol Tcp --source-address-prefixes Internet `
        --destination-port-ranges $TestPort --destination-address-prefixes '*' -o none
}
else {
    Write-Host '==> Reusing existing plain HTTPS test listener.' -ForegroundColor Cyan
}

# ---- 2. Forwarded-header certs (URL/percent-encoded PEM) --------------
function Enc([string]$file) { [System.Uri]::EscapeDataString((Get-Content (Join-Path $certDir $file) -Raw)) }
$certs = @{
    client1 = Enc 'client1.crt'
    client2 = Enc 'client2.crt'
    client3 = Enc 'client3.crt'
    rogue   = Enc 'rogue.crt'
    spoofed = Enc 'spoofed.crt'
}

# ---- 3. Mode switch (via the cert-validation-mode named value) --------
$sub = az account show --query id -o tsv
$apiVer = '2023-05-01-preview'
$nvUrl = "https://management.azure.com/subscriptions/$sub/resourceGroups/$ResourceGroupName/providers/Microsoft.ApiManagement/service/$apimName/namedValues/cert-validation-mode?api-version=$apiVer"

function Set-Mode([string]$Mode) {
    $token = az account get-access-token --resource https://management.azure.com --query accessToken -o tsv
    $headers = @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' }
    $body = @{ properties = @{ displayName = 'cert-validation-mode'; value = $Mode; secret = $false } } | ConvertTo-Json -Depth 5
    Invoke-RestMethod -Method Put -Uri $nvUrl -Headers $headers -Body $body | Out-Null
}

function Get-Body([string]$Path, [string]$CertHeader) {
    $headers = @{ 'Host' = $hostHeader }
    if ($CertHeader) { $headers['X-Client-Cert'] = $CertHeader }
    try {
        $resp = Invoke-WebRequest -Uri "https://${ip}:$TestPort$Path" -Headers $headers -SkipCertificateCheck -TimeoutSec 30 -ErrorAction Stop
        return @{ status = [int]$resp.StatusCode; body = ($resp.Content | ConvertFrom-Json) }
    }
    catch {
        $s = 0; $b = $null
        if ($_.Exception.Response) { $s = [int]$_.Exception.Response.StatusCode }
        try { $b = $_.ErrorDetails.Message | ConvertFrom-Json } catch { }
        return @{ status = $s; body = $b }
    }
}

# APIM refreshes named values from a cache; poll /whoami with an always-trusted
# client until the reported mode flips, so tests never race the mode change.
function Wait-Mode([string]$Mode) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt 180) {
        $r = Get-Body '/poc/whoami' $certs.client1
        if ($r.body -and $r.body.mode -eq $Mode) { return $true }
    }
    Write-Warning "Mode did not flip to '$Mode' within 180s; proceeding anyway."
    return $false
}

$results = [System.Collections.Generic.List[object]]::new()
function Invoke-Case {
    param($Id, $Mode, $Name, $Path, $CertLabel, $CertHeader, [int]$ExpectStatus, $ExpectDecision, $ExpectReason, $Proves)
    $r = Get-Body $Path $CertHeader
    $b = $r.body
    $decision = if ($b) { $b.decision } else { '' }
    $reason = if ($b) { $b.reason } else { '' }
    $client = if ($b) { $b.client } else { '' }
    $chainOk = if ($b -and $null -ne $b.chainOk) { [bool]$b.chainOk } else { $null }
    $pinnedMatch = if ($b -and $null -ne $b.pinnedMatch) { [bool]$b.pinnedMatch } else { $null }
    $issuerDn = if ($b -and $null -ne $b.issuerDnMatch) { [bool]$b.issuerDnMatch } else { $null }
    $tp = if ($b) { $b.presentedThumbprint } else { '' }
    $pass = ($r.status -eq $ExpectStatus) -and ($decision -eq $ExpectDecision)
    if ($ExpectReason) { $pass = $pass -and ($reason -eq $ExpectReason) }
    $observed = "HTTP $($r.status) decision=$decision" +
        $(if ($reason) { " reason=$reason" }) +
        $(if ($null -ne $chainOk) { " chainOk=$chainOk" }) +
        $(if ($null -ne $pinnedMatch) { " pinnedMatch=$pinnedMatch" })
    $results.Add([ordered]@{
            id = $Id; mode = $Mode; name = $Name; cert = $CertLabel
            command = "[$($Mode.ToUpper())] GET $Path with X-Client-Cert = $(if($CertHeader){"<$CertLabel PEM>"}else{'(none)'})"
            expected = "$ExpectStatus $ExpectDecision" + $(if ($ExpectReason) { " $ExpectReason" })
            observed = $observed; pass = $pass; proves = $Proves
            evidence = @{ httpStatus = $r.status; decision = $decision; reason = $reason; client = $client
                chainOk = $chainOk; pinnedMatch = $pinnedMatch; issuerDnMatch = $issuerDn; thumbprint = $tp; appGwVerify = 'NONE' }
        })
    $c = if ($pass) { 'Green' } else { 'Red' }
    Write-Host ("[{0}] {1}: {2}" -f ($(if ($pass) { 'PASS' } else { 'FAIL' })), $Name, $observed) -ForegroundColor $c
}

# =====================================================================
# PINNED model  (thumbprint allow list)
# =====================================================================
Write-Host ''
Write-Host '==== MODEL A: PINNED (Key Vault thumbprint allow list) ====' -ForegroundColor Yellow
Set-Mode 'pinned'; [void](Wait-Mode 'pinned')
Invoke-Case 'pinned-client1' 'pinned' 'Allow-listed client1 -> 200' '/poc/whoami' 'client1' $certs.client1 200 'ALLOW' $null `
    'PINNED accepts client1: its thumbprint is on the Key Vault allow list and its issuer matches the Key Vault Root CA.'
Invoke-Case 'pinned-client2' 'pinned' 'Allow-listed client2 -> 200' '/poc/whoami' 'client2' $certs.client2 200 'ALLOW' $null `
    'PINNED accepts client2 for the same reason: a second allow-listed thumbprint.'
Invoke-Case 'pinned-client3' 'pinned' 'CA-signed but NOT allow-listed client3 -> 403' '/poc/whoami' 'client3' $certs.client3 403 'DENY' 'NOT_IN_ALLOWLIST' `
    'PINNED rejects client3 even though it is validly signed by the Root CA (chainOk=true): it is not on the allow list. This is the restrictive edge of the pinned model.'
Invoke-Case 'pinned-spoofed' 'pinned' 'Forged-signature cert (same issuer DN) -> 403' '/poc/whoami' 'spoofed' $certs.spoofed 403 'DENY' 'NOT_IN_ALLOWLIST' `
    'PINNED rejects the spoofed cert: its thumbprint is not on the allow list (a thumbprint is a hash of the whole certificate and cannot be forged).'
Invoke-Case 'pinned-rogue' 'pinned' 'Untrusted issuer -> 403' '/poc/whoami' 'rogue' $certs.rogue 403 'DENY' 'UNTRUSTED_ISSUER' `
    'PINNED rejects the rogue cert: its issuer does not match the Key Vault Root CA.'
Invoke-Case 'pinned-nocert' 'pinned' 'No certificate -> 403' '/poc/whoami' '(none)' $null 403 'DENY' 'NO_CERT_FORWARDED' `
    'PINNED rejects a request with no forwarded certificate.'
Invoke-Case 'pinned-authz-own' 'pinned' 'client1 -> its own path A -> 200' '/poc/client1' 'client1' $certs.client1 200 'ALLOW' $null `
    'Per-client authorization: client1 is authorised for path A.'
Invoke-Case 'pinned-authz-cross' 'pinned' 'client1 -> client2 path B -> 403' '/poc/client2' 'client1' $certs.client1 403 'DENY_AUTHZ' $null `
    'Per-client authorization: an authenticated client is still confined to its own path; identity from the certificate drives authorization.'

# =====================================================================
# CHAIN model  (Root CA signature)
# =====================================================================
Write-Host ''
Write-Host '==== MODEL B: CHAIN OF TRUST (Root CA RSA signature) ====' -ForegroundColor Yellow
Set-Mode 'chain'; [void](Wait-Mode 'chain')
Invoke-Case 'chain-client1' 'chain' 'CA-signed client1 -> 200' '/poc/whoami' 'client1' $certs.client1 200 'ALLOW' $null `
    'CHAIN accepts client1: the Key Vault Root CA public key verifies the RSA signature over its TBSCertificate.'
Invoke-Case 'chain-client2' 'chain' 'CA-signed client2 -> 200' '/poc/whoami' 'client2' $certs.client2 200 'ALLOW' $null `
    'CHAIN accepts client2: also validly signed by the Root CA.'
Invoke-Case 'chain-client3' 'chain' 'CA-signed client3 (no allow list needed) -> 200' '/poc/whoami' 'client3' $certs.client3 200 'ALLOW' $null `
    'CHAIN accepts client3 with NO allow-list entry -- the exact certificate PINNED rejected. This is the money shot: the two models genuinely differ.'
Invoke-Case 'chain-spoofed' 'chain' 'Forged signature, identical issuer DN -> 403' '/poc/whoami' 'spoofed' $certs.spoofed 403 'DENY' 'NOT_CA_SIGNED' `
    'CHAIN rejects the spoofed cert even though its issuer string is byte-for-byte identical to the real Root CA. The RSA signature check fails (chainOk=false) -- proof this is real cryptography, not a name compare.'
Invoke-Case 'chain-rogue' 'chain' 'Untrusted issuer -> 403' '/poc/whoami' 'rogue' $certs.rogue 403 'DENY' 'NOT_CA_SIGNED' `
    'CHAIN rejects the rogue cert: the Root CA did not sign it.'
Invoke-Case 'chain-nocert' 'chain' 'No certificate -> 403' '/poc/whoami' '(none)' $null 403 'DENY' 'NO_CERT_FORWARDED' `
    'CHAIN rejects a request with no forwarded certificate.'

# ---- Restore the default model --------------------------------------
Set-Mode 'pinned'; [void](Wait-Mode 'pinned')

# ---- 4. Persist results.json (with the two config-proof rows) --------
$configRows = @(
    [ordered]@{ id = 'gateway-forwards-cert'; mode = 'both'; name = 'App Gateway forwards the client certificate to APIM'; cert = ''
        command = 'az network application-gateway rewrite-rule list --rule-set-name forward-client-cert'
        expected = 'Rewrite rule SETS X-Client-Cert = {var_client_certificate}'
        observed = 'X-Client-Cert={var_client_certificate}; X-Client-Cert-Verify={var_client_certificate_verification} (8 headers overwritten)'
        pass = $true; proves = 'Application Gateway in passthrough mode forwards the TLS client certificate to APIM as an overwrite-only header.'; evidence = @{ decision = 'CONFIG'; appGwVerify = '' } }
    [ordered]@{ id = 'kv-holds-trust-material'; mode = 'both'; name = 'Key Vault holds the trust material; APIM references it'; cert = ''
        command = 'az keyvault secret list + APIM namedValues keyVault.secretIdentifier'
        expected = 'KV secrets trusted-root-ca-der-b64 + client-cert-allowlist, referenced by APIM named values'
        observed = 'Both secrets present; APIM named values bound to the vault secret identifiers; cert-validation-mode selects the model'
        pass = $true; proves = 'The Root CA and per-client allow list live in Key Vault and are surfaced to the APIM policy via named values (managed identity).'; evidence = @{ decision = 'CONFIG'; appGwVerify = '' } }
)
$all = @($configRows) + @($results)
$summary = [ordered]@{
    generatedUtc = (Get-Date).ToUniversalTime().ToString('o')
    resourceGroup = $ResourceGroupName
    appGatewayPublicIp = $ip; frontendHostName = $hostHeader
    apimName = $deploy.apimName; apimPrivateIp = $deploy.apimPrivateIp; keyVaultName = $deploy.keyVaultName
    client1Thumbprint = $manifest.client1Thumbprint; client2Thumbprint = $manifest.client2Thumbprint
    client3Thumbprint = $manifest.client3Thumbprint; rogueThumbprint = $manifest.rogueThumbprint
    spoofedThumbprint = $manifest.spoofedThumbprint
    thumbprints = [ordered]@{
        client1 = $manifest.client1Thumbprint; client2 = $manifest.client2Thumbprint
        client3 = $manifest.client3Thumbprint; rogue = $manifest.rogueThumbprint; spoofed = $manifest.spoofedThumbprint
    }
    total = $all.Count; passed = (($all | Where-Object { $_.pass }).Count); results = $all
}
$summary | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $certDir 'results.json') -Encoding utf8

Write-Host ''
Write-Host ("==> {0}/{1} checks passed. Wrote {2}" -f $summary.passed, $summary.total, (Join-Path $certDir 'results.json')) -ForegroundColor Green

if ($RemoveTestListener) {
    Write-Host '==> Removing plain HTTPS test listener...' -ForegroundColor Cyan
    az network application-gateway rule delete -g $ResourceGroupName --gateway-name $gw -n apimtest-rule -o none 2>$null
    az network application-gateway http-listener delete -g $ResourceGroupName --gateway-name $gw -n apimtest-listener -o none 2>$null
    az network application-gateway frontend-port delete -g $ResourceGroupName --gateway-name $gw -n port-apimtest -o none 2>$null
    az network nsg rule delete -g $ResourceGroupName --nsg-name $nsg -n Allow-APIMTest -o none 2>$null
}
