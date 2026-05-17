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

@test "scheduled broadcasts stay disabled when message is blank" {
  run bash -c '
    set -euo pipefail
    export SERVER_BROADCAST_MESSAGE=
    source scripts/start-server.sh
    start_scheduled_broadcasts
    test -z "$broadcast_pid"
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *"Scheduled broadcasts disabled because SERVER_BROADCAST_MESSAGE is blank"* ]]
}

@test "scheduled broadcasts reject invalid interval" {
  run bash -c '
    set -euo pipefail
    export SERVER_BROADCAST_MESSAGE="Join Discord"
    export SERVER_BROADCAST_INTERVAL_MINUTES=abc
    export RCON_ENABLED=true
    export RCON_PASSWORD=secret
    source scripts/start-server.sh
    start_scheduled_broadcasts
  '

  [ "$status" -ne 0 ]
  [[ "$output" == *"SERVER_BROADCAST_INTERVAL_MINUTES must be an unsigned integer"* ]]
}

@test "scheduled broadcasts send configured message" {
  fake_rcon="$BATS_TEST_TMPDIR/rcon-wrapper"
  rcon_log="$BATS_TEST_TMPDIR/broadcast.log"
  cat > "$fake_rcon" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$FAKE_RCON_LOG"
SH
  chmod +x "$fake_rcon"

  run timeout 3 bash -c '
    set -euo pipefail
    export RCON_WRAPPER="$1"
    export FAKE_RCON_LOG="$2"
    export RCON_ENABLED=true
    export RCON_PASSWORD=secret
    export SERVER_BROADCAST_MESSAGE="Join Discord"
    export SERVER_BROADCAST_INTERVAL_MINUTES=120
    source scripts/start-server.sh
    run_scheduled_broadcasts 1
  ' bash "$fake_rcon" "$rcon_log"

  [ "$status" -eq 124 ]
  grep -q '^broadcast Join Discord$' "$rcon_log"
}

@test "raid due broadcasts include start warnings and start notice" {
  run bash -c '
    set -euo pipefail
    export TZ=America/Los_Angeles
    export PVP_BUILDING_DAMAGE_DAYS=weekends
    export PVP_BUILDING_DAMAGE_START=18:00
    export PVP_BUILDING_DAMAGE_END=22:00
    source scripts/start-server.sh
    from="$(TZ="$TZ" date -d "2026-05-16 16:59:50" +%s)"
    to="$(TZ="$TZ" date -d "2026-05-16 17:00:10" +%s)"
    raid_due_broadcasts "$from" "$to"
    from="$(TZ="$TZ" date -d "2026-05-16 17:29:50" +%s)"
    to="$(TZ="$TZ" date -d "2026-05-16 17:30:10" +%s)"
    raid_due_broadcasts "$from" "$to"
    from="$(TZ="$TZ" date -d "2026-05-16 17:54:50" +%s)"
    to="$(TZ="$TZ" date -d "2026-05-16 17:55:10" +%s)"
    raid_due_broadcasts "$from" "$to"
    from="$(TZ="$TZ" date -d "2026-05-16 17:59:50" +%s)"
    to="$(TZ="$TZ" date -d "2026-05-16 18:00:10" +%s)"
    raid_due_broadcasts "$from" "$to"
  '

  [ "$status" -eq 0 ]
  [ "$output" = $'Raid time starts in 1 hour.\nRaid time starts in 30 minutes.\nRaid time starts in 5 minutes.\nRaid time has started.' ]
}

@test "raid due broadcasts include end warnings and end notice" {
  run bash -c '
    set -euo pipefail
    export TZ=America/Los_Angeles
    export PVP_BUILDING_DAMAGE_DAYS=weekends
    export PVP_BUILDING_DAMAGE_START=18:00
    export PVP_BUILDING_DAMAGE_END=22:00
    source scripts/start-server.sh
    for window in \
      "2026-05-16 20:59:50|2026-05-16 21:00:10" \
      "2026-05-16 21:29:50|2026-05-16 21:30:10" \
      "2026-05-16 21:54:50|2026-05-16 21:55:10" \
      "2026-05-16 21:59:50|2026-05-16 22:00:10"; do
      from_raw="${window%%|*}"
      to_raw="${window#*|}"
      from="$(TZ="$TZ" date -d "$from_raw" +%s)"
      to="$(TZ="$TZ" date -d "$to_raw" +%s)"
      raid_due_broadcasts "$from" "$to"
    done
  '

  [ "$status" -eq 0 ]
  [ "$output" = $'Raid time ends in 1 hour.\nRaid time ends in 30 minutes.\nRaid time ends in 5 minutes.\nRaid time has ended.' ]
}

