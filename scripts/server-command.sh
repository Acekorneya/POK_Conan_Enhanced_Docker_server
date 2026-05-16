#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

cmd="${1:-start}"
shift || true

case "$cmd" in
  start)
    exec "$SCRIPT_DIR/start-server.sh" "$@"
    ;;
  backup)
    exec "$SCRIPT_DIR/backup.sh" manual
    ;;
  update)
    exec "$SCRIPT_DIR/install-server.sh" force
    ;;
  rcon)
    exec "$SCRIPT_DIR/rcon-wrapper.sh" "$@"
    ;;
  bash|sh)
    exec "/bin/$cmd" "$@"
    ;;
  *)
    exec "$cmd" "$@"
    ;;
esac
