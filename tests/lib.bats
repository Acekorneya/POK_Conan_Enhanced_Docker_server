#!/usr/bin/env bats

setup() {
  export PATH="$BATS_TEST_DIRNAME/../scripts:$PATH"
}

@test "truthy accepts common enabled values" {
  run bash -c 'source scripts/lib.sh; truthy true && truthy 1 && truthy YES && truthy on'
  [ "$status" -eq 0 ]
}

@test "require_uint rejects non-numeric values" {
  run bash -c 'source scripts/lib.sh; require_uint PUID abc'
  [ "$status" -ne 0 ]
  [[ "$output" == *"PUID must be an unsigned integer"* ]]
}

@test "ini_set creates section and preserves unrelated keys" {
  tmp="$(mktemp)"
  printf '[Other]\nKeep=1\n' > "$tmp"
  run bash -c "source scripts/lib.sh; ini_set '$tmp' ServerSettings MaxPlayers 40"
  [ "$status" -eq 0 ]
  grep -q '^\[Other\]$' "$tmp"
  grep -q '^Keep=1$' "$tmp"
  grep -q '^\[ServerSettings\]$' "$tmp"
  grep -q '^MaxPlayers=40$' "$tmp"
}

@test "ini_set updates existing key without duplicating it" {
  tmp="$(mktemp)"
  printf '[ServerSettings]\nMaxPlayers=10\nOther=ok\n' > "$tmp"
  run bash -c "source scripts/lib.sh; ini_set '$tmp' ServerSettings MaxPlayers 70"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^MaxPlayers=' "$tmp")" -eq 1 ]
  grep -q '^MaxPlayers=70$' "$tmp"
  grep -q '^Other=ok$' "$tmp"
}

@test "csv_words splits commas semicolons and spaces" {
  run bash -c 'source scripts/lib.sh; csv_words "1, 2;3 4"'
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "1" ]
  [ "${lines[1]}" = "2" ]
  [ "${lines[2]}" = "3" ]
  [ "${lines[3]}" = "4" ]
}

@test "secret_state reports only whether a secret is set" {
  run bash -c 'source scripts/lib.sh; secret_state "super-secret"'
  [ "$status" -eq 0 ]
  [ "$output" = "set" ]

  run bash -c 'source scripts/lib.sh; secret_state ""'
  [ "$status" -eq 0 ]
  [ "$output" = "not set" ]
}

@test "password_state reports enabled or disabled without printing the password" {
  run bash -c 'source scripts/lib.sh; password_state "server-password"'
  [ "$status" -eq 0 ]
  [ "$output" = "enabled" ]

  run bash -c 'source scripts/lib.sh; password_state ""'
  [ "$status" -eq 0 ]
  [ "$output" = "disabled" ]
}

@test "enum labels are human-readable" {
  run bash -c 'source scripts/lib.sh; community_label 1; echo; region_label 1; echo; voice_chat_label 1'
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "Relaxed" ]
  [ "${lines[1]}" = "North America" ]
  [ "${lines[2]}" = "enabled" ]
}

@test "local_steam_build_id parses appmanifest buildid" {
  manifest="$(mktemp)"
  printf '"AppState"\n{\n  "appid" "443030"\n  "buildid" "123456"\n}\n' > "$manifest"
  run bash -c "source scripts/lib.sh; local_steam_build_id '$manifest'"
  [ "$status" -eq 0 ]
  [ "$output" = "123456" ]
}

@test "steam_app_info_build_id parses selected branch buildid" {
  appinfo="$(mktemp)"
  printf '"443030"\n{\n  "depots"\n  {\n    "branches"\n    {\n      "public"\n      {\n        "buildid" "111"\n      }\n      "testlive"\n      {\n        "buildid" "222"\n      }\n    }\n  }\n}\n' > "$appinfo"
  run bash -c "source scripts/lib.sh; steam_app_info_build_id '$appinfo' testlive"
  [ "$status" -eq 0 ]
  [ "$output" = "222" ]
}

@test "countdown marks use default thirty minute cadence" {
  run bash -c 'source scripts/lib.sh; countdown_marks_seconds 30'
  [ "$status" -eq 0 ]
  [ "$output" = $'1800\n1500\n1200\n900\n600\n300\n60\n30\n5\n1' ]
}

@test "countdown marks handle non-multiple notice values" {
  run bash -c 'source scripts/lib.sh; countdown_marks_seconds 17'
  [ "$status" -eq 0 ]
  [ "$output" = $'1020\n900\n600\n300\n60\n30\n5\n1' ]
}
