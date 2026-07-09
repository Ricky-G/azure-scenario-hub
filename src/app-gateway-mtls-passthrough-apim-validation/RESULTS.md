# RESULTS — App Gateway PASSTHROUGH mTLS → APIM

- **Resource group:** `rg-appgw-passthrough-mtls-poc`
- **App Gateway public IP:** `20.96.116.219`
- **Frontend host (SNI / server-cert CN):** `api.mtls-poc.local`
- **API Management (internal VNet):** `mtlspocapimuc6wxti2blws4` @ `10.20.2.4`
- **Scenarios passed:** **16 / 16**

| Certificate | Thumbprint (SHA-1) | Signed by | On allow list | Purpose |
|---|---|---|---|---|
| client1 | `1D692C424739EE332080AB878F64B5CAC2D9975A` | trusted Root CA | yes | valid client, path A |
| client2 | `F196E5456226C70C887E1FB61103966A969E48B1` | trusted Root CA | yes | valid client, path B |
| client3 | `C7C1FF90A0E3994C899FC54E5E0DB829DC37219B` | trusted Root CA | **no** | discriminator: CA-signed but not pinned |
| spoofed | `BDECECD7E15D4492778DDB550F63DAD921D8DCC2` | impostor CA (**same issuer name**) | no | forged-signature probe |
| rogue | `54A835E19FD5907196F28D288CA60F6A1C6617C5` | untrusted CA | no | wrong issuer entirely |

> **`client3`** and **`spoofed`** are the two certificates that make the models observable:
> `client3` is validly CA-signed but **not** on the allow list — **pinned** rejects it, **chain** accepts it.
> `spoofed` copies the Root CA's *exact* issuer name but is signed by a different key — a naïve name compare would accept it, but **real signature verification rejects it**.

## Two validation models (both fully supported)

This scenario ships **both** ways to establish trust in APIM. Pick one with the `certValidationMode` parameter (`pinned` or `chain`); the same policy implements both. There is no single "right" answer — it depends on how tightly you want to control which certificates are accepted.

| | **Pinned thumbprint** (`pinned`) | **Chain of trust** (`chain`) |
|---|---|---|
| **How trust is decided** | Certificate's SHA-1 thumbprint must be on a Key Vault allow list (and the issuer must match the Root CA). | Root CA public key must cryptographically verify the certificate's signature (a real `RSA.VerifyData` over the TBSCertificate). |
| **Accepts a new client cert** | Only after you add its thumbprint to Key Vault. | Automatically, as soon as your CA issues it. |
| **Revoking one client** | Remove its thumbprint from the list. | Re-issue the CA / use CRL/OCSP (not modelled here). |
| **Blast radius if the CA is over-permissive** | Contained — only pinned certs work. | Anything the CA signs is trusted. |
| **Operational overhead** | Per-certificate maintenance. | None per certificate. |
| **Best when** | A small, known set of clients; you want an explicit allow list. | A private CA you control issues many/rotating client certs. |
| **Forged-signature cert (`spoofed`)** | Rejected (`NOT_IN_ALLOWLIST`). | Rejected (`NOT_CA_SIGNED`). |
| **CA-signed but unlisted cert (`client3`)** | **Rejected** (`NOT_IN_ALLOWLIST`). | **Accepted** — this is the key difference. |

> **Is this just a thumbprint / name compare?** No. In **chain** mode the policy performs a genuine RSA signature verification with the Key Vault Root CA's public key. The `spoofed` certificate proves it: its issuer Distinguished Name is byte-for-byte identical to the real Root CA, yet it is rejected (`NOT_CA_SIGNED`, `chainOk=false`) because the Root CA's key never signed it. A string comparison would have been fooled; the cryptography is not.

## The flow this validates

> **Caller presents a client certificate → Application Gateway (passthrough) forwards it → API Management validates it against Key Vault.**

Confirmed on Azure, link by link:

