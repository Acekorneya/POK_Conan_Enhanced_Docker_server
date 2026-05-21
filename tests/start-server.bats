#!/usr/bin/env bats

setup() {
  export SERVER_DIR="$BATS_TEST_TMPDIR/server"
  export RCON_PASSWORD=secret
  export RCON_ENABLED=true
  export SAVE_VERIFY_TIMEOUT=5
  export BACKUP_ENABLED=false
  mkdir -p "$SERVER_DIR/ConanSandbox/Saved"
  touch "$SERVER_DIR/ConanSandbox/Saved/game.db"
}

teardown() {
  if [[ -n "${FAKE_CONAN_PID:-}" ]]; then
    kill "$FAKE_CONAN_PID" 2>/dev/null || true
    sleep 0.1
    kill -KILL "$FAKE_CONAN_PID" 2>/dev/null || true
    wait "$FAKE_CONAN_PID" 2>/dev/null || true
    unset FAKE_CONAN_PID
  fi
}

@test "graceful_stop_server sends rcon shutdown and not save" {
  fake_rcon="$BATS_TEST_TMPDIR/rcon-wrapper"
  rcon_log="$BATS_TEST_TMPDIR/rcon.log"
  cat > "$fake_rcon" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$FAKE_RCON_LOG"
if [[ "${1:-}" == "shutdown" ]]; then
  sleep 1
  touch "$SERVER_DIR/ConanSandbox/Saved/game.db"
  kill "$FAKE_SERVER_PID" 2>/dev/null || true
fi
SH
  chmod +x "$fake_rcon"

  run bash -c '
    set -euo pipefail
    export SERVER_DIR="$1"
    export RCON_WRAPPER="$2"
    export FAKE_RCON_LOG="$3"
    export RCON_PASSWORD=secret
    export RCON_ENABLED=true
    export SAVE_VERIFY_TIMEOUT=5
    export BACKUP_ENABLED=false
    source scripts/start-server.sh
    sleep 30 &
    server_pid="$!"
    export FAKE_SERVER_PID="$server_pid"
    graceful_stop_server test "Going down"
  ' bash "$SERVER_DIR" "$fake_rcon" "$rcon_log"

  [ "$status" -eq 0 ]
  grep -q '^broadcast Going down$' "$rcon_log"
  grep -q '^shutdown$' "$rcon_log"
  ! grep -q '^save$' "$rcon_log"
  [[ "$output" == *"Save-file timestamp changed after RCON shutdown"* ]]
}

@test "watchdog monitor requests restart after failed health threshold" {
  run bash -c '
    set -euo pipefail
    export SERVER_DIR="$1"
    export RCON_PASSWORD=secret
    export RCON_ENABLED=true
    export SERVER_WATCHDOG_INTERVAL_SECONDS=1
    export SERVER_WATCHDOG_FAILURE_THRESHOLD=1
    export SERVER_WATCHDOG_STARTUP_GRACE_SECONDS=0
    export SERVER_WATCHDOG_RESTART_COOLDOWN_SECONDS=0
    source scripts/start-server.sh
    server_pid=999999
    watchdog_request_file="$2"
    update_active_file="$3"
    update_request_file="$4"
    run_watchdog_monitor
    test -f "$watchdog_request_file"
  ' bash "$SERVER_DIR" "$BATS_TEST_TMPDIR/watchdog-request" "$BATS_TEST_TMPDIR/update-active" "$BATS_TEST_TMPDIR/update-request"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Server watchdog health check failed (1/1)"* ]]
}

