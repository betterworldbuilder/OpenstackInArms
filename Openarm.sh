#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT="${MISSION_CONTROL_PORT:-8787}"
URL="http://127.0.0.1:${PORT}"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'ERROR: Missing required command: %s\n' "$1" >&2
    exit 1
  }
}

open_browser() {
  if command -v powershell.exe >/dev/null 2>&1; then
    powershell.exe -NoProfile -Command "Start-Process '${URL}'" >/dev/null 2>&1 || true
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$URL" >/dev/null 2>&1 || true
  elif command -v open >/dev/null 2>&1; then
    open "$URL" >/dev/null 2>&1 || true
  fi
}

port_busy() {
  python3 - "$PORT" <<'PY'
import socket
import sys

port = int(sys.argv[1])
sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.settimeout(0.25)
try:
    raise SystemExit(0 if sock.connect_ex(("127.0.0.1", port)) == 0 else 1)
finally:
    sock.close()
PY
}

need_cmd python3

cd "$SCRIPT_DIR"

printf '\nOPENSTACKK BROTHERS and SISTERS in ARM\n'
printf 'Starting BrothersInArms Mission Control\n'
printf 'URL: %s\n\n' "$URL"

if port_busy; then
  printf 'Mission Control is already running on port %s.\n' "$PORT"
  printf 'Opening existing session: %s\n\n' "$URL"
  open_browser
  exit 0
fi

(
  sleep 1
  open_browser
) &

MISSION_CONTROL_PORT="$PORT" exec python3 scripts/06_mission_control_server.py