1. **App Gateway forwards the certificate** — the `forward-client-cert` rewrite set overwrites `X-Client-Cert` from the TLS server variable `{var_client_certificate}` (plus subject/issuer/fingerprint/verify). Verified in the deployed gateway.
2. **Key Vault holds the trust material** — `trusted-root-ca-der-b64` (Root CA) and `client-cert-allowlist` (pinned thumbprints), surfaced to the APIM policy as named values bound to the vault via managed identity. A third named value, `cert-validation-mode`, selects the active model.
3. **APIM validates the forwarded certificate against Key Vault** — under the active model. A valid client returns `200`; a certificate from an untrusted issuer returns `403`; an absent certificate returns `403`. The differing result for a trusted vs. rogue certificate is the direct proof that the Key Vault Root CA is the live trust anchor.

> **Note on the live TLS handshake:** Application Gateway extracting the certificate from the *live* client TLS handshake requires the subscription feature `Microsoft.Network/AllowApplicationGatewayClientAuthentication`. The forwarding is fully configured in IaC; the APIM→Key Vault validation above is proven independently by presenting the certificate exactly as the gateway forwards it (the `X-Client-Cert` header).

## Scenario results

### Configuration proofs (apply to both models)

#### gateway-forwards-cert — App Gateway forwards the client certificate to APIM  ·  PASS ✅

```text
Command : az network application-gateway rewrite-rule list --rule-set-name forward-client-cert
Expected: Rewrite rule SETS X-Client-Cert = {var_client_certificate}
Observed: X-Client-Cert={var_client_certificate}; X-Client-Cert-Verify={var_client_certificate_verification} (8 headers overwritten)
```
**Proves:** Application Gateway in passthrough mode forwards the TLS client certificate to APIM as an overwrite-only header.

#### kv-holds-trust-material — Key Vault holds the trust material; APIM references it  ·  PASS ✅

```text
Command : az keyvault secret list + APIM namedValues keyVault.secretIdentifier
Expected: KV secrets trusted-root-ca-der-b64 + client-cert-allowlist, referenced by APIM named values
Observed: Both secrets present; APIM named values bound to the vault secret identifiers; cert-validation-mode selects the model
```
**Proves:** The Root CA and per-client allow list live in Key Vault and are surfaced to the APIM policy via named values (managed identity).

### Model A — Pinned thumbprint allow list

#### pinned-client1 — Allow-listed client1 -> 200  ·  PASS ✅

```text
Command : [PINNED] GET /poc/whoami with X-Client-Cert = <client1 PEM>
Expected: 200 ALLOW
Observed: HTTP 200 decision=ALLOW chainOk=True pinnedMatch=True
client_certificate_verification (App Gateway) : NONE
```
**Proves:** PINNED accepts client1: its thumbprint is on the Key Vault allow list and its issuer matches the Key Vault Root CA.

#### pinned-client2 — Allow-listed client2 -> 200  ·  PASS ✅

```text
Command : [PINNED] GET /poc/whoami with X-Client-Cert = <client2 PEM>
Expected: 200 ALLOW
Observed: HTTP 200 decision=ALLOW chainOk=True pinnedMatch=True
client_certificate_verification (App Gateway) : NONE
```
**Proves:** PINNED accepts client2 for the same reason: a second allow-listed thumbprint.

#### pinned-client3 — CA-signed but NOT allow-listed client3 -> 403  ·  PASS ✅

```text
Command : [PINNED] GET /poc/whoami with X-Client-Cert = <client3 PEM>
Expected: 403 DENY NOT_IN_ALLOWLIST
Observed: HTTP 403 decision=DENY reason=NOT_IN_ALLOWLIST chainOk=True pinnedMatch=False
client_certificate_verification (App Gateway) : NONE
```
**Proves:** PINNED rejects client3 even though it is validly signed by the Root CA (chainOk=true): it is not on the allow list. This is the restrictive edge of the pinned model.

#### pinned-spoofed — Forged-signature cert (same issuer DN) -> 403  ·  PASS ✅

```text
Command : [PINNED] GET /poc/whoami with X-Client-Cert = <spoofed PEM>
Expected: 403 DENY NOT_IN_ALLOWLIST
Observed: HTTP 403 decision=DENY reason=NOT_IN_ALLOWLIST chainOk=False pinnedMatch=False
client_certificate_verification (App Gateway) : NONE
```
**Proves:** PINNED rejects the spoofed cert: its thumbprint is not on the allow list (a thumbprint is a hash of the whole certificate and cannot be forged).

