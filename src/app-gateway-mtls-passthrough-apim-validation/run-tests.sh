#!/usr/bin/env bash
# =====================================================================
# Evidence suite for the mTLS passthrough POC (Linux/macOS)
# Uses OpenSSL s_client as the mTLS client and writes certs/results.json.
# =====================================================================
set -uo pipefail

RESOURCE_GROUP="${RESOURCE_GROUP:-rg-appgw-passthrough-mtls-poc}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERT_DIR="$SCRIPT_DIR/certs"

[[ -f "$CERT_DIR/deploy-output.json" ]] || { echo "Run ./deploy-infra.sh first."; exit 1; }

read_json() { python3 -c "import json,sys;print(json.load(open('$1')).get('$2',''))"; }
IP="$(read_json "$CERT_DIR/deploy-output.json" appGatewayPublicIp)"
FRONTEND_HOST="$(read_json "$CERT_DIR/deploy-output.json" frontendHostName)"
APIM_NAME="$(read_json "$CERT_DIR/deploy-output.json" apimName)"
APIM_HOST="$APIM_NAME.azure-api.net"

echo "==> Target App Gateway: $IP (SNI $FRONTEND_HOST)"

RESULTS_FILE="$CERT_DIR/results.ndjson"; : > "$RESULTS_FILE"

# run_mtls <path> <cert|""> <key|""> <inject-headers-block|"">  -> sets OUT/ERR/STATUS/DECISION/CLIENT/VERIFY
run_mtls() {
  local path="$1" cert="$2" key="$3" inject="$4"
  local req; req=$(printf 'GET %s HTTP/1.1\r\nHost: %s\r\n%sConnection: close\r\n\r\n' "$path" "$FRONTEND_HOST" "$inject")
  local args=(s_client -connect "$IP:443" -servername "$FRONTEND_HOST" -CAfile "$CERT_DIR/appgw-server.crt" -quiet)
  [[ -n "$cert" ]] && args+=(-cert "$cert" -key "$key")
  OUT="$(printf '%s' "$req" | timeout 25 openssl "${args[@]}" 2>/tmp/mtls_err.txt || true)"
  ERR="$(cat /tmp/mtls_err.txt 2>/dev/null)"
  STATUS="$(printf '%s' "$OUT" | grep -a -m1 -oE 'HTTP/1\.[01] [0-9]{3}' | awk '{print $2}')"
  DECISION="$(printf '%s' "$OUT" | grep -a -i -m1 '^X-Evidence-Decision:' | sed 's/.*: *//; s/\r//')"
  CLIENT="$(printf '%s' "$OUT" | grep -a -i -m1 '^X-Evidence-Client:' | sed 's/.*: *//; s/\r//')"
  VERIFY="$(printf '%s' "$OUT" | grep -a -i -m1 '^X-Evidence-AppGw-Verify:' | sed 's/.*: *//; s/\r//')"
}

emit() { # id name command expected observed pass proves
  python3 - "$@" >> "$RESULTS_FILE" <<'PY'
import json,sys
a=sys.argv
print(json.dumps({"id":a[1],"name":a[2],"command":a[3],"expected":a[4],"observed":a[5],"pass":a[6]=="1","proves":a[7]}))
PY
}

pass_fail(){ [[ "$1" == "1" ]] && echo "PASS" || echo "FAIL"; }

echo "==================== EVIDENCE SUITE ===================="

# 0. connectivity
run_mtls "/status-0123456789abcdef" "" "" ""
p=$([[ "$STATUS" == "200" ]] && echo 1 || echo 0)
echo "[$(pass_fail $p)] 0-connectivity HTTP $STATUS"
emit "0-connectivity" "App Gateway -> APIM connectivity" "openssl s_client ... GET /status-0123456789abcdef" "200" "HTTP $STATUS" "$p" "Passthrough allows the connection and routes to internal APIM."

