#Requires -Version 7.0
<#
.SYNOPSIS
    Runs the end-to-end evidence suite for the mTLS passthrough POC and
    writes certs/results.json (consumed by RESULTS.md and the HTML report).

.DESCRIPTION
    Drives every scenario the POC must prove using OpenSSL s_client as the
    mTLS client (Windows' built-in curl uses Schannel, which cannot present
    PEM client certificates). For each scenario it records the exact command,
    the observed HTTP status, the APIM decision/reason, the App Gateway
    client_certificate_verification value, and a PASS/FAIL verdict.

.PARAMETER ResourceGroupName
    Resource group of the deployment. Default: rg-appgw-passthrough-mtls-poc
#>
[CmdletBinding()]
param(
    [string]$ResourceGroupName = 'rg-appgw-passthrough-mtls-poc'
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$certDir = Join-Path $scriptDir 'certs'
$deployOutPath = Join-Path $certDir 'deploy-output.json'
$manifestPath = Join-Path $certDir 'manifest.json'

if (-not (Test-Path $deployOutPath)) { throw "deploy-output.json not found. Run ./deploy-infra.ps1 first." }
$deploy = Get-Content $deployOutPath -Raw | ConvertFrom-Json
$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json

# ---- Locate OpenSSL --------------------------------------------------
$script:OpenSSL = (Get-Command openssl -ErrorAction SilentlyContinue).Source
if (-not $script:OpenSSL) {
    $script:OpenSSL = @(
        'C:\Program Files\Git\usr\bin\openssl.exe',
        'C:\Program Files\Git\mingw64\bin\openssl.exe'
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $script:OpenSSL) { throw 'OpenSSL not found.' }

$script:ServerCa = Join-Path $certDir 'appgw-server.crt'
$ip = $deploy.appGatewayPublicIp
$fqdnHost = $deploy.frontendHostName
$apimHost = "$($deploy.apimName).azure-api.net"

Write-Host "==> Target App Gateway : $ip (SNI $fqdnHost)" -ForegroundColor Cyan
Write-Host "==> APIM (internal)    : $apimHost @ $($deploy.apimPrivateIp)" -ForegroundColor Cyan

# ---- mTLS client helper (OpenSSL s_client via .NET Process) ----------
function Invoke-Mtls {
    param(
        [string]$Path,
        [string[]]$CertArgs = @(),
        [hashtable]$InjectHeaders = @{}
    )
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append("GET $Path HTTP/1.1`r`n")
    [void]$sb.Append("Host: $fqdnHost`r`n")
    foreach ($k in $InjectHeaders.Keys) { [void]$sb.Append("${k}: $($InjectHeaders[$k])`r`n") }
    [void]$sb.Append("Connection: close`r`n`r`n")
    $req = $sb.ToString()

    $sslArgs = @('s_client', '-connect', "${ip}:443", '-servername', $fqdnHost, '-CAfile', $script:ServerCa, '-quiet') + $CertArgs

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $script:OpenSSL
    foreach ($a in $sslArgs) { $psi.ArgumentList.Add($a) }
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false

    $p = [System.Diagnostics.Process]::Start($psi)
    $errTask = $p.StandardError.ReadToEndAsync()
    try {
        $p.StandardInput.Write($req)
        $p.StandardInput.Flush()
        $p.StandardInput.Close()
    }
    catch { }
    $out = $p.StandardOutput.ReadToEnd()
    if (-not $p.WaitForExit(25000)) { try { $p.Kill() } catch { } }
    $err = $errTask.GetAwaiter().GetResult()

    $result = [ordered]@{
        status      = $null
        statusLine  = $null
        headers     = @{}
        body        = ''
        handshakeOk = $false
        stderr      = ($err | Out-String)
        stdoutRaw   = $out
    }
    $idx = $out.IndexOf('HTTP/1.')
    if ($idx -ge 0) {
        $result.handshakeOk = $true
        $httpText = $out.Substring($idx)
        $parts = $httpText -split "`r`n`r`n", 2
        $headerBlock = $parts[0]
        if ($parts.Count -gt 1) { $result.body = $parts[1].Trim() }
        $lines = $headerBlock -split "`r`n"
        $result.statusLine = $lines[0]
        $tokens = $lines[0] -split '\s+'
        if ($tokens.Count -ge 2) { $result.status = [int]$tokens[1] }
        foreach ($l in ($lines | Select-Object -Skip 1)) {
            $ci = $l.IndexOf(':')
            if ($ci -gt 0) { $result.headers[$l.Substring(0, $ci).Trim()] = $l.Substring($ci + 1).Trim() }
        }
    }
    return [pscustomobject]$result
}

function Get-Evidence {
    param($Response, [string]$Key)
    if ($Response.headers.ContainsKey($Key)) { return $Response.headers[$Key] }
    return ''
}

$c1 = @('-cert', (Join-Path $certDir 'client1.crt'), '-key', (Join-Path $certDir 'client1.key'))
$c2 = @('-cert', (Join-Path $certDir 'client2.crt'), '-key', (Join-Path $certDir 'client2.key'))
$rogue = @('-cert', (Join-Path $certDir 'rogue.crt'), '-key', (Join-Path $certDir 'rogue.key'))
$mismatch = @('-cert', (Join-Path $certDir 'client1.crt'), '-key', (Join-Path $certDir 'client2.key'))

$client1Pem = Get-Content (Join-Path $certDir 'client1.crt') -Raw
$roguePem = Get-Content (Join-Path $certDir 'rogue.crt') -Raw
$client1PemEnc = [System.Uri]::EscapeDataString($client1Pem)
$roguePemEnc = [System.Uri]::EscapeDataString($roguePem)

$results = [System.Collections.Generic.List[object]]::new()
function Add-Result {
    param($Id, $Name, $Command, $Expected, $Observed, [bool]$Pass, $Proves, $Response = $null)
    $ev = @{}
    if ($Response) {
        $ev = @{
            httpStatus = $Response.status
            decision   = (Get-Evidence $Response 'X-Evidence-Decision')
            client     = (Get-Evidence $Response 'X-Evidence-Client')
            appGwVerify = (Get-Evidence $Response 'X-Evidence-AppGw-Verify')
            chain      = (Get-Evidence $Response 'X-Evidence-Chain')
            thumbprint = (Get-Evidence $Response 'X-Evidence-Cert-Thumbprint')
            body       = $Response.body
        }
    }
    $results.Add([ordered]@{
            id = $Id; name = $Name; command = $Command; expected = $Expected
            observed = $Observed; pass = $Pass; proves = $Proves; evidence = $ev
        })
    $color = if ($Pass) { 'Green' } else { 'Red' }
    Write-Host ("[{0}] {1} -> {2}" -f ($(if ($Pass) { 'PASS' } else { 'FAIL' })), $Id, $Observed) -ForegroundColor $color
}

Write-Host "`n==================== EVIDENCE SUITE ====================`n" -ForegroundColor Yellow

# --- 0. Connectivity pre-check (APIM reachable via App Gateway) -------
$r = Invoke-Mtls -Path '/status-0123456789abcdef'
Add-Result '0-connectivity' 'App Gateway -> APIM connectivity (no cert, APIM status endpoint)' `
    "openssl s_client -connect ${ip}:443 -servername $fqdnHost  (GET /status-0123456789abcdef)" `
    '200 from APIM status endpoint' `
    ("HTTP {0}" -f $r.status) ($r.status -eq 200) `
    'Confirms passthrough allows the connection and App Gateway routes to internal APIM.' $r

# --- 1. POSSESSION (positive): client1 owns cert1 + key1 --------------
$r = Invoke-Mtls -Path '/poc/client1' -CertArgs $c1
$dec = Get-Evidence $r 'X-Evidence-Decision'
Add-Result '1-possession-positive' 'Possession positive: client OWNS cert1 (cert+key)' `
    "openssl s_client ... -cert client1.crt -key client1.key  (GET /poc/client1)" `
    '200 ALLOW (handshake completes, cert forwarded, APIM validates)' `
    ("HTTP {0} {1} appGwVerify={2}" -f $r.status, $dec, (Get-Evidence $r 'X-Evidence-AppGw-Verify')) `
    ($r.status -eq 200 -and $dec -eq 'ALLOW') `
    'A client that possesses the private key completes mTLS; the cert is forwarded and validated by APIM.' $r

# --- 1b. POSSESSION (negative): cert1 with the WRONG key --------------
$r = Invoke-Mtls -Path '/poc/client1' -CertArgs $mismatch
$mismatchDetected = ($r.stderr -match 'key values mismatch' -or $r.stderr -match 'key values' -or -not $r.handshakeOk)
Add-Result '1b-possession-negative' 'Possession negative: present cert1 WITHOUT its private key (cert1 + key2)' `
    "openssl s_client ... -cert client1.crt -key client2.key  (GET /poc/client1)" `
    'Client cannot present cert1 without key1; no valid cert reaches APIM' `
    ("handshakeOk={0}; stderr~='{1}'" -f $r.handshakeOk, (($r.stderr -split "`n" | Where-Object { $_ -match 'mismatch|error' } | Select-Object -First 1))) `
    ([bool]$mismatchDetected) `
    'Proof-of-possession is enforced by TLS: a certificate cannot be presented without the matching private key.' $r

# --- 2. POSITIVE per-client: client2 owns cert2 -> path B -------------
$r = Invoke-Mtls -Path '/poc/client2' -CertArgs $c2
$dec = Get-Evidence $r 'X-Evidence-Decision'
Add-Result '2-positive-client2' 'Positive: client2 (owns cert2) -> path B' `
    "openssl s_client ... -cert client2.crt -key client2.key  (GET /poc/client2)" `
    '200 ALLOW client2' `
    ("HTTP {0} {1} client={2}" -f $r.status, $dec, (Get-Evidence $r 'X-Evidence-Client')) `
    ($r.status -eq 200 -and $dec -eq 'ALLOW') `
    'Second legacy client, its own cert, its own path: allowed.' $r

# --- 3. PER-CLIENT AUTHZ: client1 -> path B (client2's path) ---------
$r = Invoke-Mtls -Path '/poc/client2' -CertArgs $c1
$dec = Get-Evidence $r 'X-Evidence-Decision'
Add-Result '3-authz-cross' 'Per-client authz: client1 cert -> client2 path B' `
    "openssl s_client ... -cert client1.crt -key client1.key  (GET /poc/client2)" `
    '403 DENY_AUTHZ' `
    ("HTTP {0} {1}" -f $r.status, $dec) `
    ($r.status -eq 403 -and $dec -eq 'DENY_AUTHZ') `
    'A trusted client is still rejected from another client''s path: per-client authorization holds.' $r

# --- 4. TRUST at APIM: rogue OWNS a valid cert from UNtrusted issuer --
$r = Invoke-Mtls -Path '/poc/client1' -CertArgs $rogue
$dec = Get-Evidence $r 'X-Evidence-Decision'
Add-Result '4-trust-rogue' 'Trust enforced at APIM: rogue owns cert from UNtrusted issuer (not allow-listed)' `
    "openssl s_client ... -cert rogue.crt -key rogue.key  (GET /poc/client1)" `
    '403 DENY (passthrough forwards it; APIM rejects)' `
    ("HTTP {0} {1} appGwVerify={2}" -f $r.status, $dec, (Get-Evidence $r 'X-Evidence-AppGw-Verify')) `
    ($r.status -eq 403 -and $dec -eq 'DENY') `
    'The gateway forwards the rogue cert regardless; APIM is the trust anchor and rejects it.' $r

# --- 5. NO CERT: passthrough allows connection, APIM rejects ----------
$r = Invoke-Mtls -Path '/poc/client1'
$dec = Get-Evidence $r 'X-Evidence-Decision'
Add-Result '5-no-cert' 'No certificate presented' `
    "openssl s_client ... (no -cert)  (GET /poc/client1)" `
    '403 DENY (NO_CERT_FORWARDED)' `
    ("HTTP {0} {1} appGwVerify={2}" -f $r.status, $dec, (Get-Evidence $r 'X-Evidence-AppGw-Verify')) `
    ($r.status -eq 403 -and $dec -eq 'DENY') `
    'Passthrough completes the connection with no cert; APIM sees none and rejects.' $r

# --- 6b-i. HEADER INJECTION (no cert + forged X-Client-Cert header) ---
$r = Invoke-Mtls -Path '/poc/client1' -InjectHeaders @{
    'X-Client-Cert'        = $client1PemEnc
    'X-Client-Cert-Verify' = 'SUCCESS'
}
$dec = Get-Evidence $r 'X-Evidence-Decision'
Add-Result '6b-inject-nocert' 'Header injection: no TLS cert, forge X-Client-Cert + X-Client-Cert-Verify=SUCCESS' `
    "openssl s_client ... (no -cert) with -H 'X-Client-Cert: <client1 PEM>' -H 'X-Client-Cert-Verify: SUCCESS'" `
    '403 DENY (rewrite overwrites forged headers with empty TLS value)' `
    ("HTTP {0} {1} appGwVerify={2}" -f $r.status, $dec, (Get-Evidence $r 'X-Evidence-AppGw-Verify')) `
    ($r.status -eq 403 -and $dec -eq 'DENY' -and (Get-Evidence $r 'X-Evidence-AppGw-Verify') -ne 'SUCCESS') `
    'App Gateway SETS the cert headers from TLS server variables, discarding the client-supplied (forged) values.' $r

# --- 6b-ii. HEADER INJECTION (valid client1 + forged rogue header) ---
$r = Invoke-Mtls -Path '/poc/client1' -CertArgs $c1 -InjectHeaders @{
    'X-Client-Cert' = $roguePemEnc
}
$dec = Get-Evidence $r 'X-Evidence-Decision'
Add-Result '6b-inject-override' 'Header injection: valid client1 cert, forge X-Client-Cert=<rogue PEM>' `
    "openssl s_client ... -cert client1.crt -key client1.key with -H 'X-Client-Cert: <rogue PEM>'" `
    '200 ALLOW client1 (real TLS cert wins, forged header discarded)' `
    ("HTTP {0} {1} client={2}" -f $r.status, $dec, (Get-Evidence $r 'X-Evidence-Client')) `
    ($r.status -eq 200 -and (Get-Evidence $r 'X-Evidence-Client') -eq 'client1') `
    'The forged header is overwritten by the real TLS-derived certificate; identity cannot be swapped via headers.' $r

# --- 6a. DIRECT-TO-APIM bypass attempt (network lockdown) ------------
Write-Host '==> Testing direct-to-APIM bypass (expect connection failure)...' -ForegroundColor Cyan
$directOk = $false
$directMsg = ''
try {
    $curlOut = & curl.exe -sS -o NUL -w '%{http_code}' --max-time 15 `
        -H "X-Client-Cert: FORGED" -H "X-Client-Cert-Verify: SUCCESS" `
        "https://$apimHost/poc/client1" 2>&1
    $directMsg = "curl exit=$LASTEXITCODE output=$curlOut"
    # Success of the LOCKDOWN means the bypass did NOT reach a working gateway.
    $directOk = ($LASTEXITCODE -ne 0) -or ($curlOut -notmatch '^200')
}
catch {
    $directMsg = "curl error: $($_.Exception.Message)"
    $directOk = $true
}
Add-Result '6a-direct-bypass' 'Spoof bypass: reach APIM directly (skip App Gateway) with forged header' `
    "curl https://$apimHost/poc/client1 -H 'X-Client-Cert: FORGED' -H 'X-Client-Cert-Verify: SUCCESS'" `
    'Blocked - APIM is Internal VNet only, not reachable from the internet' `
    $directMsg $directOk `
    'Network lockdown: the forged request never reaches APIM because the gateway is private.'

# --- 7. WAF retained -------------------------------------------------
Write-Host '==> Checking WAF policy state...' -ForegroundColor Cyan
$wafState = az network application-gateway waf-policy list -g $ResourceGroupName `
    --query "[0].{state:policySettings.state, mode:policySettings.mode, ruleset:managedRules.managedRuleSets[0].ruleSetVersion}" -o json 2>$null | ConvertFrom-Json
$wafOk = ($wafState.state -eq 'Enabled' -and $wafState.mode -eq 'Prevention')
Add-Result '7-waf-retained' 'WAF_v2 retained (OWASP, Prevention)' `
    "az network application-gateway waf-policy list -g $ResourceGroupName" `
    'WAF Enabled + Prevention' `
    ("state={0} mode={1} ruleset={2}" -f $wafState.state, $wafState.mode, $wafState.ruleset) `
    $wafOk 'The Azure WAF remains enabled in Prevention mode throughout.'

# ---- Persist + summarise --------------------------------------------
$summary = [ordered]@{
    generatedUtc     = (Get-Date).ToUniversalTime().ToString('o')
    resourceGroup    = $ResourceGroupName
    appGatewayPublicIp = $ip
    frontendHostName = $fqdnHost
    apimName         = $deploy.apimName
    apimPrivateIp    = $deploy.apimPrivateIp
    client1Thumbprint = $manifest.client1Thumbprint
    client2Thumbprint = $manifest.client2Thumbprint
    rogueThumbprint  = $manifest.rogueThumbprint
    total            = $results.Count
    passed           = (($results | Where-Object { $_.pass }).Count)
    results          = $results
}
$summary | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $certDir 'results.json') -Encoding utf8

Write-Host ''
Write-Host ("==> {0}/{1} scenarios passed. Results: {2}" -f $summary.passed, $summary.total, (Join-Path $certDir 'results.json')) `
    -ForegroundColor $(if ($summary.passed -eq $summary.total) { 'Green' } else { 'Yellow' })