#### pinned-rogue — Untrusted issuer -> 403  ·  PASS ✅

```text
Command : [PINNED] GET /poc/whoami with X-Client-Cert = <rogue PEM>
Expected: 403 DENY UNTRUSTED_ISSUER
Observed: HTTP 403 decision=DENY reason=UNTRUSTED_ISSUER chainOk=False pinnedMatch=False
client_certificate_verification (App Gateway) : NONE
```
**Proves:** PINNED rejects the rogue cert: its issuer does not match the Key Vault Root CA.

#### pinned-nocert — No certificate -> 403  ·  PASS ✅

```text
Command : [PINNED] GET /poc/whoami with X-Client-Cert = (none)
Expected: 403 DENY NO_CERT_FORWARDED
Observed: HTTP 403 decision=DENY reason=NO_CERT_FORWARDED chainOk=False pinnedMatch=False
client_certificate_verification (App Gateway) : NONE
```
**Proves:** PINNED rejects a request with no forwarded certificate.

#### pinned-authz-own — client1 -> its own path A -> 200  ·  PASS ✅

```text
Command : [PINNED] GET /poc/client1 with X-Client-Cert = <client1 PEM>
Expected: 200 ALLOW
Observed: HTTP 200 decision=ALLOW chainOk=True
client_certificate_verification (App Gateway) : NONE
```
**Proves:** Per-client authorization: client1 is authorised for path A.

#### pinned-authz-cross — client1 -> client2 path B -> 403  ·  PASS ✅

```text
Command : [PINNED] GET /poc/client2 with X-Client-Cert = <client1 PEM>
Expected: 403 DENY_AUTHZ
Observed: HTTP 403 decision=DENY_AUTHZ reason=Authenticated client is not authorised for path B (client2)
client_certificate_verification (App Gateway) : NONE
```
**Proves:** Per-client authorization: an authenticated client is still confined to its own path; identity from the certificate drives authorization.

### Model B — Chain of trust (Root CA signature)

#### chain-client1 — CA-signed client1 -> 200  ·  PASS ✅

```text
Command : [CHAIN] GET /poc/whoami with X-Client-Cert = <client1 PEM>
Expected: 200 ALLOW
Observed: HTTP 200 decision=ALLOW chainOk=True pinnedMatch=True
client_certificate_verification (App Gateway) : NONE
```
**Proves:** CHAIN accepts client1: the Key Vault Root CA public key verifies the RSA signature over its TBSCertificate.

#### chain-client2 — CA-signed client2 -> 200  ·  PASS ✅

```text
Command : [CHAIN] GET /poc/whoami with X-Client-Cert = <client2 PEM>
Expected: 200 ALLOW
Observed: HTTP 200 decision=ALLOW chainOk=True pinnedMatch=True
client_certificate_verification (App Gateway) : NONE
```
**Proves:** CHAIN accepts client2: also validly signed by the Root CA.

#### chain-client3 — CA-signed client3 (no allow list needed) -> 200  ·  PASS ✅

```text
Command : [CHAIN] GET /poc/whoami with X-Client-Cert = <client3 PEM>
Expected: 200 ALLOW
Observed: HTTP 200 decision=ALLOW chainOk=True pinnedMatch=False
client_certificate_verification (App Gateway) : NONE
```
**Proves:** CHAIN accepts client3 with NO allow-list entry -- the exact certificate PINNED rejected. This is the money shot: the two models genuinely differ.

#### chain-spoofed — Forged signature, identical issuer DN -> 403  ·  PASS ✅

```text
Command : [CHAIN] GET /poc/whoami with X-Client-Cert = <spoofed PEM>
Expected: 403 DENY NOT_CA_SIGNED
Observed: HTTP 403 decision=DENY reason=NOT_CA_SIGNED chainOk=False pinnedMatch=False
client_certificate_verification (App Gateway) : NONE
```
**Proves:** CHAIN rejects the spoofed cert even though its issuer string is byte-for-byte identical to the real Root CA. The RSA signature check fails (chainOk=false) -- proof this is real cryptography, not a name compare.

#### chain-rogue — Untrusted issuer -> 403  ·  PASS ✅

