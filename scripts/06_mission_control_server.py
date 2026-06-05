#!/usr/bin/env python3
"""Local-only Mission Control server for the ARM OpenStack PoC."""

from __future__ import annotations

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
import errno
import ipaddress
import json
import os
import socket
import subprocess
import sys
import shutil


ROOT = Path(__file__).resolve().parents[1]
HTML = ROOT / "mission-control.html"

STEPS = {
    "prereqs": ["bash", "scripts/00_check_prereqs.sh"],
    "bootstrap": ["bash", "scripts/01_bootstrap_cloud_nodes.sh"],
    "inventory": [
        "python3",
        "scripts/02_generate_inventory.py",
        "--nodes",
        "nodes.txt",
        "--output",
        "multinode-arm.ini",
    ],
    "deploy": ["bash", "scripts/03_deploy_kolla_arm.sh"],
    "deploy_genestack": ["bash", "scripts/03_deploy_genestack_arm.sh"],
    "validate": ["bash", "scripts/04_validate_arm_openstack.sh"],
    "validate_genestack": ["bash", "scripts/04_validate_genestack_arm.sh"],
    "images": ["bash", "scripts/05_build_arm64_kolla_images.sh"],
    "images_genestack": ["bash", "scripts/05_check_genestack_images.sh"],
}

ENV_KEYS = {
    "SSH_USER",
    "OPENSTACK_RELEASE",
    "VIP",
    "EXT_IFACE",
    "CIDR",
    "DEPLOY_TOOL",
    "GENESTACK_CONFIRM_DEPLOY",
    "GENESTACK_MODE",
    "GENESTACK_OPENRC",
    "GENESTACK_PATH",
    "GENESTACK_REPO",
    "KUBECONFIG",
    "OPENRC",
    "GW",
    "POOL_START",
    "POOL_END",
}


def local_lan_networks() -> list[ipaddress.IPv4Network]:
    networks: list[ipaddress.IPv4Network] = []

    if shutil.which("powershell.exe"):
        ps_script = (
            "Get-NetIPAddress -AddressFamily IPv4 | "
            "Where-Object { "
            "$_.IPAddress -notmatch '^(127|169\\.254)\\.' -and "
            "$_.PrefixLength -le 30 -and "
            "$_.InterfaceAlias -notmatch '(vEthernet|WSL|Docker|Loopback|Hyper-V|Npcap)' "
            "} | "
            "ForEach-Object { \"$($_.IPAddress)/$($_.PrefixLength)\" }"
        )
        result = subprocess.run(
            ["powershell.exe", "-NoProfile", "-Command", ps_script],
            text=True,
            capture_output=True,
            check=False,
            timeout=8,
        )
        for line in result.stdout.splitlines():
            value = line.strip().replace("\r", "")
            if not value:
                continue
            try:
                networks.append(ipaddress.ip_interface(value).network)
            except ValueError:
                continue

    if not networks and shutil.which("ip"):
        result = subprocess.run(
            ["ip", "-o", "-4", "addr", "show", "scope", "global"],
            text=True,
            capture_output=True,
            check=False,
            timeout=5,
        )
        for line in result.stdout.splitlines():
            parts = line.split()
            if "inet" not in parts:
                continue
            value = parts[parts.index("inet") + 1]
            try:
                networks.append(ipaddress.ip_interface(value).network)
            except ValueError:
                continue

    seen: set[str] = set()
    unique = []
    for network in networks:
        key = str(network)
        if key in seen:
            continue
        seen.add(key)
        unique.append(network)
    return unique


