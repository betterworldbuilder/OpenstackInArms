#!/usr/bin/env bash

set -Eeuo pipefail

log() {
  printf '\n\033[1;34m==> %s\033[0m\n' "$*"
}

warn() {
  printf '\n\033[1;33mWARNING: %s\033[0m\n' "$*" >&2
}

die() {
  printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

require_file() {
  [[ -f "$1" ]] || die "Missing required file: $1"
}

require_env() {
  local name="$1"
  [[ -n "${!name:-}" ]] || die "Missing required environment variable: $name"
}

require_root_or_sudo() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    need_cmd sudo
  fi
}

run_sudo() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}