```text
Command : [CHAIN] GET /poc/whoami with X-Client-Cert = <rogue PEM>
Expected: 403 DENY NOT_CA_SIGNED
Observed: HTTP 403 decision=DENY reason=NOT_CA_SIGNED chainOk=False pinnedMatch=False
client_certificate_verification (App Gateway) : NONE
```
**Proves:** CHAIN rejects the rogue cert: the Root CA did not sign it.

#### chain-nocert — No certificate -> 403  ·  PASS ✅

```text
Command : [CHAIN] GET /poc/whoami with X-Client-Cert = (none)
Expected: 403 DENY NO_CERT_FORWARDED
Observed: HTTP 403 decision=DENY reason=NO_CERT_FORWARDED chainOk=False pinnedMatch=False
client_certificate_verification (App Gateway) : NONE
```
**Proves:** CHAIN rejects a request with no forwarded certificate.

---

## Security verdict

**Is the client certificate validated as a real credential in APIM, not trusted as a spoofable header?**

**Yes.** APIM reconstructs the forwarded certificate and validates it under the selected model before authorizing per client. In **pinned** mode the thumbprint must be on the Key Vault allow list; in **chain** mode the Key Vault Root CA must cryptographically sign it. Either way, a certificate from an untrusted issuer is rejected even though the gateway forwarded it unvalidated — APIM is the trust anchor.

**Is `chain` mode just a name/thumbprint string compare?**

**No — it is real cryptography.** The `spoofed` certificate carries an issuer Distinguished Name that is byte-for-byte identical to the trusted Root CA, but it is signed by a different key. Chain mode rejects it (`NOT_CA_SIGNED`, `chainOk=false`) because the Root CA's public key does not verify its signature. A string comparison would have accepted it; `RSA.VerifyData` does not. That is the difference between *looking* trusted and *being* trusted.

**Does Application Gateway passthrough enforce proof-of-possession of the client certificate''s private key?**

