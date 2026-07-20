"""
The Windows "server". Exposes POST /send so you (or any other webserver) can ping it
to fire off an iMessage through the connected iPhone.

Run it:   python server.py
Then:     curl -X POST http://localhost:5000/send -H "Content-Type: application/json" \
                -H "X-Api-Key: change-me" -d "{\"to\":\"Person X\",\"message\":\"hi\"}"

Sends are serialized with a lock because one iPhone can only do one UI flow at a time.
"""

from __future__ import annotations

import os
import threading
from flask import Flask, request, jsonify, send_from_directory

from send_imessage import send_imessage

# Serve index.html (the web UI) from this same folder.
HERE = os.path.dirname(os.path.abspath(__file__))
app = Flask(__name__)


@app.get("/")
def home():
    return send_from_directory(HERE, "index.html")

# Simple shared-secret so randoms can't drive your phone. Set API_KEY in the env.
API_KEY = os.environ.get("API_KEY", "change-me")

# One iPhone = one UI action at a time. Queue requests behind this lock.
_phone_lock = threading.Lock()


@app.get("/health")
def health():
    return jsonify(status="ok")


@app.post("/send")
def send():
    if request.headers.get("X-Api-Key") != API_KEY:
        return jsonify(error="unauthorized"), 401

    data = request.get_json(silent=True) or {}
    recipient = (data.get("to") or "").strip()
    message = (data.get("message") or "").strip()
    if not recipient or not message:
        return jsonify(error="'to' and 'message' are required"), 400

    # Only one send at a time; others wait their turn.
    with _phone_lock:
        try:
            send_imessage(recipient, message)
        except Exception as e:  # noqa: BLE001 - report failures back to the caller
            return jsonify(error=str(e)), 500

    return jsonify(status="sent", to=recipient)


if __name__ == "__main__":
    # 0.0.0.0 so another machine on your network (or an ngrok tunnel) can reach it.
    # PORT is overridable — on macOS, port 5000 is taken by AirPlay Receiver.
    port = int(os.environ.get("PORT", "5000"))
    app.run(host="0.0.0.0", port=port)
