#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

SERVER_DIR="${SERVER_DIR:-/data/server}"
STEAM_DIR="${STEAM_DIR:-/data/steam}"
STEAMCMD_DIR="${STEAMCMD_DIR:-/opt/steamcmd}"

server_pid=""
backup_pid=""
update_pid=""
watchdog_pid=""
update_request_file="${TMPDIR:-/tmp}/conan-update-request.$$"
update_active_file="${TMPDIR:-/tmp}/conan-update-active.$$"
watchdog_request_file="${TMPDIR:-/tmp}/conan-watchdog-request.$$"
shutdown_requested=false
launcher=()
args=()
watchdog_restart_count=0
watchdog_extra_grace_seconds=0

rcon_command() {
  "${RCON_WRAPPER:-$SCRIPT_DIR/rcon-wrapper.sh}" "$@"
}

rcon_broadcast() {
  local message="$1"
  log_info "RCON broadcast: $message"
  rcon_command broadcast "$message" >/dev/null 2>&1 || log_warn "RCON broadcast failed"
}

steam_latest_build_id() {
  local tmp build_id
  tmp="$(mktemp)"
  if ! HOME="$STEAM_DIR" "$STEAMCMD_DIR/steamcmd.sh" \
    +login anonymous \
    +app_info_update 1 \
    +app_info_print 443030 \
    +quit >"$tmp" 2>&1; then
    log_warn "SteamCMD app_info_print failed while checking for updates"
    rm -f "$tmp"
    return 1
  fi

  build_id="$(steam_app_info_build_id "$tmp" "${STEAM_BRANCH:-public}")"
  rm -f "$tmp"
  [[ -n "$build_id" ]] || return 1
  printf '%s\n' "$build_id"
}

prepare_launcher() {
  local server_sh server_bin
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
    args+=("-RconEnabled=1" "-RconPort=${RCON_PORT:-25575}")
    if [[ -n "${RCON_PASSWORD:-}" ]]; then
      args+=("-RconPassword=${RCON_PASSWORD}")
    fi
  fi
}

run_startup_tasks() {
  log_section "Startup Tasks"
  "$SCRIPT_DIR/install-server.sh"
  "$SCRIPT_DIR/configure-server.sh"
  "$SCRIPT_DIR/install-mods.sh"
  prepare_launcher
}

launch_server() {
  local safe_args=()
  local arg

  log_section "Conan Launch"
  log_info "Selected launcher: ${launcher[*]}"
  for arg in "${args[@]}" "$@"; do
    case "$arg" in
      -RconPassword=*) safe_args+=("-RconPassword=***") ;;
      *) safe_args+=("$arg") ;;
    esac
  done
  log_info "Launch args: ${safe_args[*]}"

  cd "$SERVER_DIR"
  log_info "Starting Conan server process..."
  "${launcher[@]}" "${args[@]}" "$@" &
  server_pid="$!"
  log_info "Conan server process started with PID $server_pid"
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

stop_periodic_backups() {
  if [[ -n "$backup_pid" ]]; then
    kill "$backup_pid" 2>/dev/null || true
    wait "$backup_pid" 2>/dev/null || true
    backup_pid=""
  fi
}

wait_for_rcon_shutdown() {
  local before="$1"
  local deadline after save_changed=false
  deadline=$(( $(date +%s) + ${SAVE_VERIFY_TIMEOUT:-60} ))

  while (( $(date +%s) < deadline )); do
    after="$(latest_save_mtime "$(saved_dir)")"
    if (( after > before )) && [[ "$save_changed" == false ]]; then
      log_info "Save-file timestamp changed after RCON shutdown"
      save_changed=true
    fi
    if ! server_running "$server_pid"; then
      break
    fi
    sleep 2
  done

  after="$(latest_save_mtime "$(saved_dir)")"
  if (( after <= before )); then
    log_warn "Save timestamp did not change within ${SAVE_VERIFY_TIMEOUT:-60} seconds"
  fi
}

