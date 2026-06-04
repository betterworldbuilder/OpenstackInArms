#!/usr/bin/env python3
"""Local-only Mission Control server for the ARM OpenStack PoC."""

from __future__ import annotations

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import json
import os
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
HTML = ROOT / "mission-control.html"

STEPS = {
    "prereqs": ["bash", "scripts/00_check_prereqs.sh"],
    "bootstrap": ["bash", "scripts/01_bootstrap_arm_nodes.sh"],
    "inventory": [
        "python3",
        "scripts/02_generate_inventory.py",
        "--nodes",
        "nodes.txt",
        "--output",
        "multinode-arm.ini",
    ],
    "deploy": ["bash", "scripts/03_deploy_kolla_arm.sh"],
    "validate": ["bash", "scripts/04_validate_arm_openstack.sh"],
    "images": ["bash", "scripts/05_build_arm64_kolla_images.sh"],
}

ENV_KEYS = {
    "SSH_USER",
    "OPENSTACK_RELEASE",
    "VIP",
    "EXT_IFACE",
    "CIDR",
    "GW",
    "POOL_START",
    "POOL_END",
}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args: object) -> None:
        print(f"[mission-control] {self.address_string()} {fmt % args}")

    def _send(self, code: int, body: bytes, content_type: str) -> None:
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _json(self, code: int, payload: dict[str, object]) -> None:
        self._send(code, json.dumps(payload).encode("utf-8"), "application/json")

    def _payload(self) -> dict[str, object]:
        length = int(self.headers.get("Content-Length", "0"))
        if length == 0:
            return {}
        return json.loads(self.rfile.read(length).decode("utf-8"))

    def do_GET(self) -> None:
        if self.path not in ("/", "/mission-control.html"):
            self._json(404, {"error": "Not found"})
            return
        self._send(200, HTML.read_bytes(), "text/html; charset=utf-8")

    def do_POST(self) -> None:
        try:
            payload = self._payload()
            if self.path == "/api/save-nodes":
                self.save_nodes(payload)
            elif self.path == "/api/run":
                self.run_step(payload)
            else:
                self._json(404, {"error": "Not found"})
        except Exception as exc:  # noqa: BLE001
            self._json(500, {"error": str(exc)})

    def save_nodes(self, payload: dict[str, object]) -> None:
        content = str(payload.get("content", "")).strip()
        if not content:
            self._json(400, {"error": "nodes.txt content is empty"})
            return
        (ROOT / "nodes.txt").write_text(content + "\n", encoding="utf-8")
        self._json(200, {"output": "saved nodes.txt"})

    def run_step(self, payload: dict[str, object]) -> None:
        step = str(payload.get("step", ""))
        if step not in STEPS:
            self._json(400, {"error": f"Unknown step: {step}"})
            return

        env = os.environ.copy()
        env["NODE_LIST"] = "nodes.txt"
        env["INVENTORY"] = "multinode-arm.ini"
        for key, value in dict(payload.get("env", {})).items():
            if key in ENV_KEYS and value:
                env[key] = str(value)

        if step == "inventory" and env.get("SSH_USER"):
            command = [*STEPS[step], "--ansible-user", env["SSH_USER"]]
        else:
            command = STEPS[step]

        timeout = 7200 if step in {"deploy", "images"} else 1800
        result = subprocess.run(
            command,
            cwd=ROOT,
            env=env,
            text=True,
            capture_output=True,
            timeout=timeout,
            check=False,
        )
        output = (result.stdout or "") + (result.stderr or "")
        self._json(200, {"code": result.returncode, "output": output[-50000:]})


def main() -> int:
    port = int(os.environ.get("MISSION_CONTROL_PORT", "8787"))
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(f"Mission Control: http://127.0.0.1:{port}")
    server.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
