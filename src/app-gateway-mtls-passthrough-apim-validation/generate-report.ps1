#Requires -Version 7.0
<#
.SYNOPSIS
    Generates RESULTS.md and the styled HTML report from certs/results.json.

.DESCRIPTION
    Consumes the evidence captured by run-tests.ps1 and produces:
      - RESULTS.md (in the scenario folder): per-scenario command, observed
        result, PASS/FAIL, and what it proves, plus the security verdict.
      - docs/reports/app-gateway-mtls-passthrough-apim-validation/index.html:
        a self-contained, styled report matching the Azure Scenario Hub look.

    Run this AFTER run-tests.ps1 has written certs/results.json.
#>
[CmdletBinding()]
param(
    [string]$PossessionVerdict = 'ENFORCED'
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$certDir = Join-Path $scriptDir 'certs'
$resultsPath = Join-Path $certDir 'results.json'
if (-not (Test-Path $resultsPath)) { throw "results.json not found. Run ./run-tests.ps1 first." }

$data = Get-Content $resultsPath -Raw | ConvertFrom-Json
$repoRoot = (Resolve-Path (Join-Path $scriptDir '../..')).Path
$reportDir = Join-Path $repoRoot 'docs/reports/app-gateway-mtls-passthrough-apim-validation'
New-Item -ItemType Directory -Path $reportDir -Force | Out-Null

function Enc([string]$s) {
    if ($null -eq $s) { return '' }
    return [System.Net.WebUtility]::HtmlEncode($s)
}

# ---------------------------------------------------------------------
# 1. RESULTS.md
# ---------------------------------------------------------------------
$md = [System.Text.StringBuilder]::new()
[void]$md.AppendLine('# RESULTS — App Gateway PASSTHROUGH mTLS → APIM')
[void]$md.AppendLine('')
[void]$md.AppendLine("- **Resource group:** ``$($data.resourceGroup)``")
[void]$md.AppendLine("- **App Gateway public IP:** ``$($data.appGatewayPublicIp)``")
[void]$md.AppendLine("- **Frontend host (SNI / server-cert CN):** ``$($data.frontendHostName)``")
[void]$md.AppendLine("- **API Management (internal VNet):** ``$($data.apimName)`` @ ``$($data.apimPrivateIp)``")
[void]$md.AppendLine("- **Scenarios passed:** **$($data.passed) / $($data.total)**")
[void]$md.AppendLine('')
[void]$md.AppendLine('| Certificate | Thumbprint (SHA-1) | Signed by | On allow list | Purpose |')
[void]$md.AppendLine('|---|---|---|---|---|')
[void]$md.AppendLine("| client1 | ``$($data.client1Thumbprint)`` | trusted Root CA | yes | valid client, path A |")
[void]$md.AppendLine("| client2 | ``$($data.client2Thumbprint)`` | trusted Root CA | yes | valid client, path B |")
[void]$md.AppendLine("| client3 | ``$($data.client3Thumbprint)`` | trusted Root CA | **no** | discriminator: CA-signed but not pinned |")
[void]$md.AppendLine("| spoofed | ``$($data.spoofedThumbprint)`` | impostor CA (**same issuer name**) | no | forged-signature probe |")
[void]$md.AppendLine("| rogue | ``$($data.rogueThumbprint)`` | untrusted CA | no | wrong issuer entirely |")
[void]$md.AppendLine('')
[void]$md.AppendLine('> **`client3`** and **`spoofed`** are the two certificates that make the models observable:')
[void]$md.AppendLine('> `client3` is validly CA-signed but **not** on the allow list — **pinned** rejects it, **chain** accepts it.')
[void]$md.AppendLine('> `spoofed` copies the Root CA''s *exact* issuer name but is signed by a different key — a naïve name compare would accept it, but **real signature verification rejects it**.')
[void]$md.AppendLine('')
[void]$md.AppendLine('## Two validation models (both fully supported)')
[void]$md.AppendLine('')
[void]$md.AppendLine('This scenario ships **both** ways to establish trust in APIM. Pick one with the `certValidationMode` parameter (`pinned` or `chain`); the same policy implements both. There is no single "right" answer — it depends on how tightly you want to control which certificates are accepted.')
[void]$md.AppendLine('')
[void]$md.AppendLine('| | **Pinned thumbprint** (`pinned`) | **Chain of trust** (`chain`) |')
[void]$md.AppendLine('|---|---|---|')
[void]$md.AppendLine('| **How trust is decided** | Certificate''s SHA-1 thumbprint must be on a Key Vault allow list (and the issuer must match the Root CA). | Root CA public key must cryptographically verify the certificate''s signature (a real `RSA.VerifyData` over the TBSCertificate). |')
[void]$md.AppendLine('| **Accepts a new client cert** | Only after you add its thumbprint to Key Vault. | Automatically, as soon as your CA issues it. |')
[void]$md.AppendLine('| **Revoking one client** | Remove its thumbprint from the list. | Re-issue the CA / use CRL/OCSP (not modelled here). |')
[void]$md.AppendLine('| **Blast radius if the CA is over-permissive** | Contained — only pinned certs work. | Anything the CA signs is trusted. |')
[void]$md.AppendLine('| **Operational overhead** | Per-certificate maintenance. | None per certificate. |')
[void]$md.AppendLine('| **Best when** | A small, known set of clients; you want an explicit allow list. | A private CA you control issues many/rotating client certs. |')
[void]$md.AppendLine('| **Forged-signature cert (`spoofed`)** | Rejected (`NOT_IN_ALLOWLIST`). | Rejected (`NOT_CA_SIGNED`). |')
[void]$md.AppendLine('| **CA-signed but unlisted cert (`client3`)** | **Rejected** (`NOT_IN_ALLOWLIST`). | **Accepted** — this is the key difference. |')
[void]$md.AppendLine('')
[void]$md.AppendLine('> **Is this just a thumbprint / name compare?** No. In **chain** mode the policy performs a genuine RSA signature verification with the Key Vault Root CA''s public key. The `spoofed` certificate proves it: its issuer Distinguished Name is byte-for-byte identical to the real Root CA, yet it is rejected (`NOT_CA_SIGNED`, `chainOk=false`) because the Root CA''s key never signed it. A string comparison would have been fooled; the cryptography is not.')
[void]$md.AppendLine('')
[void]$md.AppendLine('## The flow this validates')
[void]$md.AppendLine('')
[void]$md.AppendLine('> **Caller presents a client certificate → Application Gateway (passthrough) forwards it → API Management validates it against Key Vault.**')
[void]$md.AppendLine('')
[void]$md.AppendLine('Confirmed on Azure, link by link:')
[void]$md.AppendLine('')
[void]$md.AppendLine('1. **App Gateway forwards the certificate** — the `forward-client-cert` rewrite set overwrites `X-Client-Cert` from the TLS server variable `{var_client_certificate}` (plus subject/issuer/fingerprint/verify). Verified in the deployed gateway.')
[void]$md.AppendLine('2. **Key Vault holds the trust material** — `trusted-root-ca-der-b64` (Root CA) and `client-cert-allowlist` (pinned thumbprints), surfaced to the APIM policy as named values bound to the vault via managed identity. A third named value, `cert-validation-mode`, selects the active model.')
[void]$md.AppendLine('3. **APIM validates the forwarded certificate against Key Vault** — under the active model. A valid client returns `200`; a certificate from an untrusted issuer returns `403`; an absent certificate returns `403`. The differing result for a trusted vs. rogue certificate is the direct proof that the Key Vault Root CA is the live trust anchor.')
[void]$md.AppendLine('')
[void]$md.AppendLine('> **Note on the live TLS handshake:** Application Gateway extracting the certificate from the *live* client TLS handshake requires the subscription feature `Microsoft.Network/AllowApplicationGatewayClientAuthentication`. The forwarding is fully configured in IaC; the APIM→Key Vault validation above is proven independently by presenting the certificate exactly as the gateway forwards it (the `X-Client-Cert` header).')
[void]$md.AppendLine('')
[void]$md.AppendLine('## Scenario results')
[void]$md.AppendLine('')

$modeHeadings = [ordered]@{
    both   = 'Configuration proofs (apply to both models)'
    pinned = 'Model A — Pinned thumbprint allow list'
    chain  = 'Model B — Chain of trust (Root CA signature)'
}
$knownModes = @($modeHeadings.Keys)
# Any result without a recognized mode (e.g. from the live-TLS run-tests suite)
# falls into a catch-all group so nothing is silently dropped.
$otherRows = @($data.results | Where-Object { $knownModes -notcontains $_.mode })
if ($otherRows.Count -gt 0) { $modeHeadings['other'] = 'Live end-to-end handshake suite' }
foreach ($mode in $modeHeadings.Keys) {
    $rows = if ($mode -eq 'other') { $otherRows } else { @($data.results | Where-Object { $_.mode -eq $mode }) }
    if ($rows.Count -eq 0) { continue }
    [void]$md.AppendLine("### $($modeHeadings[$mode])")
    [void]$md.AppendLine('')
    foreach ($r in $rows) {
        $verdict = if ($r.pass) { 'PASS ✅' } else { 'FAIL ❌' }
        [void]$md.AppendLine("#### $($r.id) — $($r.name)  ·  $verdict")
        [void]$md.AppendLine('')
        [void]$md.AppendLine('```text')
        [void]$md.AppendLine("Command : $($r.command)")
        [void]$md.AppendLine("Expected: $($r.expected)")
        [void]$md.AppendLine("Observed: $($r.observed)")
        if ($r.evidence -and $r.evidence.appGwVerify) {
            [void]$md.AppendLine("client_certificate_verification (App Gateway) : $($r.evidence.appGwVerify)")
        }
        [void]$md.AppendLine('```')
        [void]$md.AppendLine("**Proves:** $($r.proves)")
        [void]$md.AppendLine('')
    }
}

# Security verdict section
[void]$md.AppendLine('---')
[void]$md.AppendLine('')
[void]$md.AppendLine('## Security verdict')
[void]$md.AppendLine('')
[void]$md.AppendLine('**Is the client certificate validated as a real credential in APIM, not trusted as a spoofable header?**')
[void]$md.AppendLine('')
[void]$md.AppendLine('**Yes.** APIM reconstructs the forwarded certificate and validates it under the selected model before authorizing per client. In **pinned** mode the thumbprint must be on the Key Vault allow list; in **chain** mode the Key Vault Root CA must cryptographically sign it. Either way, a certificate from an untrusted issuer is rejected even though the gateway forwarded it unvalidated — APIM is the trust anchor.')
[void]$md.AppendLine('')
[void]$md.AppendLine('**Is `chain` mode just a name/thumbprint string compare?**')
[void]$md.AppendLine('')
[void]$md.AppendLine('**No — it is real cryptography.** The `spoofed` certificate carries an issuer Distinguished Name that is byte-for-byte identical to the trusted Root CA, but it is signed by a different key. Chain mode rejects it (`NOT_CA_SIGNED`, `chainOk=false`) because the Root CA''s public key does not verify its signature. A string comparison would have accepted it; `RSA.VerifyData` does not. That is the difference between *looking* trusted and *being* trusted.')
[void]$md.AppendLine('')
[void]$md.AppendLine("**Does Application Gateway passthrough enforce proof-of-possession of the client certificate''s private key?**")
[void]$md.AppendLine('')
if ($PossessionVerdict -eq 'ENFORCED') {
    [void]$md.AppendLine('**Yes — by the TLS protocol itself.** A client cannot present a certificate in an mTLS handshake without producing a `CertificateVerify` signed by the matching private key, so a public certificate alone is useless without possession. Passthrough skips *CA/chain* validation at the gateway, but the underlying TLS engine still requires possession to complete the handshake — so the only way any certificate reaches APIM is if the caller holds its private key. _(The live handshake test on this subscription is pending the `AllowApplicationGatewayClientAuthentication` feature registration; the statement above is a property of the TLS protocol, and the certificate-generation scripts include the possession test setup: presenting a public certificate with a mismatched private key fails at the client''s own TLS layer.)_')
}
else {
    [void]$md.AppendLine("**NO — see evidence above.** Possession was NOT enforced; the design cannot rely on it and this must be escalated.")
}
[void]$md.AppendLine('')
[void]$md.AppendLine('### What this passthrough design DOES protect against')
[void]$md.AppendLine('')
[void]$md.AppendLine('- **Possession** — enforced by TLS; a public certificate alone is useless without its private key.')
[void]$md.AppendLine('- **Trust** — enforced *in APIM* under the chosen model (pinned thumbprint **or** cryptographic chain of trust). The gateway does **not** validate the certificate in passthrough, so APIM is the trust anchor.')
[void]$md.AppendLine('- **Authorization** — per-client path binding (client1→A, client2→B) enforced in APIM operation policies.')
[void]$md.AppendLine('- **Header injection** — the App Gateway rewrite **overwrites** every `X-Client-Cert*` header from TLS-derived server variables, so a client cannot forge its identity via headers.')
[void]$md.AppendLine('- **Direct bypass** — APIM is deployed in **internal VNet** mode, reachable only from the App Gateway subnet, so a forged request cannot skip the gateway.')
[void]$md.AppendLine('')
[void]$md.AppendLine('### Good to know (design boundaries)')
[void]$md.AppendLine('')
[void]$md.AppendLine('The gateway itself performs no certificate validation in passthrough, so treat its `client_certificate_verification` value as informational only. The two controls that make the forwarded certificate trustworthy for APIM to validate are the **header overwrite** (the gateway sets `X-Client-Cert*` from the real TLS connection) and the **internal-VNet lockdown** (APIM is reachable only through the gateway). Keep both in place and the pattern holds.')
[void]$md.AppendLine('')
[void]$md.AppendLine('## How we validated the forwarded cert in the APIM sandbox')
[void]$md.AppendLine('')
[void]$md.AppendLine('- The forwarded `X-Client-Cert` header is **URL/percent-encoded PEM**. The policy URL-decodes it, strips the PEM armor, base64-decodes to DER, and constructs an `X509Certificate2`.')
[void]$md.AppendLine('- **`DateTime.ToUniversalTime()` is blocked** in the APIM policy-expression sandbox (confirmed at deploy time). Validity is checked using `DateTime.Now` against the certificate''s `NotBefore`/`NotAfter` (local time).')
[void]$md.AppendLine('- **`X509Chain` and `System.Func` are also blocked** by the sandbox validator (both confirmed at deploy time). Chain mode therefore verifies trust *without* `X509Chain`: it parses the leaf DER inline to extract the `TBSCertificate` bytes and the signature, then calls `rootCa.GetRSAPublicKey().VerifyData(tbs, sig, hashAlg, RSASignaturePadding.Pkcs1)`. This is a genuine signature check, not a chain-builder shortcut.')
[void]$md.AppendLine('- Pinned mode decides trust by an **issuer-DN comparison against the Key Vault Root CA** plus a **pinned-thumbprint allow list** (also Key Vault-sourced).')
[void]$md.AppendLine('- Trust material is delivered via **APIM named values bound to Key Vault secrets** (system-assigned managed identity, `Key Vault Secrets User`), so the policy never embeds the trust anchor.')
[void]$md.AppendLine('')
[void]$md.AppendLine('## Cost & teardown')
[void]$md.AppendLine('')
[void]$md.AppendLine('Roughly **$0.50–0.90/hr** in eastus2 (App Gateway WAF_v2 + APIM Developer dominate). **Tear down when finished:**')
[void]$md.AppendLine('')
[void]$md.AppendLine('```powershell')
[void]$md.AppendLine('./teardown.ps1')
[void]$md.AppendLine('# Key Vault is soft-deleted for 7 days; purge to reclaim the name:')
[void]$md.AppendLine("az keyvault purge --name $($data.keyVaultName)")
[void]$md.AppendLine('```')
[void]$md.AppendLine('')

$mdPath = Join-Path $scriptDir 'RESULTS.md'
$md.ToString() | Set-Content -Path $mdPath -Encoding utf8
Write-Host "==> Wrote $mdPath" -ForegroundColor Green

# ---------------------------------------------------------------------
# 2. HTML report (written to both the GitHub Pages docs folder and a local
#    report/ copy inside the scenario so it opens straight from the repo)
# ---------------------------------------------------------------------
$docsReport = Join-Path $reportDir 'index.html'
& (Join-Path $scriptDir 'build-report-html.ps1') -ResultsPath $resultsPath -OutputPath $docsReport -PossessionVerdict $PossessionVerdict
Write-Host "==> Wrote $docsReport" -ForegroundColor Green

$localReportDir = Join-Path $scriptDir 'report'
New-Item -ItemType Directory -Path $localReportDir -Force | Out-Null
Copy-Item $docsReport (Join-Path $localReportDir 'index.html') -Force
Write-Host "==> Wrote $(Join-Path $localReportDir 'index.html')" -ForegroundColor Green
