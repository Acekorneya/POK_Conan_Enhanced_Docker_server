#!/usr/bin/env bats

setup() {
  export SERVER_DIR="$BATS_TEST_TMPDIR/server"
  export BACKUP_DIR="$BATS_TEST_TMPDIR/backups"
  export BACKUP_RETENTION_COUNT=1
  mkdir -p "$SERVER_DIR/ConanSandbox/Saved/Config/LinuxServer" "$BACKUP_DIR"
  sqlite3 "$SERVER_DIR/ConanSandbox/Saved/game.db" 'create table test(id integer); insert into test values (1);'
  printf '[ServerSettings]\nMaxPlayers=40\n' > "$SERVER_DIR/ConanSandbox/Saved/Config/LinuxServer/ServerSettings.ini"
}

@test "backup creates archive with save and config" {
  run scripts/backup.sh test
  [ "$status" -eq 0 ]
  archive="$(find "$BACKUP_DIR" -name 'conan-*-test.tar.gz' | head -n1)"
  [ -n "$archive" ]
  tar -tzf "$archive" | grep -q './saves/game.db'
  tar -tzf "$archive" | grep -q './config/ServerSettings.ini'
  tar -tzf "$archive" | grep -q './metadata.txt'
}

@test "backup retention removes older archives" {
  touch "$BACKUP_DIR/conan-20000101T000000Z-old.tar.gz"
  run scripts/backup.sh retention
  [ "$status" -eq 0 ]
  [ "$(find "$BACKUP_DIR" -name 'conan-*.tar.gz' | wc -l)" -eq 1 ]
}

