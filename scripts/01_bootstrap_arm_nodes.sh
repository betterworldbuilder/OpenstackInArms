#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

printf 'WARNING: scripts/01_bootstrap_arm_nodes.sh was renamed to scripts/01_bootstrap_cloud_nodes.sh\n' >&2
exec "${SCRIPT_DIR}/01_bootstrap_cloud_nodes.sh" "$@"