terminate_server_if_needed() {
  if ! server_running "$server_pid"; then
    return 0
  fi

  log_warn "Conan server process $server_pid is still running; sending SIGTERM"
  kill -TERM "$server_pid" 2>/dev/null || true
  for _ in {1..10}; do
    if ! server_running "$server_pid"; then
      return 0
    fi
    sleep 1
  done

  if server_running "$server_pid"; then
    log_warn "Conan server process $server_pid did not stop after SIGTERM; sending SIGKILL"
    kill -KILL "$server_pid" 2>/dev/null || true
  fi
}

graceful_stop_server() {
  local reason="${1:-stop}"
  local message="${2:-Server shutting down, saving world.}"
  local before

  if [[ -z "$server_pid" ]]; then
    return 0
  fi

  log_section "Graceful Shutdown"
  before="$(latest_save_mtime "$(saved_dir)")"

  if truthy "${RCON_ENABLED:-true}" && [[ -n "${RCON_PASSWORD:-}" ]]; then
    [[ -n "$message" ]] && rcon_broadcast "$message"
    log_info "Sending RCON shutdown command"
    rcon_command shutdown >/dev/null 2>&1 || log_warn "RCON shutdown command failed"
    wait_for_rcon_shutdown "$before"
  else
    log_warn "RCON shutdown skipped because RCON is disabled or RCON_PASSWORD is not set"
  fi

  terminate_server_if_needed
  wait "$server_pid" 2>/dev/null || true

  if truthy "${BACKUP_ENABLED:-true}" && truthy "${BACKUP_ON_STOP:-true}"; then
    log_info "Creating $reason backup"
    "$SCRIPT_DIR/backup.sh" "$reason" || true
  else
    log_info "Shutdown backup disabled"
  fi
}