def resolve_endpoint_name(ip: str) -> tuple[str, str]:
    for hosts_path in (
        Path("/etc/hosts"),
        Path("/mnt/c/Windows/System32/drivers/etc/hosts"),
        Path(r"C:\Windows\System32\drivers\etc\hosts"),
    ):
        if not hosts_path.exists():
            continue
        try:
            for line in hosts_path.read_text(errors="ignore").splitlines():
                clean = line.split("#", 1)[0].strip()
                if not clean:
                    continue
                parts = clean.split()
                if len(parts) >= 2 and parts[0] == ip:
                    return parts[1].strip("."), "hosts"
        except OSError:
            continue

    try:
        name = socket.gethostbyaddr(ip)[0].strip(".")
        if name:
            return name, "reverse-dns"
    except (OSError, socket.herror):
        pass

    if shutil.which("powershell.exe"):
        scripts = [
            (
                f"$r = Resolve-DnsName -Name '{ip}' -ErrorAction SilentlyContinue; "
                "$r | Where-Object { $_.NameHost } | Select-Object -First 1 -ExpandProperty NameHost"
            ),
            (
                "$cache = Get-DnsClientCache -ErrorAction SilentlyContinue; "
                f"$cache | Where-Object {{ $_.Data -eq '{ip}' -or ($_.Data -is [array] -and $_.Data -contains '{ip}') }} "
                "| Select-Object -First 1 -ExpandProperty Entry"
            ),
        ]
        for ps_script in scripts:
            try:
                result = subprocess.run(
                    ["powershell.exe", "-NoProfile", "-Command", ps_script],
                    text=True,
                    capture_output=True,
                    check=False,
                    timeout=3,
                )
            except subprocess.TimeoutExpired:
                continue
            name = result.stdout.strip().replace("\r", "").strip(".")
            if name:
                return name, "windows-dns"

    nbtstat = shutil.which("nbtstat.exe") or shutil.which("nbtstat")
    if nbtstat:
        try:
            result = subprocess.run(
                [nbtstat, "-A", ip],
                text=True,
                capture_output=True,
                check=False,
                timeout=4,
            )
        except subprocess.TimeoutExpired:
            return "unknown", "none"
        for line in result.stdout.splitlines():
            clean = " ".join(line.strip().split())
            if "<00>" not in clean or "UNIQUE" not in clean:
                continue
            name = clean.split("<00>", 1)[0].strip()
            if name and not name.startswith("__"):
                return name, "netbios"

    return "unknown", "none"


def resolve_endpoint_names(ips: list[str]) -> dict[str, tuple[str, str]]:
    resolved: dict[str, tuple[str, str]] = {}
    wanted = set(ips)

    for hosts_path in (
        Path("/etc/hosts"),
        Path("/mnt/c/Windows/System32/drivers/etc/hosts"),
        Path(r"C:\Windows\System32\drivers\etc\hosts"),
    ):
        if not hosts_path.exists():
            continue
        try:
            for line in hosts_path.read_text(errors="ignore").splitlines():
                clean = line.split("#", 1)[0].strip()
                if not clean:
                    continue
                parts = clean.split()
                if len(parts) >= 2 and parts[0] in wanted and parts[0] not in resolved:
                    resolved[parts[0]] = (parts[1].strip("."), "hosts")
        except OSError:
            continue

    for ip in ips:
        if ip in resolved:
            continue
        try:
            name = socket.gethostbyaddr(ip)[0].strip(".")
            if name:
                resolved[ip] = (name, "reverse-dns")
        except (OSError, socket.herror):
            pass

    pending = [ip for ip in ips if ip not in resolved]
    if pending and shutil.which("powershell.exe"):
        ip_json = json.dumps(pending)
        ps_script = f"""
$ips = @'
{ip_json}
'@ | ConvertFrom-Json
foreach ($ip in $ips) {{
  $name = $null
  try {{
    $name = Resolve-DnsName -Name $ip -Type PTR -QuickTimeout -ErrorAction SilentlyContinue |
      Where-Object {{ $_.NameHost }} |
      Select-Object -First 1 -ExpandProperty NameHost
  }} catch {{}}
  if (-not $name) {{
    try {{
      $name = Resolve-DnsName -Name $ip -QuickTimeout -ErrorAction SilentlyContinue |
        Where-Object {{ $_.NameHost }} |
        Select-Object -First 1 -ExpandProperty NameHost
    }} catch {{}}
  }}
  if ($name) {{ "$ip`t$name" }}
}}
"""
        try:
            result = subprocess.run(
                ["powershell.exe", "-NoProfile", "-Command", ps_script],
                text=True,
                capture_output=True,
                check=False,
                timeout=max(8, min(30, len(pending) * 3)),
            )
            for line in result.stdout.splitlines():
                if "\t" not in line:
                    continue
                ip, name = line.split("\t", 1)
                ip = ip.strip()
                name = name.strip().replace("\r", "").strip(".")
                if ip in wanted and name and ip not in resolved:
                    resolved[ip] = (name, "windows-dns")
        except subprocess.TimeoutExpired:
            pass

    return resolved


