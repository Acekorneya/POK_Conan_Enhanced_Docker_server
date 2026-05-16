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