run_update_countdown() {
  local local_build="$1"
  local latest_build="$2"
  local notice="${AUTO_UPDATE_RESTART_NOTICE_MINUTES:-30}"
  local marks=()
  local mark next_mark label i

  mapfile -t marks < <(countdown_marks_seconds "$notice")
  log_section "Automatic Update"
  log_info "Update detected: local build=$local_build latest build=$latest_build"

  for (( i = 0; i < ${#marks[@]}; i++ )); do
    mark="${marks[$i]}"
    label="$(countdown_label "$mark")"
    rcon_broadcast "Server update detected. Restart in $label."
    if (( i + 1 < ${#marks[@]} )); then
      next_mark="${marks[$((i + 1))]}"
      sleep "$(( mark - next_mark ))"
    else
      sleep "$mark"
    fi
  done

  rcon_broadcast "Restarting server now for update."
}

run_update_monitor() {
  local interval_hours="${AUTO_UPDATE_CHECK_INTERVAL_HOURS:-6}"
  local interval_seconds latest_build local_build

  require_uint_between AUTO_UPDATE_CHECK_INTERVAL_HOURS "$interval_hours" 1 24 || return 1
  interval_seconds=$(( interval_hours * 3600 ))

  log_info "Automatic update monitor enabled: every $interval_hours hour(s), restart notice=${AUTO_UPDATE_RESTART_NOTICE_MINUTES:-30} minute(s)"
  while true; do
    sleep "$interval_seconds"

    local_build="$(local_steam_build_id "${SERVER_DIR}/steamapps/appmanifest_443030.acf" || true)"
    if [[ -z "$local_build" ]]; then
      log_warn "Could not read local Steam build ID from appmanifest; retrying next interval"
      continue
    fi

    latest_build="$(steam_latest_build_id || true)"
    if [[ -z "$latest_build" ]]; then
      log_warn "Could not read latest Steam build ID; retrying next interval"
      continue
    fi

    if [[ "$latest_build" != "$local_build" ]]; then
      touch "$update_active_file"
      run_update_countdown "$local_build" "$latest_build"
      printf 'local_build=%s latest_build=%s\n' "$local_build" "$latest_build" > "$update_request_file"
      return 0
    fi

    log_info "No Conan update detected: build=$local_build"
  done
}

start_update_monitor() {
  if ! truthy "${AUTO_UPDATE:-true}"; then
    log_info "Automatic update monitor disabled because AUTO_UPDATE=false"
    return 0
  fi
  if ! truthy "${RCON_ENABLED:-true}" || [[ -z "${RCON_PASSWORD:-}" ]]; then
    log_warn "Automatic update monitor disabled because RCON is disabled or RCON_PASSWORD is not set"
    return 0
  fi

  require_uint_between AUTO_UPDATE_CHECK_INTERVAL_HOURS "${AUTO_UPDATE_CHECK_INTERVAL_HOURS:-6}" 1 24
  require_positive_uint AUTO_UPDATE_RESTART_NOTICE_MINUTES "${AUTO_UPDATE_RESTART_NOTICE_MINUTES:-30}"

  run_update_monitor &
  update_pid="$!"
}

stop_update_monitor() {
  if [[ -n "$update_pid" ]]; then
    kill "$update_pid" 2>/dev/null || true
    wait "$update_pid" 2>/dev/null || true
    update_pid=""
  fi
}

wait_for_server_health() {
  local timeout="${1:-600}"
  local label="${2:-restart}"
  local deadline
  deadline=$(( $(date +%s) + timeout ))
  log_info "Verifying Conan server health after $label"

  while (( $(date +%s) < deadline )); do
    if ! server_running "$server_pid"; then
      log_warn "Conan server process exited before health verification completed"
      return 1
    fi

    if truthy "${RCON_ENABLED:-true}"; then
      if rcon_command help >/dev/null 2>&1; then
        log_info "Conan server health verified with RCON"
        return 0
      fi
    else
      log_info "Conan server process is running; RCON health verification skipped"
      return 0
    fi

    sleep 5
  done

  log_warn "Conan server health did not verify within $timeout seconds"
  return 1
}

watchdog_health_ok() {
  server_running "$server_pid" || return 1
  if truthy "${RCON_ENABLED:-true}"; then
    rcon_command help >/dev/null 2>&1 || return 1
  fi
  return 0
}

run_watchdog_monitor() {
  local interval="${SERVER_WATCHDOG_INTERVAL_SECONDS:-60}"
  local threshold="${SERVER_WATCHDOG_FAILURE_THRESHOLD:-3}"
  local grace="${SERVER_WATCHDOG_STARTUP_GRACE_SECONDS:-600}"
  local total_grace
  local failures=0

  require_positive_uint SERVER_WATCHDOG_INTERVAL_SECONDS "$interval" || return 1
  require_positive_uint SERVER_WATCHDOG_FAILURE_THRESHOLD "$threshold" || return 1
  require_uint SERVER_WATCHDOG_STARTUP_GRACE_SECONDS "$grace" || return 1
  require_uint SERVER_WATCHDOG_RESTART_COOLDOWN_SECONDS "${watchdog_extra_grace_seconds:-0}" || return 1
  total_grace=$(( grace + watchdog_extra_grace_seconds ))

  log_info "Server watchdog enabled: interval=${interval}s failures=$threshold startup_grace=${total_grace}s"
  sleep "$total_grace"

  while true; do
    if [[ -f "$update_active_file" || -f "$update_request_file" ]]; then
      failures=0
      sleep "$interval"
      continue
    fi

    if watchdog_health_ok; then
      if (( failures > 0 )); then
        log_info "Server watchdog health recovered after $failures failed check(s)"
      fi
      failures=0
    else
      failures=$(( failures + 1 ))
      log_warn "Server watchdog health check failed ($failures/$threshold)"
      if (( failures >= threshold )); then
        printf 'failures=%s threshold=%s\n' "$failures" "$threshold" > "$watchdog_request_file"
        return 0
      fi
    fi

    sleep "$interval"
  done
}

start_watchdog_monitor() {
  if ! truthy "${SERVER_WATCHDOG_ENABLED:-true}"; then
    log_info "Server watchdog disabled"
    return 0
  fi

  require_positive_uint SERVER_WATCHDOG_INTERVAL_SECONDS "${SERVER_WATCHDOG_INTERVAL_SECONDS:-60}"
  require_positive_uint SERVER_WATCHDOG_FAILURE_THRESHOLD "${SERVER_WATCHDOG_FAILURE_THRESHOLD:-3}"
  require_uint SERVER_WATCHDOG_STARTUP_GRACE_SECONDS "${SERVER_WATCHDOG_STARTUP_GRACE_SECONDS:-600}"
  require_uint SERVER_WATCHDOG_RESTART_COOLDOWN_SECONDS "${SERVER_WATCHDOG_RESTART_COOLDOWN_SECONDS:-300}"
  require_uint SERVER_WATCHDOG_MAX_RESTARTS "${SERVER_WATCHDOG_MAX_RESTARTS:-3}"

  run_watchdog_monitor &
  watchdog_pid="$!"
}

stop_watchdog_monitor() {
  if [[ -n "$watchdog_pid" ]]; then
    kill "$watchdog_pid" 2>/dev/null || true
    wait "$watchdog_pid" 2>/dev/null || true
    watchdog_pid=""
  fi
}

cleanup_runtime() {
  stop_watchdog_monitor
  stop_update_monitor
  stop_periodic_backups
  rm -f "$update_request_file" "$update_active_file" "$watchdog_request_file"
}

handle_signal() {
  if [[ "$shutdown_requested" == true ]]; then
    return 0
  fi
  shutdown_requested=true
  log_info "Received stop signal"
  stop_watchdog_monitor
  stop_update_monitor
  graceful_stop_server stop "Server shutting down, saving world."
  stop_periodic_backups
  rm -f "$update_request_file" "$update_active_file" "$watchdog_request_file"
  exit 0
}

main() {
  local status restart_requested restart_reason verify_after_launch=false max_watchdog_restarts

  trap handle_signal TERM INT

  while true; do
    rm -f "$update_request_file" "$update_active_file" "$watchdog_request_file"
    run_startup_tasks
    launch_server "$@"

    run_periodic_backups &
    backup_pid="$!"

    if [[ "$verify_after_launch" == true ]]; then
      wait_for_server_health 600 "restart" || true
      verify_after_launch=false
    fi

    start_update_monitor
    start_watchdog_monitor
    watchdog_extra_grace_seconds=0
    restart_requested=false
    restart_reason=""
    while server_running "$server_pid"; do
      if [[ -f "$update_request_file" ]]; then
        restart_requested=true
        restart_reason="update"
        break
      fi
      if [[ -f "$watchdog_request_file" ]]; then
        restart_requested=true
        restart_reason="watchdog"
        break
      fi
      sleep 2
    done

    if [[ "$restart_requested" == true ]]; then
      stop_watchdog_monitor
      stop_update_monitor
      if [[ "$restart_reason" == "watchdog" ]]; then
        watchdog_restart_count=$(( watchdog_restart_count + 1 ))
        max_watchdog_restarts="${SERVER_WATCHDOG_MAX_RESTARTS:-3}"
        if (( max_watchdog_restarts > 0 && watchdog_restart_count > max_watchdog_restarts )); then
          log_error "Server watchdog exceeded max restarts ($max_watchdog_restarts); exiting for Docker restart policy"
          stop_periodic_backups
          terminate_server_if_needed
          exit 1
        fi
        if (( max_watchdog_restarts > 0 )); then
          log_warn "Server watchdog restarting Conan process (attempt $watchdog_restart_count/$max_watchdog_restarts)"
        else
          log_warn "Server watchdog restarting Conan process (attempt $watchdog_restart_count/unlimited)"
        fi
        graceful_stop_server watchdog "Server health check failed. Restarting server."
        stop_periodic_backups
        verify_after_launch=true
        watchdog_extra_grace_seconds="${SERVER_WATCHDOG_RESTART_COOLDOWN_SECONDS:-300}"
      else
        graceful_stop_server update ""
        stop_periodic_backups
        verify_after_launch=true
      fi
      continue
    fi

    set +e
    wait "$server_pid"
    status="$?"
    set -e

    cleanup_runtime
    log_info "Conan server process exited with status $status"
    exit "$status"
  done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
