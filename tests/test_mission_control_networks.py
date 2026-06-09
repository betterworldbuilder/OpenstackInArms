from __future__ import annotations

import importlib.util
import ipaddress
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("mission_control", ROOT / "scripts/06_mission_control_server.py")
mission_control = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(mission_control)


def iface(value: str) -> ipaddress.IPv4Interface:
    return ipaddress.ip_interface(value)


def test_auto_scan_ignores_wsl_and_docker_networks() -> None:
    assert mission_control.usable_auto_network(iface("10.255.255.254/32"), "lo") is None
    assert mission_control.usable_auto_network(iface("172.17.0.1/16"), "docker0") is None
    assert mission_control.usable_auto_network(iface("172.20.0.1/16"), "br-10697003382f") is None
    assert (
        mission_control.usable_auto_network(
            iface("172.18.160.1/20"),
            "vEthernet (WSL (Hyper-V firewall))",
            "Hyper-V Virtual Ethernet Adapter",
        )
        is None
    )


def test_auto_scan_keeps_physical_lan_network() -> None:
    network = mission_control.usable_auto_network(iface("192.168.1.4/24"), "Wi-Fi", "RZ616 Wi-Fi 6E 160MHz")
    assert str(network) == "192.168.1.0/24"


def test_auto_scan_bounds_large_physical_network_to_host_24() -> None:
    network = mission_control.usable_auto_network(iface("10.10.20.33/20"), "Ethernet", "Intel Ethernet")
    assert str(network) == "10.10.20.0/24"


def test_auto_scan_uses_startup_cache_when_windows_interop_goes_away(monkeypatch) -> None:
    cached = ipaddress.ip_network("192.168.1.0/24")
    monkeypatch.setattr(mission_control, "AUTO_NETWORK_CACHE", [cached])
    monkeypatch.setattr(mission_control, "powershell_command", lambda: None)
    monkeypatch.setattr(mission_control, "is_wsl", lambda: True)
    assert mission_control.local_lan_networks() == [cached]


def test_auto_scan_uses_configured_env_cidrs(monkeypatch) -> None:
    monkeypatch.setattr(mission_control, "AUTO_NETWORK_CACHE", [])
    monkeypatch.setenv("MISSION_CONTROL_AUTO_CIDRS", "192.168.50.0/24")
    assert [str(network) for network in mission_control.local_lan_networks()] == ["192.168.50.0/24"]