@test "watchdog monitor ignores rcon failure while tracked process is alive" {
  run timeout 3 bash -c '
    set -euo pipefail
    export SERVER_DIR="$1"
    export RCON_PASSWORD=secret
    export RCON_ENABLED=true
    export RCON_WRAPPER=/bin/false
    export SERVER_WATCHDOG_INTERVAL_SECONDS=1
    export SERVER_WATCHDOG_FAILURE_THRESHOLD=1
    export SERVER_WATCHDOG_STARTUP_GRACE_SECONDS=0
    export SERVER_WATCHDOG_RESTART_COOLDOWN_SECONDS=0
    source scripts/start-server.sh
    sleep 30 &
    server_pid="$!"
    trap '\''kill "$server_pid" 2>/dev/null || true'\'' EXIT
    watchdog_request_file="$2"
    update_active_file="$3"
    update_request_file="$4"
    run_watchdog_monitor
  ' bash "$SERVER_DIR" "$BATS_TEST_TMPDIR/watchdog-request" "$BATS_TEST_TMPDIR/update-active" "$BATS_TEST_TMPDIR/update-request"

  [ "$status" -eq 124 ]
  [ ! -f "$BATS_TEST_TMPDIR/watchdog-request" ]
  [[ "$output" != *"Server watchdog health check failed"* ]]
}

@test "launch_server refuses to start while another Conan process exists" {
  conan_name="ConanSandboxServer-Linux""-Shipping"
  bash -c 'exec -a "$1" sleep 30' bash "$conan_name" &
  FAKE_CONAN_PID="$!"
  sleep 0.1

  run bash -c '
    set -euo pipefail
    export SERVER_DIR="$1"
    source scripts/start-server.sh
    launcher=(sleep)
    args=(30)
    launch_server
  ' bash "$SERVER_DIR"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Refusing to launch while Conan server process(es) still exist"* ]]
}

@test "terminate_server_if_needed fails when Conan process survives SIGTERM" {
  conan_name="ConanSandboxServer-Linux""-Shipping"
  bash -c 'trap "" TERM; exec -a "$1" sleep 30' bash "$conan_name" &
  FAKE_CONAN_PID="$!"
  sleep 0.1

  run bash -c '
    set -euo pipefail
    export SERVER_STOP_GRACE_SECONDS=1
    source scripts/start-server.sh
    server_pid=999999
    terminate_server_if_needed
  '

  [ "$status" -ne 0 ]
  [[ "$output" == *"did not stop after SIGTERM"* ]]
}

@test "disabled daily restart does not start a monitor" {
  run bash -c '
    set -euo pipefail
    export DAILY_RESTART_ENABLED=false
    source scripts/start-server.sh
    start_daily_restart_monitor
    [[ -z "${daily_restart_pid:-}" ]]
  '
  [ "$status" -eq 0 ]
}

@test "countdown writes a daily restart request after warnings" {
  run bash -c '
    set -euo pipefail
    export DAILY_RESTART_ENABLED=true
    export DAILY_RESTART_TIME="02:00"
    export TZ=UTC
    export AUTO_UPDATE_RESTART_NOTICE_MINUTES=1
    export RCON_ENABLED=true
    export RCON_PASSWORD=secret
    source scripts/start-server.sh

    # Mock sleep to do nothing so test finishes instantly
    sleep() { :; }
    export -f sleep

    # Mock rcon_broadcast
    rcon_broadcast() { echo "Mock broadcast: $*"; }
    export -f rcon_broadcast

    # Mock conan_processes_running to return true
    conan_processes_running() { return 0; }
    export -f conan_processes_running

    daily_restart_request_file="$BATS_TEST_TMPDIR/daily-request"
    run_daily_restart_monitor

    test -f "$daily_restart_request_file"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"Daily server restart scheduled. Restart in"* ]]
  [[ "$output" == *"Restarting server now for daily maintenance."* ]]
}

@test "main loop recognizes daily restart reason" {
  run bash -c '
    set -euo pipefail

    source scripts/start-server.sh

    # Mock dependencies
    run_startup_tasks() { :; }
    launch_server() { server_pid=999999; }
    start_update_monitor() { :; }
    start_watchdog_monitor() { :; }
    run_periodic_backups() { :; }
    server_running() { return 0; }
    stop_watchdog_monitor() { :; }
    stop_update_monitor() { :; }
    stop_daily_restart_monitor() { :; }
    stop_periodic_backups() { :; }

    graceful_stop_server() {
      echo "graceful_stop_server called with reason: $1"
      exit 0
    }

    daily_restart_request_file="$BATS_TEST_TMPDIR/daily-request"
    start_daily_restart_monitor() { touch "$daily_restart_request_file"; }

    main
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"graceful_stop_server called with reason: daily_restart"* ]]
}
