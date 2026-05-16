#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

require_nonempty RCON_PASSWORD "${RCON_PASSWORD:-}"

host="${RCON_HOST:-127.0.0.1}"
port="${RCON_PORT:-25575}"

exec rcon -a "${host}:${port}" -p "$RCON_PASSWORD" "$@"