@test "raid end warnings before short window starts are skipped" {
  run bash -c '
    set -euo pipefail
    export TZ=America/Los_Angeles
    export PVP_BUILDING_DAMAGE_DAYS=Saturday
    export PVP_BUILDING_DAMAGE_START=18:00
    export PVP_BUILDING_DAMAGE_END=18:20
    source scripts/start-server.sh
    from="$(TZ="$TZ" date -d "2026-05-16 17:19:50" +%s)"
    to="$(TZ="$TZ" date -d "2026-05-16 17:20:10" +%s)"
    raid_due_broadcasts "$from" "$to"
  '

  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "raid due broadcasts handle overnight windows" {
  run bash -c '
    set -euo pipefail
    export TZ=America/Los_Angeles
    export PVP_BUILDING_DAMAGE_DAYS=Saturday
    export PVP_BUILDING_DAMAGE_START=23:00
    export PVP_BUILDING_DAMAGE_END=00:30
    source scripts/start-server.sh
    from="$(TZ="$TZ" date -d "2026-05-16 22:29:50" +%s)"
    to="$(TZ="$TZ" date -d "2026-05-16 22:30:10" +%s)"
    raid_due_broadcasts "$from" "$to"
    from="$(TZ="$TZ" date -d "2026-05-16 23:29:50" +%s)"
    to="$(TZ="$TZ" date -d "2026-05-16 23:30:10" +%s)"
    raid_due_broadcasts "$from" "$to"
    from="$(TZ="$TZ" date -d "2026-05-17 00:29:50" +%s)"
    to="$(TZ="$TZ" date -d "2026-05-17 00:30:10" +%s)"
    raid_due_broadcasts "$from" "$to"
  '

  [ "$status" -eq 0 ]
  [ "$output" = $'Raid time starts in 30 minutes.\nRaid time ends in 1 hour.\nRaid time has ended.' ]
}

@test "raid broadcasts stay disabled when schedule is blank" {
  run bash -c '
    set -euo pipefail
    export RAID_BROADCASTS_ENABLED=true
    export PVP_BUILDING_DAMAGE_DAYS=
    export PVP_BUILDING_DAMAGE_START=
    export PVP_BUILDING_DAMAGE_END=
    source scripts/start-server.sh
    start_raid_broadcasts
    test -z "$raid_broadcast_pid"
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *"Raid broadcasts disabled because PVP_BUILDING_DAMAGE schedule is blank"* ]]
}

@test "raid broadcasts can be disabled explicitly" {
  run bash -c '
    set -euo pipefail
    export RAID_BROADCASTS_ENABLED=false
    export PVP_BUILDING_DAMAGE_DAYS=weekends
    export PVP_BUILDING_DAMAGE_START=18:00
    export PVP_BUILDING_DAMAGE_END=22:00
    source scripts/start-server.sh
    start_raid_broadcasts
    test -z "$raid_broadcast_pid"
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *"Raid broadcasts disabled because RAID_BROADCASTS_ENABLED=false"* ]]
}

@test "raid due broadcast sends expected rcon message" {
  fake_rcon="$BATS_TEST_TMPDIR/rcon-wrapper"
  rcon_log="$BATS_TEST_TMPDIR/raid-broadcast.log"
  cat > "$fake_rcon" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$FAKE_RCON_LOG"
SH
  chmod +x "$fake_rcon"

  run bash -c '
    set -euo pipefail
    export RCON_WRAPPER="$1"
    export FAKE_RCON_LOG="$2"
    export TZ=America/Los_Angeles
    export PVP_BUILDING_DAMAGE_DAYS=weekends
    export PVP_BUILDING_DAMAGE_START=18:00
    export PVP_BUILDING_DAMAGE_END=22:00
    source scripts/start-server.sh
    from="$(TZ="$TZ" date -d "2026-05-16 17:59:50" +%s)"
    to="$(TZ="$TZ" date -d "2026-05-16 18:00:10" +%s)"
    broadcast_due_raid_events "$from" "$to"
  ' bash "$fake_rcon" "$rcon_log"

  [ "$status" -eq 0 ]
  grep -q '^broadcast Raid time has started\.$' "$rcon_log"
}
