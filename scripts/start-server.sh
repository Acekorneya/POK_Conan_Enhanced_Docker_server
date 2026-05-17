#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

SERVER_DIR="${SERVER_DIR:-/data/server}"

log_section "Startup Tasks"
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
  log_error "Conan server launcher not found after install"
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
  log_section "Graceful Shutdown"
  save_dir="$(saved_dir)"
  before="$(latest_save_mtime "$save_dir")"

  if truthy "${RCON_ENABLED:-true}" && [[ -n "${RCON_PASSWORD:-}" ]]; then
    log_info "Sending RCON shutdown broadcast"
    "$SCRIPT_DIR/rcon-wrapper.sh" broadcast "Server shutting down, saving world." >/dev/null 2>&1 || true
    log_info "Sending RCON save command"
    "$SCRIPT_DIR/rcon-wrapper.sh" save >/dev/null 2>&1 || true
    deadline=$(( $(date +%s) + ${SAVE_VERIFY_TIMEOUT:-60} ))
    while (( $(date +%s) < deadline )); do
      after="$(latest_save_mtime "$save_dir")"
      if (( after > before )); then
        log_info "Save-file timestamp changed after RCON save"
        break
      fi
      sleep 2
    done
    after="$(latest_save_mtime "$save_dir")"
    if (( after <= before )); then
      log_warn "Save timestamp did not change within ${SAVE_VERIFY_TIMEOUT:-60} seconds"
    fi
  else
    log_warn "RCON save skipped because RCON is disabled or RCON_PASSWORD is not set"
  fi

  if truthy "${BACKUP_ENABLED:-true}" && truthy "${BACKUP_ON_STOP:-true}"; then
    log_info "Creating shutdown backup"
    "$SCRIPT_DIR/backup.sh" stop || true
  else
    log_info "Shutdown backup disabled"
  fi
}

# shellcheck disable=SC2317
handle_signal() {
  log_info "Received stop signal"
  save_and_backup
  if [[ -n "$server_pid" ]] && kill -0 "$server_pid" 2>/dev/null; then
    log_info "Forwarding SIGTERM to Conan server process $server_pid"
    kill -TERM "$server_pid" 2>/dev/null || true
  fi
}

run_periodic_backups() {
  if ! truthy "${BACKUP_ENABLED:-true}"; then
    log_info "Scheduled backups disabled"
    return 0
  fi
  require_uint BACKUP_INTERVAL_MINUTES "${BACKUP_INTERVAL_MINUTES:-60}"
  log_info "Scheduled backups enabled: every ${BACKUP_INTERVAL_MINUTES:-60} minutes, retention=${BACKUP_RETENTION_COUNT:-30}"
  while true; do
    sleep "$(( BACKUP_INTERVAL_MINUTES * 60 ))"
    "$SCRIPT_DIR/backup.sh" scheduled || true
  done
}

trap handle_signal TERM INT

log_section "Conan Launch"
log_info "Selected launcher: ${launcher[*]}"
log_info "Launch args: ${args[*]} $*"

run_periodic_backups &
backup_pid="$!"

cd "$SERVER_DIR"
log_info "Starting Conan server process..."
"${launcher[@]}" "${args[@]}" "$@" &
server_pid="$!"
log_info "Conan server process started with PID $server_pid"

set +e
wait "$server_pid"
status="$?"
set -e

if [[ -n "$backup_pid" ]]; then
  kill "$backup_pid" 2>/dev/null || true
fi

log_info "Conan server process exited with status $status"
exit "$status"
