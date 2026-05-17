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
  grep -q '^RconEnabled=1$' "$cfg/Game.ini"
  grep -q '^RconPassword=rcon$' "$cfg/Game.ini"
  grep -q '^AdminPassword=admin$' "$cfg/ServerSettings.ini"
  grep -q '^ServerCommunity=0$' "$cfg/ServerSettings.ini"
  grep -q '^serverRegion=0$' "$cfg/ServerSettings.ini"
  grep -q '^serverVoiceChat=0$' "$cfg/ServerSettings.ini"
  grep -q '^DropEquipmentOnDeath=true$' "$cfg/ServerSettings.ini"
  grep -q '^DropBackpackOnDeath=true$' "$cfg/ServerSettings.ini"
  grep -q '^EverybodyCanLootCorpse=true$' "$cfg/ServerSettings.ini"
  grep -q '^ThrallConversionMultiplier=0.5$' "$cfg/ServerSettings.ini"
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

@test "configure-server applies raw ServerSettings overrides" {
  export AvatarLifetime=600
  export MaxAllowedPing=300
  export BuildingPickupEnabled=False
  run scripts/configure-server.sh
  [ "$status" -eq 0 ]
  cfg="$SERVER_DIR/ConanSandbox/Saved/Config/LinuxServer/ServerSettings.ini"
  grep -q '^AvatarLifetime=600$' "$cfg"
  grep -q '^MaxAllowedPing=300$' "$cfg"
  grep -q '^BuildingPickupEnabled=False$' "$cfg"
}

@test "configure-server converts Los Angeles weekend raid windows to UTC" {
  export TZ=America/Los_Angeles
  export PVP_BUILDING_DAMAGE_DAYS=weekends
  export PVP_BUILDING_DAMAGE_START=11:00
  export PVP_BUILDING_DAMAGE_END=23:00
  export AVATAR_SUMMONING_DAYS=weekends
  export AVATAR_SUMMONING_START=11:00
  export AVATAR_SUMMONING_END=23:00
  run scripts/configure-server.sh
  [ "$status" -eq 0 ]
  cfg="$SERVER_DIR/ConanSandbox/Saved/Config/LinuxServer/ServerSettings.ini"
  grep -q '^RestrictPVPBuildingDamageTime=True$' "$cfg"
  grep -q '^CanDamagePlayerOwnedStructures=True$' "$cfg"
  grep -q '^PVPBuildingDamageEnabledSaturday=True$' "$cfg"
  grep -q '^PVPBuildingDamageEnabledSunday=True$' "$cfg"
  grep -q '^PVPBuildingDamageTimeSaturdayStart=1800$' "$cfg"
  grep -q '^PVPBuildingDamageTimeSaturdayEnd=0600$' "$cfg"
  grep -q '^PVPBuildingDamageTimeSundayStart=1800$' "$cfg"
  grep -q '^PVPBuildingDamageTimeSundayEnd=0600$' "$cfg"
  grep -q '^RestrictAvatarSummoningTime=True$' "$cfg"
  grep -q '^AvatarSummoningTimeWeekendStart=1800$' "$cfg"
  grep -q '^AvatarSummoningTimeWeekendEnd=0600$' "$cfg"
}

@test "configure-server logs effective settings without secret values" {
  export TZ=UTC
  export PVP_TIME_DAYS=weekends
  export PVP_TIME_START=18:00
  export PVP_TIME_END=22:00
  run scripts/configure-server.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"========== Effective Server Settings =========="* ]]
  [[ "$output" == *"Schedules: PvP=weekends 18:00-22:00 UTC"* ]]
  [[ "$output" == *"EverybodyCanLootCorpse=true"* ]]
  [[ "$output" != *"admin"* ]]
  [[ "$output" != *"rcon"* ]]
}