# 1 possession positive
run_mtls "/poc/client1" "$CERT_DIR/client1.crt" "$CERT_DIR/client1.key" ""
p=$([[ "$STATUS" == "200" && "$DECISION" == "ALLOW" ]] && echo 1 || echo 0)
echo "[$(pass_fail $p)] 1-possession-positive HTTP $STATUS $DECISION verify=$VERIFY"
emit "1-possession-positive" "Possession positive: owns cert1" "openssl s_client -cert client1.crt -key client1.key GET /poc/client1" "200 ALLOW" "HTTP $STATUS $DECISION verify=$VERIFY" "$p" "A client that holds the private key completes mTLS; cert forwarded and validated."

# 1b possession negative (cert1 + key2)
run_mtls "/poc/client1" "$CERT_DIR/client1.crt" "$CERT_DIR/client2.key" ""
if echo "$ERR" | grep -qi 'key values mismatch' || [[ -z "$STATUS" ]]; then p=1; else p=0; fi
echo "[$(pass_fail $p)] 1b-possession-negative status='$STATUS' err~mismatch"
emit "1b-possession-negative" "Possession negative: cert1 without key1" "openssl s_client -cert client1.crt -key client2.key" "cannot present cert1 without key1" "status='$STATUS' mismatch-detected=$p" "$p" "Possession is enforced by TLS: no cert without its private key."

# 2 positive client2
run_mtls "/poc/client2" "$CERT_DIR/client2.crt" "$CERT_DIR/client2.key" ""
p=$([[ "$STATUS" == "200" && "$DECISION" == "ALLOW" ]] && echo 1 || echo 0)
echo "[$(pass_fail $p)] 2-positive-client2 HTTP $STATUS $DECISION client=$CLIENT"
emit "2-positive-client2" "Positive: client2 -> path B" "openssl s_client -cert client2.crt -key client2.key GET /poc/client2" "200 ALLOW client2" "HTTP $STATUS $DECISION client=$CLIENT" "$p" "Second client, own cert, own path: allowed."

# 3 authz cross
run_mtls "/poc/client2" "$CERT_DIR/client1.crt" "$CERT_DIR/client1.key" ""
p=$([[ "$STATUS" == "403" && "$DECISION" == "DENY_AUTHZ" ]] && echo 1 || echo 0)
echo "[$(pass_fail $p)] 3-authz-cross HTTP $STATUS $DECISION"
emit "3-authz-cross" "Per-client authz: client1 -> path B" "openssl s_client -cert client1.crt -key client1.key GET /poc/client2" "403 DENY_AUTHZ" "HTTP $STATUS $DECISION" "$p" "Trusted client rejected from another client's path."

# 4 trust rogue
run_mtls "/poc/client1" "$CERT_DIR/rogue.crt" "$CERT_DIR/rogue.key" ""
p=$([[ "$STATUS" == "403" && "$DECISION" == "DENY" ]] && echo 1 || echo 0)
echo "[$(pass_fail $p)] 4-trust-rogue HTTP $STATUS $DECISION verify=$VERIFY"
emit "4-trust-rogue" "Trust at APIM: rogue untrusted issuer" "openssl s_client -cert rogue.crt -key rogue.key GET /poc/client1" "403 DENY" "HTTP $STATUS $DECISION verify=$VERIFY" "$p" "Gateway forwards rogue cert; APIM rejects as untrusted."

# 5 no cert
run_mtls "/poc/client1" "" "" ""
p=$([[ "$STATUS" == "403" && "$DECISION" == "DENY" ]] && echo 1 || echo 0)
echo "[$(pass_fail $p)] 5-no-cert HTTP $STATUS $DECISION verify=$VERIFY"
emit "5-no-cert" "No certificate presented" "openssl s_client (no -cert) GET /poc/client1" "403 DENY NO_CERT" "HTTP $STATUS $DECISION verify=$VERIFY" "$p" "Passthrough completes with no cert; APIM rejects."

