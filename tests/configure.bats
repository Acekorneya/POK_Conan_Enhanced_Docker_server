#!/usr/bin/env bats

setup() {
  export SERVER_DIR="$BATS_TEST_TMPDIR/server"
  export ADMIN_PASSWORD=admin
  export RCON_PASSWORD=rcon
  export SERVER_NAME="Test Server"
  export SERVER_PASSWORD=""
  mkdir -p "$SERVER_DIR"
}

@test "configure-server renders key config files" {
  run scripts/configure-server.sh
  [ "$status" -eq 0 ]
  cfg="$SERVER_DIR/ConanSandbox/Saved/Config/LinuxServer"
  grep -q '^ServerName=Test Server$' "$cfg/Engine.ini"
  grep -q '^RconEnabled=True$' "$cfg/Game.ini"
  grep -q '^RconPassword=rcon$' "$cfg/Game.ini"
  grep -q '^AdminPassword=admin$' "$cfg/ServerSettings.ini"
  grep -q '^ServerCommunity=0$' "$cfg/ServerSettings.ini"
  grep -q '^serverRegion=0$' "$cfg/ServerSettings.ini"
  grep -q '^serverVoiceChat=0$' "$cfg/ServerSettings.ini"
}

@test "configure-server requires admin password" {
  export ADMIN_PASSWORD=
  run scripts/configure-server.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"ADMIN_PASSWORD is required"* ]]
}

@test "configure-server rejects example passwords" {
  export ADMIN_PASSWORD=change-me
  export RCON_PASSWORD=change-me-rcon
  run scripts/configure-server.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"ADMIN_PASSWORD must be changed"* ]]
}

@test "configure-server rejects invalid community value" {
  export COMMUNITY=10
  run scripts/configure-server.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"COMMUNITY must be one of: 0 1 2 3 4"* ]]
}