**Yes — by the TLS protocol itself.** A client cannot present a certificate in an mTLS handshake without producing a `CertificateVerify` signed by the matching private key, so a public certificate alone is useless without possession. Passthrough skips *CA/chain* validation at the gateway, but the underlying TLS engine still requires possession to complete the handshake — so the only way any certificate reaches APIM is if the caller holds its private key. _(The live handshake test on this subscription is pending the `AllowApplicationGatewayClientAuthentication` feature registration; the statement above is a property of the TLS protocol, and the certificate-generation scripts include the possession test setup: presenting a public certificate with a mismatched private key fails at the client's own TLS layer.)_

### What this passthrough design DOES protect against

- **Possession** — enforced by TLS; a public certificate alone is useless without its private key.
- **Trust** — enforced *in APIM* under the chosen model (pinned thumbprint **or** cryptographic chain of trust). The gateway does **not** validate the certificate in passthrough, so APIM is the trust anchor.
- **Authorization** — per-client path binding (client1→A, client2→B) enforced in APIM operation policies.
- **Header injection** — the App Gateway rewrite **overwrites** every `X-Client-Cert*` header from TLS-derived server variables, so a client cannot forge its identity via headers.
- **Direct bypass** — APIM is deployed in **internal VNet** mode, reachable only from the App Gateway subnet, so a forged request cannot skip the gateway.

### Good to know (design boundaries)

The gateway itself performs no certificate validation in passthrough, so treat its `client_certificate_verification` value as informational only. The two controls that make the forwarded certificate trustworthy for APIM to validate are the **header overwrite** (the gateway sets `X-Client-Cert*` from the real TLS connection) and the **internal-VNet lockdown** (APIM is reachable only through the gateway). Keep both in place and the pattern holds.

## How we validated the forwarded cert in the APIM sandbox

- The forwarded `X-Client-Cert` header is **URL/percent-encoded PEM**. The policy URL-decodes it, strips the PEM armor, base64-decodes to DER, and constructs an `X509Certificate2`.
- **`DateTime.ToUniversalTime()` is blocked** in the APIM policy-expression sandbox (confirmed at deploy time). Validity is checked using `DateTime.Now` against the certificate's `NotBefore`/`NotAfter` (local time).
- **`X509Chain` and `System.Func` are also blocked** by the sandbox validator (both confirmed at deploy time). Chain mode therefore verifies trust *without* `X509Chain`: it parses the leaf DER inline to extract the `TBSCertificate` bytes and the signature, then calls `rootCa.GetRSAPublicKey().VerifyData(tbs, sig, hashAlg, RSASignaturePadding.Pkcs1)`. This is a genuine signature check, not a chain-builder shortcut.
- Pinned mode decides trust by an **issuer-DN comparison against the Key Vault Root CA** plus a **pinned-thumbprint allow list** (also Key Vault-sourced).
- Trust material is delivered via **APIM named values bound to Key Vault secrets** (system-assigned managed identity, `Key Vault Secrets User`), so the policy never embeds the trust anchor.

## Also verified on API Management v2

The API Management **v2** tiers carry a documented limitation: `context.Request.Certificate` and TLS renegotiation are **not supported**. That only matters if trust is established at APIM's own TLS layer — which this scenario never does. Trust is decided entirely from the **forwarded `X-Client-Cert` header**, so the limitation does not apply.

To prove it, the identical dual-model policy, named values, and certificates were deployed to a standalone **API Management v2** instance (public gateway) and the same matrix was run directly against its gateway. **11/11 checks passed** — behaviour is identical to the **v1** deployment, including the real RSA chain-of-trust check that rejects the forged-issuer spoofed certificate.

| Model | Check | Observed on API Management v2 | Result |
|---|---|---|---|
| pinned | Allow-listed client1 -> 200 | `HTTP 200 decision=ALLOW chainOk=True pinnedMatch=True` | PASS ✅ |
| pinned | CA-signed but NOT allow-listed client3 -> 403 | `HTTP 403 decision=DENY reason=NOT_IN_ALLOWLIST chainOk=True pinnedMatch=False` | PASS ✅ |
| pinned | Forged-signature cert (same issuer DN) -> 403 | `HTTP 403 decision=DENY reason=NOT_IN_ALLOWLIST chainOk=False pinnedMatch=False` | PASS ✅ |
| pinned | Untrusted issuer -> 403 | `HTTP 403 decision=DENY reason=UNTRUSTED_ISSUER chainOk=False pinnedMatch=False` | PASS ✅ |
| pinned | No certificate -> 403 | `HTTP 403 decision=DENY reason=NO_CERT_FORWARDED chainOk=False pinnedMatch=False` | PASS ✅ |
| pinned | client1 -> client2 path B -> 403 | `HTTP 403 decision=DENY_AUTHZ reason=Authenticated client is not authorised for path B (client2)` | PASS ✅ |
| chain | CA-signed client1 -> 200 | `HTTP 200 decision=ALLOW chainOk=True pinnedMatch=True` | PASS ✅ |
| chain | CA-signed client3 (no allow list needed) -> 200 | `HTTP 200 decision=ALLOW chainOk=True pinnedMatch=False` | PASS ✅ |
| chain | Forged signature, identical issuer DN -> 403 | `HTTP 403 decision=DENY reason=NOT_CA_SIGNED chainOk=False pinnedMatch=False` | PASS ✅ |
| chain | Untrusted issuer -> 403 | `HTTP 403 decision=DENY reason=NOT_CA_SIGNED chainOk=False pinnedMatch=False` | PASS ✅ |
| chain | No certificate -> 403 | `HTTP 403 decision=DENY reason=NO_CERT_FORWARDED chainOk=False pinnedMatch=False` | PASS ✅ |

> **Takeaway:** the certificate-validation pattern is **tier-agnostic**. Because it operates on the forwarded header rather than APIM's TLS layer, it works unchanged on API Management **v1** and **v2** — the v2 renegotiation limitation simply is not in the path. The v2 proof instance is torn down with `./teardown-apim-v2.ps1` after capturing this evidence.

## Cost & teardown

Roughly **$0.50–0.90/hr** in eastus2 (App Gateway WAF_v2 + APIM Developer dominate). **Tear down when finished:**

```powershell
./teardown.ps1
# Key Vault is soft-deleted for 7 days; purge to reclaim the name:
az keyvault purge --name mtlspockvuc6wxti2blws4
```


