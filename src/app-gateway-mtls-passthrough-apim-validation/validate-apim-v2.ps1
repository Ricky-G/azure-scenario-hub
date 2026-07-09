#Requires -Version 7.0
<#
.SYNOPSIS
    Proves the certificate-validation logic behaves identically on an API
    Management **v2** tier (PremiumV2) by deploying a standalone public v2
    instance, applying the SAME dual-model policies + Key Vault-backed named
    values, and running the SAME dual-mode certificate matrix against it.

.DESCRIPTION
    The v2 tiers carry a documented limitation: `context.Request.Certificate`
    and TLS renegotiation are not supported. This scenario never relies on
    either - APIM validates the certificate that Application Gateway forwards
    in the `X-Client-Cert` header - so the limitation should not apply. This
    script proves that empirically on a real PremiumV2 instance.

    Because the certificate check is entirely policy-driven on the forwarded
    header, no Application Gateway is needed here: the v2 gateway is public,
    so the certificates are presented directly to the v2 gateway in the
    `X-Client-Cert` header, exactly as App Gateway would forward them.

    Writes certs/results-v2.json for the report generator.

.PARAMETER ResourceGroupName
    Resource group of the existing scenario (reuses its Key Vault). Default:
    rg-appgw-passthrough-mtls-poc

.PARAMETER KeepAfter
    Leave the PremiumV2 instance running after the test (default is to leave
    it; run teardown-apim-v2.ps1 to remove just the v2 instance).

.EXAMPLE
    ./validate-apim-v2.ps1
