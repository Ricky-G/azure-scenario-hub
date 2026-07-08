#!/usr/bin/env bash
# =====================================================================
# Generate the certificate set for the mTLS passthrough POC (Linux/macOS)
# =====================================================================
set -euo pipefail

FRONTEND_HOST="${1:-api.mtls-poc.local}"
PFX_PASSWORD="${PFX_PASSWORD:-Poc-$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERT_DIR="$SCRIPT_DIR/certs"

command -v openssl >/dev/null 2>&1 || { echo "openssl not found"; exit 1; }

rm -rf "$CERT_DIR"; mkdir -p "$CERT_DIR"; cd "$CERT_DIR"

cat > client_ext.cnf <<'EOF'
basicConstraints = CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth
subjectKeyIdentifier = hash
EOF

echo "==> Generating trusted Root CA..."
openssl genrsa -out rootCA.key 4096 2>/dev/null
openssl req -x509 -new -nodes -key rootCA.key -sha256 -days 3650 -out rootCA.crt \
  -subj "/CN=mTLS POC Root CA/O=AzureScenarioHub/C=US" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign"

for c in client1 client2 client3; do
  echo "==> Generating $c (signed by trusted Root CA)..."
  openssl genrsa -out "$c.key" 2048 2>/dev/null
  openssl req -new -key "$c.key" -out "$c.csr" -subj "/CN=$c.mtls-poc.local/O=Legacy Client $c/C=US"
  openssl x509 -req -in "$c.csr" -CA rootCA.crt -CAkey rootCA.key -CAcreateserial \
    -out "$c.crt" -days 825 -sha256 -extfile client_ext.cnf 2>/dev/null
done

echo "==> Generating ROGUE CA + rogue client (untrusted issuer)..."
openssl genrsa -out rogueCA.key 4096 2>/dev/null
openssl req -x509 -new -nodes -key rogueCA.key -sha256 -days 3650 -out rogueCA.crt \
  -subj "/CN=Rogue Untrusted CA/O=RogueCorp/C=US" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign"
openssl genrsa -out rogue.key 2048 2>/dev/null
openssl req -new -key rogue.key -out rogue.csr -subj "/CN=rogue.mtls-poc.local/O=Rogue Client/C=US"
openssl x509 -req -in rogue.csr -CA rogueCA.crt -CAkey rogueCA.key -CAcreateserial \
  -out rogue.crt -days 825 -sha256 -extfile client_ext.cnf 2>/dev/null

# SPOOFED issuer: a DIFFERENT CA key that copies the trusted Root CA's exact
# subject DN. Its leaf has an identical issuer *string* to a genuine cert but a
# signature the real Root CA never produced -- the cert that separates a
# name-compare (would ACCEPT) from real signature verification (chain REJECTS).
echo "==> Generating SPOOFED-issuer client (same issuer DN, wrong key)..."
openssl genrsa -out spoofCA.key 4096 2>/dev/null
openssl req -x509 -new -nodes -key spoofCA.key -sha256 -days 3650 -out spoofCA.crt \
  -subj "/CN=mTLS POC Root CA/O=AzureScenarioHub/C=US" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign"
openssl genrsa -out spoofed.key 2048 2>/dev/null
openssl req -new -key spoofed.key -out spoofed.csr -subj "/CN=client1.mtls-poc.local/O=Legacy Client client1/C=US"
openssl x509 -req -in spoofed.csr -CA spoofCA.crt -CAkey spoofCA.key -CAcreateserial \
  -out spoofed.crt -days 825 -sha256 -extfile client_ext.cnf 2>/dev/null

echo "==> Generating App Gateway server cert (CN=$FRONTEND_HOST)..."
openssl genrsa -out appgw-server.key 2048 2>/dev/null
openssl req -x509 -new -nodes -key appgw-server.key -sha256 -days 825 -out appgw-server.crt \
  -subj "/CN=$FRONTEND_HOST/O=AppGw POC/C=US" \
  -addext "subjectAltName=DNS:$FRONTEND_HOST" \
  -addext "keyUsage=critical,digitalSignature,keyEncipherment" \
  -addext "extendedKeyUsage=serverAuth" \
  -addext "basicConstraints=CA:FALSE"
# Modern PKCS#12 encoding (AES-256 / PBKDF2 / SHA-256). Do NOT use the legacy
# PBE-SHA1-3DES flags: Application Gateway runs on OpenSSL 3.x and cannot load
# legacy SHA1-3DES PFX files without the legacy provider.
openssl pkcs12 -export -out appgw-server.pfx -inkey appgw-server.key -in appgw-server.crt \
  -passout "pass:$PFX_PASSWORD"

openssl x509 -in rootCA.crt -outform DER -out rootCA.der

thumb() { openssl x509 -in "$1" -noout -fingerprint -sha1 | sed 's/.*=//; s/://g' | tr '[:lower:]' '[:upper:]'; }
TP1="$(thumb client1.crt)"; TP2="$(thumb client2.crt)"; TP3="$(thumb client3.crt)"; TPR="$(thumb rogue.crt)"; TPS="$(thumb spoofed.crt)"
B64() { base64 -w0 "$1" 2>/dev/null || base64 "$1" | tr -d '\n'; }
PFX_B64="$(B64 appgw-server.pfx)"; ROOT_B64="$(B64 rootCA.der)"; ROOTPEM_B64="$(B64 rootCA.crt)"
# client3 is CA-signed but deliberately NOT allow-listed: the discriminator
# that proves pinned mode (403) differs from chain mode (200).
ALLOWLIST="client1:$TP1|client2:$TP2"

cat > manifest.json <<EOF
{
  "frontendHostName": "$FRONTEND_HOST",
  "serverCertPassword": "$PFX_PASSWORD",
  "serverCertPfxB64": "$PFX_B64",
  "trustedRootCaDerB64": "$ROOT_B64",
  "rootCaCertB64": "$ROOTPEM_B64",
  "client1Thumbprint": "$TP1",
  "client2Thumbprint": "$TP2",
  "client3Thumbprint": "$TP3",
  "rogueThumbprint": "$TPR",
  "spoofedThumbprint": "$TPS",
  "clientCertAllowlist": "$ALLOWLIST"
}
EOF

# Shell-sourceable copy for deploy-infra.sh
cat > manifest.env <<EOF
FRONTEND_HOST='$FRONTEND_HOST'
SERVER_CERT_PASSWORD='$PFX_PASSWORD'
SERVER_CERT_PFX_B64='$PFX_B64'
TRUSTED_ROOT_CA_DER_B64='$ROOT_B64'
ROOT_CA_CERT_B64='$ROOTPEM_B64'
CLIENT1_THUMBPRINT='$TP1'
CLIENT2_THUMBPRINT='$TP2'
CLIENT3_THUMBPRINT='$TP3'
ROGUE_THUMBPRINT='$TPR'
SPOOFED_THUMBPRINT='$TPS'
CLIENT_CERT_ALLOWLIST='$ALLOWLIST'
EOF

echo ""
echo "==> Certificate set generated."
echo "    client1 thumbprint : $TP1 (allow-listed)"
echo "    client2 thumbprint : $TP2 (allow-listed)"
echo "    client3 thumbprint : $TP3 (CA-signed, NOT allow-listed)"
echo "    rogue   thumbprint : $TPR (untrusted issuer)"
echo "    spoofed thumbprint : $TPS (same issuer DN, forged signature)"
