import os
import threading
import time
from datetime import datetime, timezone

import requests
from flask import Flask, jsonify

app = Flask(__name__)

NAMESPACE = os.environ.get("POD_NAMESPACE", "unknown")
IP_CHECK_URL = "https://api.ipify.org?format=json"
CHECK_INTERVAL = 10

_state = {"egress_ip": "pending", "timestamp": None, "error": None}
_lock = threading.Lock()


def check_egress_ip():
    while True:
        try:
            resp = requests.get(IP_CHECK_URL, timeout=5)
            resp.raise_for_status()
            ip = resp.json().get("ip", "unknown")
            with _lock:
                _state["egress_ip"] = ip
                _state["timestamp"] = datetime.now(timezone.utc).isoformat()
                _state["error"] = None
        except Exception as e:
            with _lock:
                _state["error"] = str(e)
                _state["timestamp"] = datetime.now(timezone.utc).isoformat()
        time.sleep(CHECK_INTERVAL)


@app.route("/")
def index():
    with _lock:
        return jsonify(
            namespace=NAMESPACE,
            egress_ip=_state["egress_ip"],
            timestamp=_state["timestamp"],
            error=_state["error"],
        )


@app.route("/health")
def health():
    return "ok", 200


# Start background thread at import time (works with gunicorn)
_bg = threading.Thread(target=check_egress_ip, daemon=True)
_bg.start()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