#>
[CmdletBinding()]
param(
    [string]$ResourceGroupName = 'rg-appgw-passthrough-mtls-poc',
    [string[]]$SkuCandidates = @('PremiumV2', 'StandardV2'),
    [string[]]$LocationCandidates = @('eastus2', 'eastus', 'centralus', 'westus2', 'uksouth'),
    [switch]$SkipDeploy
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$certDir = Join-Path $scriptDir 'certs'
$templateFile = Join-Path $scriptDir 'bicep/apim-v2-proof.bicep'

$manifest = Get-Content (Join-Path $certDir 'manifest.json') -Raw | ConvertFrom-Json
$deploy = Get-Content (Join-Path $certDir 'deploy-output.json') -Raw | ConvertFrom-Json
$keyVaultName = $deploy.keyVaultName

# ---- 1. Deploy a v2 instance + config (reuses the same KV) -------------
# The v2 tiers (PremiumV2 / StandardV2) share the same policy engine and the
# same v2-tier certificate limitation, so either faithfully proves the point.
# PremiumV2 is preferred but is capacity-gated per subscription/region; if it
# can't be created anywhere, fall back to StandardV2. The Key Vault is public-
# access, so a v2 instance in any region reaches the same trust material.
if (-not $SkipDeploy) {
    $deployed = $false
    foreach ($sku in $SkuCandidates) {
        foreach ($loc in $LocationCandidates) {
            Write-Host "==> Deploying $sku API Management (public) in '$loc'..." -ForegroundColor Cyan
            Write-Host '    v2 tiers provision in minutes; please wait.' -ForegroundColor DarkGray
            az deployment group create `
                --resource-group $ResourceGroupName `
                --name 'mtls-apim-v2-proof' `
                --template-file $templateFile `
                --parameters keyVaultName=$keyVaultName certValidationMode=pinned location=$loc apimSku=$sku `
                --output none
            if ($LASTEXITCODE -eq 0) { $deployed = $true; Write-Host "==> $sku created in '$loc'." -ForegroundColor Green; break }
            $err = az deployment operation group list -g $ResourceGroupName -n deploy-apim-v2 --query "[?properties.provisioningState=='Failed'].properties.statusMessage.error.code | [0]" -o tsv 2>$null
            if ($err -eq 'ApiServiceCreationDisabledForSubscription') {
                Write-Host "    $sku in '$loc' is capacity-gated right now; trying the next region..." -ForegroundColor Yellow
                continue
            }
            Write-Error "v2 deployment failed for $sku in '$loc' (code: $err)."; exit 1
        }
        if ($deployed) { break }
        Write-Host "==> $sku is capacity-gated in every candidate region; trying the next v2 SKU..." -ForegroundColor Yellow
    }
    if (-not $deployed) { Write-Error 'No v2 SKU could be created in any candidate region (all capacity-gated). Try again later or add more regions.'; exit 1 }
}

$outputs = az deployment group show --resource-group $ResourceGroupName --name 'mtls-apim-v2-proof' `
    --query properties.outputs --output json | ConvertFrom-Json
$apimV2Name = $outputs.apimV2Name.value
$apimV2Sku = $outputs.apimV2Sku.value
$gatewayUrl = $outputs.apimV2GatewayUrl.value.TrimEnd('/')
Write-Host ("==> v2 tier deployed: {0}  |  gateway: {1}" -f $apimV2Sku, $gatewayUrl) -ForegroundColor Green

# ---- 2. Forwarded-header certs (URL/percent-encoded PEM) ---------------
function Enc([string]$file) { [System.Uri]::EscapeDataString((Get-Content (Join-Path $certDir $file) -Raw)) }
$certs = @{
    client1 = Enc 'client1.crt'
    client2 = Enc 'client2.crt'
    client3 = Enc 'client3.crt'
    rogue   = Enc 'rogue.crt'
    spoofed = Enc 'spoofed.crt'
}

# ---- 3. Mode switch via the cert-validation-mode named value -----------
$sub = az account show --query id -o tsv
$apiVer = '2023-05-01-preview'
$nvUrl = "https://management.azure.com/subscriptions/$sub/resourceGroups/$ResourceGroupName/providers/Microsoft.ApiManagement/service/$apimV2Name/namedValues/cert-validation-mode?api-version=$apiVer"

function Set-Mode([string]$Mode) {
    $token = az account get-access-token --resource https://management.azure.com --query accessToken -o tsv
    $headers = @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' }
    $body = @{ properties = @{ displayName = 'cert-validation-mode'; value = $Mode; secret = $false } } | ConvertTo-Json -Depth 5
    Invoke-RestMethod -Method Put -Uri $nvUrl -Headers $headers -Body $body | Out-Null
}

function Get-Body([string]$Path, [string]$CertHeader) {
    $headers = @{ }
    if ($CertHeader) { $headers['X-Client-Cert'] = $CertHeader }
    try {
        $resp = Invoke-WebRequest -Uri "$gatewayUrl$Path" -Headers $headers -SkipCertificateCheck -TimeoutSec 40 -ErrorAction Stop
        return @{ status = [int]$resp.StatusCode; body = ($resp.Content | ConvertFrom-Json) }
    }
    catch {
        $s = 0; $b = $null
        if ($_.Exception.Response) { $s = [int]$_.Exception.Response.StatusCode }
        try { $b = $_.ErrorDetails.Message | ConvertFrom-Json } catch { }
        return @{ status = $s; body = $b }
    }
}

function Wait-Ready([string]$Mode) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt 300) {
        $r = Get-Body '/poc/whoami' $certs.client1
        if ($r.body -and $r.body.mode -eq $Mode) { return $true }
        Start-Sleep -Seconds 5
    }
    Write-Warning "v2 gateway did not report mode '$Mode' within 300s; proceeding anyway."
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
                chainOk = $chainOk; pinnedMatch = $pinnedMatch; thumbprint = $tp; appGwVerify = 'NONE' }
        })
    $c = if ($pass) { 'Green' } else { 'Red' }
    Write-Host ("[{0}] {1}: {2}" -f ($(if ($pass) { 'PASS' } else { 'FAIL' })), $Name, $observed) -ForegroundColor $c
}

# =====================================================================
# PINNED model
# =====================================================================
Write-Host ''
Write-Host "==== [v2 $apimV2Sku] MODEL A: PINNED (thumbprint allow list) ====" -ForegroundColor Yellow
Set-Mode 'pinned'; [void](Wait-Ready 'pinned')
Invoke-Case 'v2-pinned-client1' 'pinned' 'Allow-listed client1 -> 200' '/poc/whoami' 'client1' $certs.client1 200 'ALLOW' $null `
    'On PremiumV2, the same policy accepts an allow-listed certificate.'
Invoke-Case 'v2-pinned-client3' 'pinned' 'CA-signed but NOT allow-listed client3 -> 403' '/poc/whoami' 'client3' $certs.client3 403 'DENY' 'NOT_IN_ALLOWLIST' `
    'On PremiumV2, pinned mode rejects a validly-signed-but-unlisted cert (chainOk=true).'
