#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

SERVER_DIR="${SERVER_DIR:-/data/server}"

"$SCRIPT_DIR/install-server.sh"
"$SCRIPT_DIR/configure-server.sh"
"$SCRIPT_DIR/install-mods.sh"

server_sh="$SERVER_DIR/ConanSandboxServer.sh"
server_bin="$SERVER_DIR/ConanSandbox/Binaries/Linux/ConanSandboxServer-Linux-Shipping"
if [[ -x "$server_sh" ]]; then
  launcher=("$server_sh")
elif [[ -x "$server_bin" ]]; then
  launcher=("$server_bin" "ConanSandbox")
else
  echo "Conan server launcher not found after install." >&2
  exit 1
fi

args=(
  "-log"
  "-MaxPlayers=${MAX_PLAYERS:-40}"
  "-MULTIHOME=${MULTIHOME:-0.0.0.0}"
  "-Port=${SERVER_PORT:-7777}"
  "-QueryPort=${QUERY_PORT:-27015}"
)

if truthy "${RCON_ENABLED:-true}"; then
  args+=("-RconEnabled=True" "-RconPort=${RCON_PORT:-25575}")
fi

shutdown_requested=false
server_pid=""
backup_pid=""

# shellcheck disable=SC2317
save_and_backup() {
  local before after deadline save_dir
  if [[ "$shutdown_requested" == true ]]; then
    return 0
  fi
  shutdown_requested=true
  save_dir="$(saved_dir)"
  before="$(latest_save_mtime "$save_dir")"

  if truthy "${RCON_ENABLED:-true}" && [[ -n "${RCON_PASSWORD:-}" ]]; then
    "$SCRIPT_DIR/rcon-wrapper.sh" broadcast "Server shutting down, saving world." >/dev/null 2>&1 || true
    "$SCRIPT_DIR/rcon-wrapper.sh" save >/dev/null 2>&1 || true
    deadline=$(( $(date +%s) + ${SAVE_VERIFY_TIMEOUT:-60} ))
    while (( $(date +%s) < deadline )); do
      after="$(latest_save_mtime "$save_dir")"
      if (( after > before )); then
        break
      fi
      sleep 2
    done
  fi

  if truthy "${BACKUP_ENABLED:-true}" && truthy "${BACKUP_ON_STOP:-true}"; then
    "$SCRIPT_DIR/backup.sh" stop || true
  fi
}

# shellcheck disable=SC2317
handle_signal() {
  save_and_backup
  if [[ -n "$server_pid" ]] && kill -0 "$server_pid" 2>/dev/null; then
    kill -TERM "$server_pid" 2>/dev/null || true
  fi
}

run_periodic_backups() {
  if ! truthy "${BACKUP_ENABLED:-true}"; then
    return 0
  fi
  require_uint BACKUP_INTERVAL_MINUTES "${BACKUP_INTERVAL_MINUTES:-60}"
  while true; do
    sleep "$(( BACKUP_INTERVAL_MINUTES * 60 ))"
    "$SCRIPT_DIR/backup.sh" scheduled || true
  done
}

trap handle_signal TERM INT

run_periodic_backups &
backup_pid="$!"

cd "$SERVER_DIR"
"${launcher[@]}" "${args[@]}" "$@" &
server_pid="$!"

wait "$server_pid"
status="$?"

if [[ -n "$backup_pid" ]]; then
  kill "$backup_pid" 2>/dev/null || true
fi

exit "$status"
