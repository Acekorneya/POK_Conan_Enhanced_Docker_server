#!/usr/bin/env bats

@test "rcon-wrapper sends multi-word command as one rcon argument" {
  fake_bin="$BATS_TEST_TMPDIR/bin"
  rcon_log="$BATS_TEST_TMPDIR/rcon.log"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/rcon" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '<%s>\n' "$@" > "$FAKE_RCON_LOG"
SH
  chmod +x "$fake_bin/rcon"

  run env PATH="$fake_bin:$PATH" RCON_PASSWORD=secret FAKE_RCON_LOG="$rcon_log" scripts/rcon-wrapper.sh broadcast "Join our Discord Community"

  [ "$status" -eq 0 ]
  grep -q '^<-a>$' "$rcon_log"
  grep -q '^<127.0.0.1:25575>$' "$rcon_log"
  grep -q '^<-p>$' "$rcon_log"
  grep -q '^<secret>$' "$rcon_log"
  grep -q '^<broadcast Join our Discord Community>$' "$rcon_log"
}
