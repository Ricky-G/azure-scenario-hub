import os
from datetime import datetime, timezone

import requests
from flask import Flask, jsonify, render_template

app = Flask(__name__)

NAMESPACES = os.environ.get(
    "NAMESPACES",
    "egress-team-alpha,egress-team-bravo,egress-team-charlie,egress-team-delta,egress-team-echo",
).split(",")

SERVICE_NAME = os.environ.get("SERVICE_NAME", "egress-checker")
SERVICE_PORT = os.environ.get("SERVICE_PORT", "8080")

# Cluster network context (injected via env vars in the manifest)
CLUSTER_INFO = {
    "nodeSubnet": os.environ.get("NODE_SUBNET", "10.224.0.0/16"),
    "podCidr": os.environ.get("POD_CIDR", "192.168.0.0/16"),
    "serviceCidr": os.environ.get("SERVICE_CIDR", "10.0.0.0/16"),
    "networkPlugin": os.environ.get("NETWORK_PLUGIN", "Azure CNI Overlay"),
    "gatewayPrefixSize": os.environ.get("GATEWAY_PREFIX_SIZE", "/28"),
}

# Namespace-to-egress-prefix mapping (injected via env var, format: ns1=cidr1,ns2=cidr2)
_raw_prefixes = os.environ.get("EGRESS_PREFIXES", "")
EGRESS_PREFIXES = {}
if _raw_prefixes:
    for entry in _raw_prefixes.split(","):
        if "=" in entry:
            ns, prefix = entry.split("=", 1)
            EGRESS_PREFIXES[ns.strip()] = prefix.strip()


@app.route("/")
def index():
    return render_template("index.html")


@app.route("/api/status")
def status():
    results = []
    for ns in NAMESPACES:
        url = f"http://{SERVICE_NAME}.{ns}.svc.cluster.local:{SERVICE_PORT}/"
        try:
            resp = requests.get(url, timeout=3)
            resp.raise_for_status()
            data = resp.json()
            results.append(
                {
                    "namespace": ns,
                    "egress_ip": data.get("egress_ip", "unknown"),
                    "egress_prefix": EGRESS_PREFIXES.get(ns, "unknown"),
                    "timestamp": data.get("timestamp"),
                    "status": "ok",
                }
            )
        except Exception:
            results.append(
                {
                    "namespace": ns,
                    "egress_ip": None,
                    "egress_prefix": EGRESS_PREFIXES.get(ns, "unknown"),
                    "timestamp": datetime.now(timezone.utc).isoformat(),
                    "status": "error",
                }
            )
    return jsonify(results=results, clusterInfo=CLUSTER_INFO)


@app.route("/health")
def health():
    return "ok", 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
