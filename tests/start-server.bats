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
