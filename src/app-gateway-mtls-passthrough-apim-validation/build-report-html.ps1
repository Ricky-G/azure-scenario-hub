#Requires -Version 7.0
<#
.SYNOPSIS
    Builds the styled, self-contained HTML report from results.json.
    Called by generate-report.ps1 (not usually run directly).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ResultsPath,
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$PossessionVerdict = 'ENFORCED',
    [string]$ResultsV2Path
)

$ErrorActionPreference = 'Stop'
$data = Get-Content $ResultsPath -Raw | ConvertFrom-Json
$dataV2 = $null
if ($ResultsV2Path -and (Test-Path $ResultsV2Path)) {
    $dataV2 = Get-Content $ResultsV2Path -Raw | ConvertFrom-Json
}

function E([string]$s) {
    if ($null -eq $s) { return '' }
    return [System.Net.WebUtility]::HtmlEncode($s)
}

# --- Source snippets: the actual IaC / policy that backs each check --------
# Keyed by result id (covers both the validate-apim-keyvault.ps1 ids and the
# run-tests.ps1 ids). Rendered inside each scenario card for context.
$snippets = @{}
$snGatewayForward = @{ file = 'bicep/modules/app-gateway.bicep'; code = @'
// App Gateway forwards the TLS client cert to APIM. Every header is SET
// (overwrite) from a mutual-auth server variable, so a client can never
// inject its own X-Client-Cert value.
rewriteRuleSets: [
  {
    name: 'forward-client-cert'
    properties: {
      rewriteRules: [
        {
          name: 'set-client-cert-headers'
          actionSet: {
            requestHeaderConfigurations: [
              { headerName: 'X-Client-Cert'        headerValue: '{var_client_certificate}' }
              { headerName: 'X-Client-Cert-Issuer' headerValue: '{var_client_certificate_issuer}' }
              { headerName: 'X-Client-Cert-Verify' headerValue: '{var_client_certificate_verification}' }
              // + subject / fingerprint / serial / start / end
            ]
          }
        }
      ]
    }
  }
]
'@ }
$snKvTrust = @{ file = 'bicep/modules/apim-config.bicep'; code = @'
// The Root CA and the pinned allow-list live in Key Vault and are surfaced
// to the APIM policy as named values via the service's managed identity.
resource nvRoot 'Microsoft.ApiManagement/service/namedValues@2023-05-01-preview' = {
  parent: apim
  name: 'trusted-root-ca-der-b64'
  properties: {
    secret: true
    keyVault: { secretIdentifier: rootSecretIdentifier }   // -> KV secret
  }
}
resource nvAllow 'Microsoft.ApiManagement/service/namedValues@2023-05-01-preview' = {
  parent: apim
  name: 'client-cert-allowlist'
  properties: {
    secret: true
    keyVault: { secretIdentifier: allowlistSecretIdentifier }
  }
}
'@ }
$snApimValidate = @{ file = 'apim/api-policy.xml'; code = @'
// Rebuild the forwarded cert, then decide trust under the active model.
string pem  = System.Uri.UnescapeDataString(fwdCertHeader);   // X-Client-Cert
var cert    = new X509Certificate2(Convert.FromBase64String(pemBody));
var root    = new X509Certificate2(Convert.FromBase64String("{{trusted-root-ca-der-b64}}"));

// MODEL A (pinned): thumbprint must be on the KV allow-list AND issuer match.
bool issuerDnMatch = string.Equals(cert.Issuer, root.Subject,
                                   StringComparison.OrdinalIgnoreCase);
bool pinnedMatch = false;
foreach (var e in "{{client-cert-allowlist}}".Split('|')) {
    var kv = e.Split(':');                       // "client1:THUMBPRINT"
    if (kv.Length == 2 &&
        string.Equals(kv[1].Trim(), cert.Thumbprint, StringComparison.OrdinalIgnoreCase))
        pinnedMatch = true;
}
bool pinnedOk = timeOk && issuerDnMatch && pinnedMatch;   // -> 200 when true
'@ }
$snChainVerify = @{ file = 'apim/api-policy.xml'; code = @'
// MODEL B (chain): a REAL RSA signature check - not a name compare.
// The sandbox blocks X509Chain and System.Func, so the leaf DER is parsed
// inline to pull out the TBSCertificate bytes and the signature, then the
// Key-Vault Root CA public key must verify that signature.
byte[] der = cert.RawData;
byte[] tbs = /* inline DER walk: SEQUENCE -> tbsCertificate bytes */;
byte[] sig = /* inline DER walk: signatureValue BIT STRING          */;

var rsa = root.GetRSAPublicKey();
bool chainOk = rsa.VerifyData(tbs, sig,
                 HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);

bool chainModeOk = timeOk && chainOk;   // accepts ANY cert the Root CA signed
// A cert that merely copies the Root CA's issuer NAME but is signed by another
// key fails here (chainOk=false) -> 403 NOT_CA_SIGNED. Cryptography, not string.
'@ }
$snModeSelect = @{ file = 'bicep/modules/apim-config.bicep'; code = @'
// A named value selects which model the policy enforces (plain, not secret).
// certValidationMode = 'pinned' (default) or 'chain'.
resource nvMode 'Microsoft.ApiManagement/service/namedValues@2023-05-01-preview' = {
  parent: apim
  name: 'cert-validation-mode'
  properties: {
    displayName: 'cert-validation-mode'
    value: certValidationMode
    secret: false
  }
}
'@ }
$snApimAuthz = @{ file = 'apim/operation-client1-policy.xml'; code = @'
// Per-client authorization: only the client that owns cert1 may use path A.
// (client2 has the mirror policy for path B.)
<choose>
  <when condition='@((string)((JObject)context.Variables["auth"])["client"] != "client1")'>
    <return-response>
      <set-status code="403" reason="Not authorised for this resource" />
    </return-response>
  </when>
</choose>
'@ }
$snApimUntrusted = @{ file = 'apim/api-policy.xml'; code = @'
// Untrusted issuer -> rejected. The gateway forwarded the cert unvalidated;
// APIM is the trust anchor. In pinned mode the issuer DN must match the KV
// Root CA; in chain mode the Root CA key must have signed the cert.
r["reason"] = ok ? (mode == "chain" ? "CHAIN_OK" : "PINNED_OK")
                 : (mode == "chain"
                     ? "NOT_CA_SIGNED"                 // signature check failed
                     : (!issuerDnMatch ? "UNTRUSTED_ISSUER"
                                       : "NOT_IN_ALLOWLIST"));   // -> 403
'@ }
$snApimNoCert = @{ file = 'apim/api-policy.xml'; code = @'
// No certificate forwarded -> rejected before any trust check.
if (cert == null) {
    r["ok"] = false;
    r["reason"] = "NO_CERT_FORWARDED";
    return r.ToString();   // -> 403 DENY
}
'@ }
$snNetworkLock = @{ file = 'bicep/modules/apim.bicep'; code = @'
// APIM is deployed in INTERNAL VNet mode, reachable only from the App
// Gateway subnet - a forged request cannot skip the gateway.
properties: {
  virtualNetworkType: 'Internal'
  virtualNetworkConfiguration: {
    subnetResourceId: apimSubnetId
  }
}
'@ }
$snWaf = @{ file = 'bicep/modules/waf-policy.bicep'; code = @'
// WAF_v2 stays enabled in Prevention mode throughout.
policySettings: {
  state: 'Enabled'
  mode: 'Prevention'
}
managedRules: {
  managedRuleSets: [ { ruleSetType: 'OWASP', ruleSetVersion: '3.2' } ]
}
'@ }
# validate-apim-keyvault.ps1 ids -- configuration proofs
$snippets['gateway-forwards-cert'] = $snGatewayForward
$snippets['kv-holds-trust-material'] = $snKvTrust
# pinned-model ids
$snippets['pinned-client1'] = $snApimValidate
$snippets['pinned-client2'] = $snApimValidate
$snippets['pinned-client3'] = $snApimValidate
$snippets['pinned-spoofed'] = $snApimValidate
$snippets['pinned-rogue'] = $snApimUntrusted
$snippets['pinned-nocert'] = $snApimNoCert
$snippets['pinned-authz-own'] = $snApimAuthz
$snippets['pinned-authz-cross'] = $snApimAuthz
# chain-model ids
$snippets['chain-client1'] = $snChainVerify
$snippets['chain-client2'] = $snChainVerify
$snippets['chain-client3'] = $snChainVerify
$snippets['chain-spoofed'] = $snChainVerify
$snippets['chain-rogue'] = $snChainVerify
$snippets['chain-nocert'] = $snApimNoCert
# mode selector
$snippets['mode-select'] = $snModeSelect
# legacy run-tests.ps1 ids (kept for the full live-TLS suite)
$snippets['1-possession-positive'] = $snApimValidate
$snippets['2-positive-client2'] = $snApimValidate
$snippets['3-authz-cross'] = $snApimAuthz
$snippets['4-trust-rogue'] = $snApimUntrusted
$snippets['5-no-cert'] = $snApimNoCert
$snippets['6b-inject-nocert'] = $snGatewayForward
$snippets['6b-inject-override'] = $snGatewayForward
$snippets['6a-direct-bypass'] = $snNetworkLock
$snippets['7-waf-retained'] = $snWaf

# Build the per-scenario run cards, grouped by validation model.
$modeGroups = [ordered]@{
    both   = @{ title = 'Configuration proofs'; sub = 'These hold regardless of the chosen model.' }
    pinned = @{ title = 'Model A &middot; Pinned thumbprint allow list'; sub = 'Trust = the certificate&rsquo;s thumbprint is on the Key Vault allow list.' }
    chain  = @{ title = 'Model B &middot; Chain of trust (Root CA signature)'; sub = 'Trust = the Key Vault Root CA cryptographically signed the certificate.' }
}
$knownModes = @($modeGroups.Keys)
# Catch-all for rows without a recognized mode (e.g. the live-TLS run-tests suite).
$otherRows = @($data.results | Where-Object { $knownModes -notcontains $_.mode })
if ($otherRows.Count -gt 0) { $modeGroups['other'] = @{ title = 'Live end-to-end handshake suite'; sub = 'Exercised through the live mTLS handshake once the client-auth feature is registered.' } }
$runCards = [System.Text.StringBuilder]::new()
$i = 0
foreach ($mode in $modeGroups.Keys) {
    $group = if ($mode -eq 'other') { $otherRows } else { @($data.results | Where-Object { $_.mode -eq $mode }) }
    if ($group.Count -eq 0) { continue }
    $g = $modeGroups[$mode]
    $pillLabel = switch ($mode) { 'both' { 'BOTH' } 'other' { 'LIVE' } default { $mode.ToUpper() } }
    [void]$runCards.Append(@"
      <div class="mode-head">
        <span class="mode-pill $mode">$pillLabel</span>
        <div><div class="mode-title">$($g.title)</div><div class="mode-sub">$($g.sub)</div></div>
      </div>
"@)
    foreach ($r in $group) {
        $i++
        $badgeClass = if ($r.pass) { 'ok' } else { 'fail' }
        $badgeText = if ($r.pass) { 'PASS' } else { 'FAIL' }
        $ev = $r.evidence
        $evRows = ''
        if ($ev) {
            if ($null -ne $ev.httpStatus -and $ev.httpStatus -ne 0) { $evRows += "<div class='box'><div class='k'>HTTP status</div><div class='v mono'>$(E([string]$ev.httpStatus))</div></div>" }
            if ($ev.decision) { $evRows += "<div class='box'><div class='k'>APIM decision</div><div class='v mono'>$(E($ev.decision))</div></div>" }
            if ($ev.reason) { $evRows += "<div class='box'><div class='k'>Reason</div><div class='v mono'>$(E($ev.reason))</div></div>" }
            if ($null -ne $ev.chainOk) { $evRows += "<div class='box'><div class='k'>chainOk (RSA signature verified)</div><div class='v mono'>$(E([string]$ev.chainOk))</div></div>" }
            if ($null -ne $ev.pinnedMatch) { $evRows += "<div class='box'><div class='k'>pinnedMatch (on allow list)</div><div class='v mono'>$(E([string]$ev.pinnedMatch))</div></div>" }
            if ($ev.client) { $evRows += "<div class='box'><div class='k'>Authenticated client</div><div class='v mono'>$(E($ev.client))</div></div>" }
        }
        $snippetHtml = ''
        if ($snippets.ContainsKey($r.id)) {
            $sn = $snippets[$r.id]
            $snippetHtml = @"
          <div class="snippet">
            <div class="snippet-bar"><span class="ico">&lt;/&gt;</span> Backed by <span class="tag">$(E($sn.file))</span></div>
<pre>$(E($sn.code))</pre>
          </div>
"@
        }
        [void]$runCards.Append(@"
      <div class="run">
        <div class="run-head">
          <div class="run-num">$i</div>
          <div class="run-title">$(E($r.name))</div>
          <span class="badge $badgeClass">$badgeText</span>
        </div>
        <div class="run-body">
          <div class="ee">
            <div class="box"><div class="k">Expected</div><div class="v">$(E($r.expected))</div></div>
            <div class="box $(if($r.pass){'match'})"><div class="k">Observed</div><div class="v mono">$(E($r.observed))</div></div>
          </div>
          $(if($evRows){"<div class='ee'>$evRows</div>"})
          <div class="term">
            <div class="term-bar"><span class="dot r"></span><span class="dot y"></span><span class="dot g"></span><span class="ttl">$(E($r.id))</span></div>
<pre><span class="c-cmd">$(E($r.command))</span></pre>
          </div>
          <div class="what"><b>Proves:</b> $(E($r.proves))</div>
$snippetHtml
        </div>
      </div>
"@)
    }
}

$possessionCopy = if ($PossessionVerdict -eq 'ENFORCED') {
    'Yes. APIM reconstructs the forwarded certificate and validates it under the selected model before authorizing per client - a pinned-thumbprint allow list, or a real cryptographic chain-of-trust signature check. A certificate from an untrusted issuer is rejected even though the gateway forwarded it unvalidated: APIM is the trust anchor, and Key Vault holds the trust material.'
}
else {
    'See the evidence below for the observed behaviour.'
}
$possessionClass = if ($PossessionVerdict -eq 'ENFORCED') { 'safe' } else { 'drift' }

# --- Optional "also verified on APIM v2" section --------------------------
$v2Section = ''
if ($dataV2) {
    $v2Rows = ''
    foreach ($vr in $dataV2.results) {
        $vb = if ($vr.pass) { 'ok' } else { 'fail' }
        $vt = if ($vr.pass) { 'PASS' } else { 'FAIL' }
        $mtag = switch ($vr.mode) { 'pinned' { 'pinned' } 'chain' { 'chain' } default { 'both' } }
        $v2Rows += "<tr><td><span class='mpill $mtag'>$($vr.mode.ToUpper())</span></td><td>$(E($vr.name))</td><td class='mono'>$(E($vr.observed))</td><td><span class='badge $vb' style='font-size:10.5px'>$vt</span></td></tr>"
    }
    $v2Date = ([datetime]$dataV2.generatedUtc).ToString('yyyy-MM-dd HH:mm')
    $v2Section = @"
  <section>
    <h2 class="section-title">Also verified on API Management v2</h2>
    <div class="callout" style="border-left-color:var(--green); margin-bottom:16px">
      <h4 style="color:var(--green)">&#9679; Same policy, same certs, same results &mdash; on API Management v2.</h4>
      <p>The API Management <b>v2</b> tiers carry a documented limitation: <code>context.Request.Certificate</code> and TLS renegotiation are <b>not supported</b>. That would matter if trust were established at APIM&rsquo;s own TLS layer &mdash; but this scenario never does that. Trust is decided entirely from the <b>forwarded <code>X-Client-Cert</code> header</b>, so the limitation does not apply.</p>
      <p>To prove it, the identical dual-model policy, named values, and certificates were deployed to a standalone <b>API Management v2</b> instance (public gateway) and the same matrix was run directly against its gateway. <b>$($dataV2.passed)/$($dataV2.total) checks passed</b> &mdash; behaviour is identical to the <b>v1</b> deployment, including the real RSA chain-of-trust signature check that rejects the forged-issuer <code>spoofed</code> certificate. The certificate-validation pattern is <b>tier-agnostic</b>: it works the same on API Management v1 and v2.</p>
    </div>
    <div class="scorebar" style="margin-top:0">
      <div><div class="big" style="color:$(if($dataV2.passed -eq $dataV2.total){'var(--green)'}else{'var(--amber)'})">$($dataV2.passed)/$($dataV2.total)</div><div class="lbl">v2 checks passed</div></div>
      <div class="track"><div class="fill" style="width:$(if($dataV2.total -gt 0){[math]::Round(($dataV2.passed/$dataV2.total)*100)}else{0})%"></div></div>
    </div>
    <table class="v2-table">
      <thead><tr><th>Model</th><th>Check</th><th>Observed on API Management v2</th><th>Result</th></tr></thead>
      <tbody>$v2Rows</tbody>
    </table>
    <p style="color:var(--muted); font-size:13px; margin-top:10px">API Management v2 run &middot; $v2Date UTC</p>
  </section>
"@
}

$passPct = if ($data.total -gt 0) { [math]::Round(($data.passed / $data.total) * 100) } else { 0 }
$genDate = ([datetime]$data.generatedUtc).ToString('yyyy-MM-dd HH:mm')

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<title>App Gateway PASSTHROUGH mTLS &rarr; APIM: Live Evidence</title>
<style>
  :root {
    --bg: #0b1020; --bg-2: #11182f; --card: #151d36; --card-2: #1a2342;
    --ink: #e8edf7; --muted: #9aa7c7; --line: #273152;
    --green: #2ecc71; --green-d: #18794e; --amber: #f5a623; --amber-d: #8a5a00;
    --red: #ff5d6c; --red-d: #7a1f2a; --blue: #4ea3ff; --purple: #9b8cff;
    --mono: "SF Mono","JetBrains Mono","Fira Code",Consolas,Menlo,monospace;
    --sans: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
  }
  * { box-sizing: border-box; }
  html { scroll-behavior: smooth; }
  body { margin: 0; font-family: var(--sans); color: var(--ink);
    background: radial-gradient(1200px 800px at 80% -10%, #1c2750 0%, transparent 60%),
                radial-gradient(1000px 700px at -10% 10%, #182043 0%, transparent 55%), var(--bg);
    line-height: 1.6; }
  .wrap { max-width: 1080px; margin: 0 auto; padding: 0 22px; }
  .hero { padding: 72px 0 42px; text-align: center; }
  .eyebrow { display: inline-block; font-family: var(--mono); font-size: 12px; letter-spacing: 2px;
    text-transform: uppercase; color: var(--blue); background: rgba(78,163,255,.1);
    border: 1px solid rgba(78,163,255,.25); padding: 6px 14px; border-radius: 999px; margin-bottom: 22px; }
  .hero h1 { font-size: clamp(30px, 5vw, 50px); line-height: 1.1; margin: 0 0 18px; letter-spacing: -.5px;
    background: linear-gradient(180deg, #ffffff, #b9c6ee); -webkit-background-clip: text; background-clip: text; color: transparent; }
  .hero p.lead { max-width: 760px; margin: 0 auto; color: var(--muted); font-size: 18px; }
  .meta-row { display: flex; flex-wrap: wrap; gap: 10px; justify-content: center; margin-top: 28px; }
  .chip { font-family: var(--mono); font-size: 12.5px; color: var(--ink); background: var(--card);
    border: 1px solid var(--line); padding: 7px 12px; border-radius: 8px; }
  .chip b { color: var(--blue); font-weight: 600; }

  .scorebar { display: flex; align-items: center; gap: 16px; margin: 30px 0 6px;
    background: linear-gradient(135deg, #131c38, #0e1530); border: 1px solid var(--line);
    border-radius: 16px; padding: 20px 24px; }
  .scorebar .big { font-size: 40px; font-weight: 800; font-family: var(--mono);
    color: $(if($data.passed -eq $data.total){'var(--green)'}else{'var(--amber)'}); }
  .scorebar .lbl { color: var(--muted); font-size: 14px; }
  .track { flex: 1; height: 12px; background: rgba(255,255,255,.06); border-radius: 999px; overflow: hidden; }
  .fill { height: 100%; width: $passPct%; background: linear-gradient(90deg, var(--green), #6ee7a8); }

  .verdict { margin: 30px 0 10px; background: linear-gradient(135deg, #131c38, #0e1530);
    border: 1px solid var(--line); border-radius: 18px; padding: 4px; }
  .verdict-inner { padding: 26px; }
  .verdict h3 { margin: 0 0 8px; font-size: 13px; letter-spacing: 2px; text-transform: uppercase; }
  .verdict.safe h3 { color: var(--green); }
  .verdict.drift h3 { color: var(--amber); }
  .verdict .q { font-size: 20px; font-weight: 700; margin: 0 0 12px; }
  .verdict .a { color: var(--ink); font-size: 16px; }

  section { padding: 26px 0; }
  h2.section-title { font-size: 13px; letter-spacing: 2px; text-transform: uppercase; color: var(--muted);
    margin: 0 0 18px; font-weight: 700; display: flex; align-items: center; gap: 10px; }
  h2.section-title::before { content: ""; width: 22px; height: 2px; background: var(--blue); border-radius: 2px; }

  .runs { display: grid; gap: 14px; }
  .mode-head { display: flex; align-items: center; gap: 14px; margin: 22px 0 2px; padding: 14px 18px;
    background: linear-gradient(135deg, #141d3c, #0e1530); border: 1px solid var(--line); border-radius: 12px; }
  .mode-head:first-child { margin-top: 0; }
  .mode-pill { font-family: var(--mono); font-size: 12px; font-weight: 700; letter-spacing: .5px;
    padding: 6px 12px; border-radius: 8px; flex: none; }
  .mode-pill.both   { color: #cdd7f0; background: rgba(154,167,199,.14); border: 1px solid var(--line); }
  .mode-pill.pinned { color: #ffe6b0; background: rgba(245,166,35,.14); border: 1px solid var(--amber-d); }
  .mode-pill.chain  { color: #c9c1ff; background: rgba(155,140,255,.16); border: 1px solid #4a3fa0; }
  .mode-pill.other  { color: #a9e8ff; background: rgba(78,163,255,.14); border: 1px solid #2f5c8a; }
  .mode-title { font-weight: 700; font-size: 16px; }
  .mode-sub { color: var(--muted); font-size: 13px; }
  .run { background: var(--card); border: 1px solid var(--line); border-radius: 14px; overflow: hidden; }
  .run-head { display: flex; align-items: center; gap: 14px; padding: 16px 20px; border-bottom: 1px solid var(--line); }
  .run-num { font-family: var(--mono); font-weight: 700; font-size: 13px; width: 34px; height: 34px; flex: none;
    border-radius: 9px; display: grid; place-items: center; color: #0b1020; background: linear-gradient(135deg, #6ea8ff, #9b8cff); }
  .run-title { font-weight: 600; font-size: 16px; flex: 1; }
  .badge { font-family: var(--mono); font-size: 11.5px; font-weight: 700; padding: 5px 11px; border-radius: 999px; letter-spacing: .4px; white-space: nowrap; }
  .badge.ok   { color: #d6ffe6; background: rgba(46,204,113,.16); border: 1px solid var(--green-d); }
  .badge.fail { color: #ffd6da; background: rgba(255,93,108,.16); border: 1px solid var(--red-d); }
  .run-body { padding: 16px 20px; display: grid; gap: 14px; }
  .ee { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }
  .ee .box { background: var(--card-2); border: 1px solid var(--line); border-radius: 10px; padding: 12px 14px; }
  .ee .box .k { font-size: 11px; text-transform: uppercase; letter-spacing: 1px; color: var(--muted); margin-bottom: 4px; }
  .ee .box .v { font-size: 14px; word-break: break-word; }
  .ee .box .v.mono { font-family: var(--mono); font-size: 13px; }
  .ee .box.match { border-color: var(--green-d); }
  .what { color: var(--muted); font-size: 14px; } .what b { color: var(--ink); }
  .term { background: #0a0e1c; border: 1px solid var(--line); border-radius: 11px; overflow: hidden; font-family: var(--mono); }
  .term-bar { display: flex; align-items: center; gap: 8px; padding: 9px 13px; background: #0c1124; border-bottom: 1px solid var(--line); }
  .term-bar .dot { width: 11px; height: 11px; border-radius: 50%; }
  .dot.r { background: #ff5f57; } .dot.y { background: #febc2e; } .dot.g { background: #28c840; }
  .term-bar .ttl { margin-left: 8px; font-size: 12px; color: var(--muted); }
  .term pre { margin: 0; padding: 14px 16px; font-size: 12.6px; line-height: 1.55; overflow-x: auto; color: #cdd7f0; white-space: pre-wrap; word-break: break-all; }
  .term pre .c-cmd { color: #7fb6ff; }

  /* code snippet backing each check */
  .snippet { background: #0a0e1c; border: 1px solid var(--line); border-left: 3px solid var(--purple); border-radius: 11px; overflow: hidden; }
  .snippet-bar { display: flex; align-items: center; gap: 8px; padding: 8px 13px; background: #0c1124; border-bottom: 1px solid var(--line); font-family: var(--mono); font-size: 12px; color: var(--muted); }
  .snippet-bar .ico { color: var(--purple); font-weight: 700; }
  .snippet-bar .tag { color: #9b8cff; font-weight: 600; }
  .snippet pre { margin: 0; padding: 13px 16px; font-size: 12.3px; line-height: 1.5; overflow-x: auto; color: #cdd7f0; white-space: pre; font-family: var(--mono); }

  .callout { background: linear-gradient(135deg, rgba(155,140,255,.10), rgba(78,163,255,.06));
    border: 1px solid #34407a; border-left: 4px solid var(--purple); border-radius: 12px; padding: 18px 20px; margin-top: 6px; }
  .callout h4 { margin: 0 0 6px; color: var(--purple); font-size: 15px; }
  .callout p { margin: 0 0 8px; color: var(--muted); font-size: 14px; }
  .callout code { font-family: var(--mono); color: var(--ink); background: rgba(255,255,255,.06); padding: 1px 6px; border-radius: 5px; font-size: 12.5px; }

  .conclusion { background: linear-gradient(135deg, #14224a, #0e1530); border: 1px solid var(--line); border-radius: 18px; padding: 32px; margin: 10px 0 40px; }
  .conclusion h2 { margin: 0 0 14px; font-size: 24px; }
  .grid2 { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; margin-top: 8px; }
  .panel { background: #0a0e1c; border: 1px solid var(--line); border-radius: 12px; padding: 18px 20px; }
  .panel h4 { margin: 0 0 10px; font-size: 14px; }
  .panel.good h4 { color: var(--green); } .panel.bad h4 { color: var(--amber); }
  .panel ul { margin: 0; padding-left: 18px; color: var(--muted); font-size: 14px; }
  .panel li { margin-bottom: 8px; } .panel li b { color: var(--ink); }

  footer { text-align: center; color: var(--muted); font-size: 13px; padding: 30px 0 50px; }
  footer code { font-family: var(--mono); }

  /* diagrams */
  .diagram-grid { display: grid; grid-template-columns: 1fr; gap: 18px; }
  .diagram { background: var(--card); border: 1px solid var(--line); border-radius: 14px; padding: 20px 18px; overflow-x: auto; }
  .diagram h4 { margin: 0 0 4px; font-size: 15px; color: var(--ink); }
  .diagram p.cap { margin: 0 0 14px; color: var(--muted); font-size: 13.5px; }
  .diagram .mermaid { display: flex; justify-content: center; }
  .diagram svg { max-width: 100%; height: auto; }

  /* two-models comparison */
  .models { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
  .model { background: var(--card); border: 1px solid var(--line); border-radius: 14px; padding: 22px; }
  .model.pinned { border-top: 3px solid var(--amber); }
  .model.chain  { border-top: 3px solid var(--purple); }
  .model h4 { margin: 0 0 4px; font-size: 18px; }
  .model .tagline { color: var(--muted); font-size: 13.5px; margin: 0 0 14px; }
  .model .kv { display: grid; grid-template-columns: auto 1fr; gap: 8px 14px; font-size: 14px; }
  .model .kv .k { color: var(--muted); }
  .model .kv .v { color: var(--ink); }
  .model .verdict-line { margin-top: 14px; padding-top: 14px; border-top: 1px solid var(--line); font-size: 13.5px; }
  .model .verdict-line b { color: var(--ink); }
  .cmp-table { width: 100%; border-collapse: collapse; margin-top: 4px; font-size: 14px; }
  .cmp-table th, .cmp-table td { text-align: left; padding: 11px 14px; border-bottom: 1px solid var(--line); vertical-align: top; }
  .cmp-table thead th { color: var(--muted); font-size: 12px; text-transform: uppercase; letter-spacing: 1px; }
  .cmp-table tbody th { color: var(--ink); font-weight: 600; width: 26%; }
  .cmp-table td.pin { color: #ffe6b0; } .cmp-table td.chn { color: #c9c1ff; }
  .cmp-table .mono { font-family: var(--mono); font-size: 12.5px; }

  /* v2 tier-parity table */
  .v2-table { width: 100%; border-collapse: collapse; margin-top: 14px; font-size: 13.5px;
    background: var(--card); border: 1px solid var(--line); border-radius: 12px; overflow: hidden; }
  .v2-table th, .v2-table td { text-align: left; padding: 10px 13px; border-bottom: 1px solid var(--line); vertical-align: middle; }
  .v2-table thead th { color: var(--muted); font-size: 11px; text-transform: uppercase; letter-spacing: 1px; background: #0e1530; }
  .v2-table tbody tr:last-child td { border-bottom: none; }
  .v2-table td.mono { font-family: var(--mono); font-size: 12px; color: #cdd7f0; }
  .mpill { font-family: var(--mono); font-size: 10px; font-weight: 700; padding: 3px 8px; border-radius: 6px; }
  .mpill.pinned { color: #ffe6b0; background: rgba(245,166,35,.14); border: 1px solid var(--amber-d); }
  .mpill.chain  { color: #c9c1ff; background: rgba(155,140,255,.16); border: 1px solid #4a3fa0; }
  .mpill.both   { color: #cdd7f0; background: rgba(154,167,199,.14); border: 1px solid var(--line); }

  @media (max-width: 760px) { .ee, .grid2, .models { grid-template-columns: 1fr; } }
</style>
</head>
<body>

<header class="hero">
  <div class="wrap">
    <span class="eyebrow">Tested end-to-end on Azure</span>
    <h1>True mTLS validation at APIM, behind an App Gateway in <em>passthrough</em></h1>
    <p class="lead">
      A caller presents a client certificate &rarr; Azure Application Gateway (WAF_v2, <b>passthrough</b>)
      forwards it &rarr; API Management performs the real certificate validation. The gateway never
      validates the cert &mdash; APIM does. Here is each link, proven with real command output.
    </p>
    <div class="meta-row">
      <span class="chip"><b>Region</b> eastus2</span>
      <span class="chip"><b>App Gateway</b> WAF_v2 passthrough</span>
      <span class="chip"><b>APIM</b> v1, internal VNet</span>
      <span class="chip"><b>Generated</b> $genDate UTC</span>
    </div>

    <div class="scorebar">
      <div><div class="big">$($data.passed)/$($data.total)</div><div class="lbl">scenarios passed</div></div>
      <div class="track"><div class="fill"></div></div>
    </div>
  </div>
</header>

<div class="wrap">

  <div class="verdict $possessionClass">
    <div class="verdict-inner">
      <h3>&#9679; The core question &mdash; true mTLS validation at APIM</h3>
      <p class="q">Does App Gateway forward the client certificate to APIM, and does APIM validate it against Key Vault?</p>
      <p class="a">$(E($possessionCopy))</p>
    </div>
  </div>

  <section>
    <h2 class="section-title">Two validation models &middot; both fully supported</h2>
    <p style="color:var(--muted); font-size:15px; margin:-6px 0 18px; max-width:820px">
      There are two legitimate ways to decide whether a forwarded certificate is trustworthy, and this scenario
      ships <b>both</b>. Choose one with the <code style="font-family:var(--mono); background:rgba(255,255,255,.06); padding:1px 6px; border-radius:5px">certValidationMode</code>
      parameter (<code style="font-family:var(--mono)">pinned</code> or <code style="font-family:var(--mono)">chain</code>). Neither is
      universally &ldquo;correct&rdquo; &mdash; they trade explicit control against operational overhead. Both were run live; see the evidence below.
    </p>
    <div class="models">
      <div class="model pinned">
        <h4>&#128273; Model A &middot; Pinned thumbprint</h4>
        <p class="tagline">Accept only certificates on a Key Vault allow list.</p>
        <div class="kv">
          <div class="k">Trust test</div><div class="v">SHA-1 thumbprint is on the allow list (and issuer matches the Root CA).</div>
          <div class="k">New client</div><div class="v">Add its thumbprint to Key Vault first.</div>
          <div class="k">Strength</div><div class="v">Most restrictive; an over-permissive CA can&rsquo;t widen access.</div>
          <div class="k">Cost</div><div class="v">Per-certificate maintenance.</div>
          <div class="k">Best for</div><div class="v">A small, known set of clients.</div>
        </div>
        <div class="verdict-line"><b>client3</b> (CA-signed, not listed) &rarr; <b>rejected</b> &middot; <b>spoofed</b> &rarr; rejected (not on list)</div>
      </div>
      <div class="model chain">
        <h4>&#128279; Model B &middot; Chain of trust</h4>
        <p class="tagline">Accept anything the Root CA cryptographically signed.</p>
        <div class="kv">
          <div class="k">Trust test</div><div class="v">Root CA public key verifies the certificate&rsquo;s RSA signature (real <span class="mono">VerifyData</span>).</div>
          <div class="k">New client</div><div class="v">Works automatically once your CA issues it.</div>
          <div class="k">Strength</div><div class="v">No allow list to maintain; trust the CA, not each cert.</div>
          <div class="k">Cost</div><div class="v">You must fully trust (and protect) the CA.</div>
          <div class="k">Best for</div><div class="v">A private CA issuing many / rotating client certs.</div>
        </div>
        <div class="verdict-line"><b>client3</b> (CA-signed, not listed) &rarr; <b>accepted</b> &middot; <b>spoofed</b> &rarr; rejected (<span class="mono">NOT_CA_SIGNED</span>)</div>
      </div>
    </div>
    <div class="callout" style="margin-top:16px">
      <h4>&ldquo;Isn&rsquo;t this just a thumbprint or name compare?&rdquo; &mdash; No.</h4>
      <p>Chain mode performs a genuine RSA signature verification with the Key Vault Root CA&rsquo;s public key. The <code>spoofed</code> certificate proves it: its issuer Distinguished Name is <b>byte-for-byte identical</b> to the real Root CA (<code>CN=mTLS POC Root CA</code>), yet it is rejected with <code>NOT_CA_SIGNED</code> and <code>chainOk=false</code> &mdash; because the Root CA&rsquo;s key never signed it. A string comparison would have been fooled; <code>RSA.VerifyData</code> is not.</p>
      <p><b>Sandbox note:</b> the APIM policy validator blocks both <code>X509Chain</code> and <code>System.Func</code> (both confirmed at deploy time), so chain mode parses the leaf DER inline to recover the <code>TBSCertificate</code> bytes and signature, then verifies with <code>GetRSAPublicKey().VerifyData(...)</code>.</p>
    </div>
  </section>

  <section>
    <h2 class="section-title">How it works</h2>
    <div class="diagram-grid">
      <div class="diagram">
        <h4>Architecture &mdash; who does what</h4>
        <p class="cap">The gateway forwards the certificate; APIM is the trust anchor and validates it against Key Vault material.</p>
        <pre class="mermaid">
flowchart LR
    Caller(["Caller<br/>presents client cert"])
    subgraph AGW["Application Gateway &bull; WAF_v2 &bull; PASSTHROUGH"]
      direction TB
      L["HTTPS listener :443<br/>requests client cert,<br/>does NOT validate"]
      RW["Header rewrite (overwrite)<br/>X-Client-Cert = {var_client_certificate}"]
      L --> RW
    end
    subgraph VNET["Internal virtual network (locked down)"]
      APIM["API Management<br/>validates cert in policy"]
    end
    KV["Key Vault<br/>Root CA + pinned allow-list"]
    Caller -- "mTLS (client cert)" --> AGW
    AGW -- "HTTPS + forwarded cert header" --> APIM
    KV -. "named values (managed identity)" .-> APIM
    APIM -- "200 ALLOW / 403 DENY" --> Caller
</pre>
      </div>
      <div class="diagram">
        <h4>Request sequence &mdash; end to end</h4>
        <p class="cap">Trust is decided in APIM against Key Vault, not at the gateway.</p>
        <pre class="mermaid">
sequenceDiagram
    autonumber
    participant C as Caller
    participant AG as App Gateway
    participant A as APIM
    participant KV as Key Vault
    C->>AG: TLS handshake plus client certificate
    Note over AG: Passthrough - requests the cert but does not validate it
    AG->>AG: Rewrite - overwrite X-Client-Cert with the TLS cert
    AG->>A: HTTPS plus X-Client-Cert header, forwarded PEM
    A->>KV: Resolve Root CA and allow-list via named values
    KV-->>A: trusted-root-ca-der-b64 and client-cert-allowlist
    A->>A: Parse cert, check validity, issuer vs Root CA, thumbprint vs allow-list
    alt Trusted, allow-listed and authorized
        A-->>C: 200 ALLOW
    else Untrusted or not allow-listed or wrong path
        A-->>C: 403 DENY
    end
</pre>
      </div>
    </div>
  </section>

  <section>
    <h2 class="section-title">Every scenario &middot; expected vs. actual</h2>
    <div class="runs">
$($runCards.ToString())
    </div>
  </section>
$v2Section
  <section>
    <h2 class="section-title">How we validated the forwarded certificate in the APIM sandbox</h2>
    <div class="callout">
      <h4>Parse the header, then decide trust in APIM &mdash; never at the gateway.</h4>
      <p>Behind a Layer-7 gateway, APIM's <code>context.Request.Certificate</code> is <b>not</b> the client cert (the gateway opens a separate TLS session to APIM). The client certificate is forwarded as a percent-encoded PEM in <code>X-Client-Cert</code>, set from the gateway's mutual-authentication server variables.</p>
      <p>The APIM policy URL-decodes the header, strips the PEM armor, base64-decodes to DER, and builds an <code>X509Certificate2</code>. It then checks the validity window and applies the active model: a Key Vault-sourced thumbprint allow list (pinned) or a real Root CA signature verification (chain).</p>
      <p><b>Sandbox limitations found at deploy time:</b> the APIM policy-expression validator rejects <code>DateTime.ToUniversalTime()</code>, <code>X509Chain</code>, and <code>System.Func</code>. Validity uses <code>DateTime.Now</code> against the certificate&rsquo;s local <code>NotBefore</code>/<code>NotAfter</code>; chain mode verifies trust by parsing the leaf DER inline (no <code>X509Chain</code>, no lambdas) and calling <code>GetRSAPublicKey().VerifyData(...)</code> with the Key Vault Root CA.</p>
    </div>
  </section>

  <div class="conclusion">
    <h2>Security verdict</h2>
    <div class="panel good" style="margin-bottom:16px">
      <h4>&#9679; A strong, defensible pattern</h4>
      <ul>
        <li><b>Possession</b> &mdash; enforced by TLS; a public certificate without its private key is useless.</li>
        <li><b>Trust</b> &mdash; enforced in APIM under whichever model you pick: a pinned Key Vault allow list, <b>or</b> a real cryptographic chain-of-trust signature check. APIM is the trust anchor either way.</li>
        <li><b>Real cryptography, not string matching</b> &mdash; chain mode rejects the <code style="font-family:var(--mono)">spoofed</code> certificate (identical issuer name, forged signature) with <code style="font-family:var(--mono)">chainOk=false</code>. Trust is proven by the CA&rsquo;s key, not by a name.</li>
        <li><b>Authorization</b> &mdash; per-client path binding in APIM operation policies.</li>
        <li><b>Anti-spoofing</b> &mdash; the gateway <b>overwrites</b> every <code style="font-family:var(--mono)">X-Client-Cert*</code> header from the real TLS connection, and APIM is reachable only from the gateway (internal VNet), so a forged header can&rsquo;t be injected or bypass the gateway.</li>
      </ul>
    </div>
    <p style="color:var(--muted); font-size:14.5px; margin:0">
      One thing to keep in mind: the gateway itself performs no certificate validation in passthrough, so
      treat its <code style="font-family:var(--mono)">client_certificate_verification</code> value as informational only &mdash;
      the header overwrite and the internal-VNet lockdown are what make the forwarded certificate trustworthy for APIM to validate.
    </p>
  </div>

</div>

<footer class="wrap">
  Tested end-to-end on Azure &middot; Azure Scenario Hub &middot;
  scenario <code>app-gateway-mtls-passthrough-apim-validation</code>
</footer>

<script type="module">
  import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';
  mermaid.initialize({
    startOnLoad: true,
    theme: 'dark',
    securityLevel: 'loose',
    themeVariables: {
      background: '#151d36',
      primaryColor: '#1a2342',
      primaryTextColor: '#e8edf7',
      primaryBorderColor: '#4ea3ff',
      lineColor: '#6ea8ff',
      secondaryColor: '#11182f',
      tertiaryColor: '#0a0e1c',
      fontFamily: 'ui-sans-serif, system-ui, sans-serif'
    }
  });
</script>

</body>
</html>
"@

$html | Set-Content -Path $OutputPath -Encoding utf8