# 6b-i injection no cert
CLIENT1_ENC="$(python3 -c "import urllib.parse;print(urllib.parse.quote(open('$CERT_DIR/client1.crt').read()))")"
INJECT=$(printf 'X-Client-Cert: %s\r\nX-Client-Cert-Verify: SUCCESS\r\n' "$CLIENT1_ENC")
run_mtls "/poc/client1" "" "" "$INJECT"
p=$([[ "$STATUS" == "403" && "$VERIFY" != "SUCCESS" ]] && echo 1 || echo 0)
echo "[$(pass_fail $p)] 6b-inject-nocert HTTP $STATUS $DECISION verify=$VERIFY"
emit "6b-inject-nocert" "Header injection (no cert, forged headers)" "openssl s_client (no -cert) -H X-Client-Cert:<pem> -H X-Client-Cert-Verify:SUCCESS" "403 DENY (headers overwritten)" "HTTP $STATUS $DECISION verify=$VERIFY" "$p" "Gateway overwrites cert headers from TLS server variables; forged values discarded."

# 6b-ii injection override with valid cert
ROGUE_ENC="$(python3 -c "import urllib.parse;print(urllib.parse.quote(open('$CERT_DIR/rogue.crt').read()))")"
INJECT=$(printf 'X-Client-Cert: %s\r\n' "$ROGUE_ENC")
run_mtls "/poc/client1" "$CERT_DIR/client1.crt" "$CERT_DIR/client1.key" "$INJECT"
p=$([[ "$STATUS" == "200" && "$CLIENT" == "client1" ]] && echo 1 || echo 0)
echo "[$(pass_fail $p)] 6b-inject-override HTTP $STATUS $DECISION client=$CLIENT"
emit "6b-inject-override" "Header injection (valid cert + forged rogue header)" "openssl s_client -cert client1.crt -key client1.key -H X-Client-Cert:<rogue pem>" "200 ALLOW client1" "HTTP $STATUS $DECISION client=$CLIENT" "$p" "Real TLS cert overrides forged header; identity cannot be swapped."

# 6a direct bypass
CODE="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 -H 'X-Client-Cert: FORGED' -H 'X-Client-Cert-Verify: SUCCESS' "https://$APIM_HOST/poc/client1" 2>/dev/null || echo 'conn-failed')"
if [[ "$CODE" != "200" ]]; then p=1; else p=0; fi
echo "[$(pass_fail $p)] 6a-direct-bypass result=$CODE"
emit "6a-direct-bypass" "Direct-to-APIM bypass with forged header" "curl https://$APIM_HOST/poc/client1 -H X-Client-Cert:FORGED" "Blocked (internal VNet only)" "result=$CODE" "$p" "APIM is private; the forged request never reaches it."

# 7 WAF retained
WAF="$(az network application-gateway waf-policy list -g "$RESOURCE_GROUP" --query "[0].{s:policySettings.state,m:policySettings.mode}" -o json 2>/dev/null)"
STATE="$(echo "$WAF" | python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('s',''))" 2>/dev/null)"
MODE="$(echo "$WAF" | python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('m',''))" 2>/dev/null)"
p=$([[ "$STATE" == "Enabled" && "$MODE" == "Prevention" ]] && echo 1 || echo 0)
echo "[$(pass_fail $p)] 7-waf-retained state=$STATE mode=$MODE"
emit "7-waf-retained" "WAF_v2 retained (Prevention)" "az network application-gateway waf-policy list" "Enabled + Prevention" "state=$STATE mode=$MODE" "$p" "Azure WAF stays enabled in Prevention mode."

# Assemble results.json
python3 - "$RESULTS_FILE" "$CERT_DIR/results.json" "$RESOURCE_GROUP" "$IP" "$FRONTEND_HOST" "$APIM_NAME" <<'PY'
import json,sys,datetime
rows=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
out={"generatedUtc":datetime.datetime.utcnow().isoformat()+"Z","resourceGroup":sys.argv[3],
     "appGatewayPublicIp":sys.argv[4],"frontendHostName":sys.argv[5],"apimName":sys.argv[6],
     "total":len(rows),"passed":sum(1 for r in rows if r["pass"]),"results":rows}
json.dump(out,open(sys.argv[2],"w"),indent=2)
print(f"==> {out['passed']}/{out['total']} scenarios passed. Results: {sys.argv[2]}")
PY