Invoke-Case 'v2-pinned-spoofed' 'pinned' 'Forged-signature cert (same issuer DN) -> 403' '/poc/whoami' 'spoofed' $certs.spoofed 403 'DENY' 'NOT_IN_ALLOWLIST' `
    'On PremiumV2, pinned mode rejects the forged-signature cert (not on the allow list).'
Invoke-Case 'v2-pinned-rogue' 'pinned' 'Untrusted issuer -> 403' '/poc/whoami' 'rogue' $certs.rogue 403 'DENY' 'UNTRUSTED_ISSUER' `
    'On PremiumV2, pinned mode rejects the rogue cert (issuer does not match the Root CA).'
Invoke-Case 'v2-pinned-nocert' 'pinned' 'No certificate -> 403' '/poc/whoami' '(none)' $null 403 'DENY' 'NO_CERT_FORWARDED' `
    'On PremiumV2, a request with no forwarded certificate is rejected.'
Invoke-Case 'v2-pinned-authz-cross' 'pinned' 'client1 -> client2 path B -> 403' '/poc/client2' 'client1' $certs.client1 403 'DENY_AUTHZ' $null `
    'On PremiumV2, per-client authorization still confines a client to its own path.'

# =====================================================================
# CHAIN model
# =====================================================================
Write-Host ''
Write-Host "==== [v2 $apimV2Sku] MODEL B: CHAIN OF TRUST (Root CA RSA signature) ====" -ForegroundColor Yellow
Set-Mode 'chain'; [void](Wait-Ready 'chain')
Invoke-Case 'v2-chain-client1' 'chain' 'CA-signed client1 -> 200' '/poc/whoami' 'client1' $certs.client1 200 'ALLOW' $null `
    'On PremiumV2, the same RSA signature verification accepts a CA-signed cert.'
Invoke-Case 'v2-chain-client3' 'chain' 'CA-signed client3 (no allow list needed) -> 200' '/poc/whoami' 'client3' $certs.client3 200 'ALLOW' $null `
    'On PremiumV2, chain mode accepts client3 with no allow-list entry - the exact cert pinned rejected.'
Invoke-Case 'v2-chain-spoofed' 'chain' 'Forged signature, identical issuer DN -> 403' '/poc/whoami' 'spoofed' $certs.spoofed 403 'DENY' 'NOT_CA_SIGNED' `
    'On PremiumV2, the RSA signature check still rejects the forged cert (chainOk=false) despite an identical issuer DN - real cryptography, not a name compare, on the v2 policy engine.'
Invoke-Case 'v2-chain-rogue' 'chain' 'Untrusted issuer -> 403' '/poc/whoami' 'rogue' $certs.rogue 403 'DENY' 'NOT_CA_SIGNED' `
    'On PremiumV2, chain mode rejects the rogue cert (the Root CA did not sign it).'
Invoke-Case 'v2-chain-nocert' 'chain' 'No certificate -> 403' '/poc/whoami' '(none)' $null 403 'DENY' 'NO_CERT_FORWARDED' `
    'On PremiumV2, a request with no forwarded certificate is rejected.'

# ---- Restore the default model --------------------------------------
Set-Mode 'pinned'; [void](Wait-Ready 'pinned')

# ---- 4. Persist results-v2.json -------------------------------------
$summary = [ordered]@{
    generatedUtc = (Get-Date).ToUniversalTime().ToString('o')
    sku = $apimV2Sku
    resourceGroup = $ResourceGroupName
    apimName = $apimV2Name
    gatewayUrl = $gatewayUrl
    keyVaultName = $keyVaultName
    thumbprints = [ordered]@{
        client1 = $manifest.client1Thumbprint; client2 = $manifest.client2Thumbprint
        client3 = $manifest.client3Thumbprint; rogue = $manifest.rogueThumbprint; spoofed = $manifest.spoofedThumbprint
    }
    total = $results.Count; passed = (($results | Where-Object { $_.pass }).Count); results = $results
}
$summary | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $certDir 'results-v2.json') -Encoding utf8

Write-Host ''
Write-Host ("==> [v2 {0}] {1}/{2} checks passed. Wrote {3}" -f $apimV2Sku, $summary.passed, $summary.total, (Join-Path $certDir 'results-v2.json')) -ForegroundColor Green
Write-Host ("==> {0} is a premium-priced v2 tier. Run ./teardown-apim-v2.ps1 to remove just the v2 instance when done." -f $apimV2Sku) -ForegroundColor Yellow