def classify_endpoint(row: dict[str, object]) -> dict[str, str]:
    hostname = str(row.get("hostname", ""))
    model = str(row.get("model", ""))
    os_name = str(row.get("os", ""))
    cpu = str(row.get("cpu", ""))
    arch = str(row.get("arch", "")).lower()
    text = f"{hostname} {model} {os_name} {cpu} {arch}".lower()
    ssh_ok = bool(row.get("ssh"))
    is_arm = arch in {"aarch64", "arm64", "armv7l"}
    is_x86 = arch in {"x86_64", "amd64", "i386", "i686"}
    is_pi = any(token in text for token in ("raspberry", "raspberry pi", "cortex-a76", "bcm2712"))
    is_consumer = any(
        token in text
        for token in ("router", "gateway", "android", "phone", "speaker", "wiim", "denon", "sonos", "printer", "chromecast", "tv", "roku", "iphone", "ipad")
    )

    if ssh_ok and is_pi:
        return {
            "endpoint_type": "Raspberry Pi with SSH",
            "visibility": "Full details via SSH",
            "console_method": "ssh + serial",
            "openstack_role": "compute",
        }
    if ssh_ok and is_arm:
        return {
            "endpoint_type": "ARM server with SSH",
            "visibility": "Full details via SSH",
            "console_method": "ssh + serial or bmc/ipmi",
            "openstack_role": "compute",
        }
    if ssh_ok and is_x86:
        return {
            "endpoint_type": "x86 server with SSH",
            "visibility": "Full details via SSH",
            "console_method": "ssh, vnc, or bmc/ipmi",
            "openstack_role": "compute",
        }
    if is_consumer:
        return {
            "endpoint_type": "Router / phone / speaker",
            "visibility": "Usually no hardware facts",
            "console_method": "none",
            "openstack_role": "exclude",
        }
    return {
        "endpoint_type": "SSH-closed endpoint",
        "visibility": "Limited to IP/hostname/port scan",
        "console_method": "none or unknown",
        "openstack_role": "exclude",
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
            elif self.path == "/api/scan-lan":
                self.scan_lan(payload)
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

    def scan_lan(self, payload: dict[str, object]) -> None:
        cidr = str(payload.get("cidr", "")).strip()
        ssh_user = str(payload.get("sshUser", "ubuntu")).strip() or "ubuntu"
        if not cidr or cidr.lower() == "auto":
            networks = local_lan_networks()
            if not networks:
                self._json(400, {"error": "Could not auto-detect a LAN CIDR. Enter one manually, for example 192.168.10.0/24."})
                return
        else:
            networks = [ipaddress.ip_network(cidr, strict=False)]

        hosts = sorted(
            {str(ip) for network in networks for ip in network.hosts()},
            key=lambda value: tuple(int(part) for part in value.split(".")),
        )
        if len(hosts) > 4096:
            cidrs = ", ".join(str(network) for network in networks)
            self._json(400, {"error": f"Auto-detected scan is too large ({len(hosts)} IPs: {cidrs}). Enter a smaller CIDR like 192.168.10.0/24."})
            return

        def probe(ip: str) -> dict[str, object] | None:
            ping = subprocess.run(
                ["ping", "-c", "1", "-W", "1", ip],
                text=True,
                capture_output=True,
                check=False,
            )
            if ping.returncode != 0:
                return None

            ssh = subprocess.run(
                [
                    "ssh",
                    "-o",
                    "BatchMode=yes",
                    "-o",
                    "ConnectTimeout=2",
                    "-o",
                    "StrictHostKeyChecking=accept-new",
                    f"{ssh_user}@{ip}",
                    "\n".join(
                        [
                            "printf 'HOSTNAME=%s\\n' \"$(hostname 2>/dev/null || echo unknown)\"",
                            "printf 'ARCH=%s\\n' \"$(uname -m 2>/dev/null || echo unknown)\"",
                            "if [ -r /etc/os-release ]; then . /etc/os-release; printf 'OS=%s\\n' \"${PRETTY_NAME:-unknown}\"; else printf 'OS=unknown\\n'; fi",
                            "if [ -r /proc/device-tree/model ]; then tr -d '\\0' </proc/device-tree/model | sed 's/^/MODEL=/'; printf '\\n'; else printf 'MODEL=unknown\\n'; fi",
                            "printf 'CPU=%s\\n' \"$(lscpu 2>/dev/null | awk -F: '/Model name|BIOS Model name|Hardware/ {gsub(/^[ \\t]+/, \"\", $2); print $2; exit}' || true)\"",
                            "printf 'CORES=%s\\n' \"$(nproc 2>/dev/null || echo unknown)\"",
                            "printf 'RAM=%sGB\\n' \"$(awk '/MemTotal/ {printf \"%.1f\", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo unknown)\"",
                            "printf 'DISK=%s\\n' \"$(lsblk -dn -o SIZE,TYPE 2>/dev/null | awk '$2==\"disk\" {print $1}' | paste -sd+ - || echo unknown)\"",
                        ]
                    ),
                ],
                text=True,
                capture_output=True,
                check=False,
            )
            hostname = "unknown"
            arch = "unknown"
            os_name = "unknown"
            model = "unknown"
            cpu = "unknown"
            cores = "unknown"
            ram = "unknown"
            disk = "unknown"
            ssh_ok = ssh.returncode == 0
            if ssh_ok:
                facts = {}
                for line in ssh.stdout.splitlines():
                    if "=" not in line:
                        continue
                    key, value = line.split("=", 1)
                    facts[key.strip()] = value.strip() or "unknown"
                hostname = facts.get("HOSTNAME", hostname)
                arch = facts.get("ARCH", arch)
                os_name = facts.get("OS", os_name)
                model = facts.get("MODEL", model)
                cpu = facts.get("CPU", cpu) or "unknown"
                cores = facts.get("CORES", cores)
                ram = facts.get("RAM", ram)
                disk = facts.get("DISK", disk) or "unknown"
            name_source = "ssh" if hostname != "unknown" else "none"
            arm = arch in {"aarch64", "arm64", "armv7l"}
            return {
                "ip": ip,
                "hostname": hostname,
                "name_source": name_source,
                "arch": arch,
                "os": os_name,
                "model": model,
                "cpu": cpu,
                "cores": cores,
                "ram": ram,
                "disk": disk,
                "ssh": ssh_ok,
                "arm": arm,
            }

        found = []
        with ThreadPoolExecutor(max_workers=64) as pool:
            futures = [pool.submit(probe, ip) for ip in hosts]
            for future in as_completed(futures):
                row = future.result()
                if row:
                    found.append(row)

        found.sort(key=lambda row: tuple(int(part) for part in str(row["ip"]).split(".")))

        unresolved = [str(row["ip"]) for row in found if row["hostname"] == "unknown"]
        name_map: dict[str, tuple[str, str]] = {}
        if unresolved:
            with ThreadPoolExecutor(max_workers=4) as pool:
                futures = {pool.submit(resolve_endpoint_name, ip): ip for ip in unresolved}
                for future in as_completed(futures):
                    ip = futures[future]
                    name, source = future.result()
                    if name != "unknown":
                        name_map[ip] = (name, source)
        for row in found:
            name = name_map.get(str(row["ip"]))
            if row["hostname"] == "unknown" and name:
                row["hostname"], row["name_source"] = name
            row.update(classify_endpoint(row))
        self._json(200, {"cidrs": [str(network) for network in networks], "hosts": found})

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

        if step == "deploy" and env.get("DEPLOY_TOOL") == "genestack":
            command = STEPS["deploy_genestack"]
        elif step == "validate" and env.get("DEPLOY_TOOL") == "genestack":
            command = STEPS["validate_genestack"]
        elif step == "images" and env.get("DEPLOY_TOOL") == "genestack":
            command = STEPS["images_genestack"]
        elif step == "inventory" and env.get("SSH_USER"):
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
    try:
        server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    except OSError as exc:
        if exc.errno == errno.EADDRINUSE:
            print(f"Mission Control is already running: http://127.0.0.1:{port}")
            return 0
        raise
    print(f"Mission Control: http://127.0.0.1:{port}")
    server.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
