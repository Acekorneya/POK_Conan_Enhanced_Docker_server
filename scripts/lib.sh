#!/usr/bin/env bash

truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

log_timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

log_info() {
  printf '[%s] [INFO] %s\n' "$(log_timestamp)" "$*"
}

log_warn() {
  printf '[%s] [WARN] %s\n' "$(log_timestamp)" "$*" >&2
}

log_error() {
  printf '[%s] [ERROR] %s\n' "$(log_timestamp)" "$*" >&2
}

log_section() {
  log_info "========== $* =========="
}

secret_state() {
  if [[ -n "${1:-}" ]]; then
    printf 'set'
  else
    printf 'not set'
  fi
}

password_state() {
  if [[ -n "${1:-}" ]]; then
    printf 'enabled'
  else
    printf 'disabled'
  fi
}

community_label() {
  case "${1:-0}" in
    0) printf 'Purist' ;;
    1) printf 'Relaxed' ;;
    2) printf 'HardCore' ;;
    3) printf 'RolePlaying' ;;
    4) printf 'Experimental' ;;
    *) printf 'Unknown(%s)' "${1:-}" ;;
  esac
}

region_label() {
  case "${1:-0}" in
    0) printf 'Europe' ;;
    1) printf 'North America' ;;
    2) printf 'Asia' ;;
    3) printf 'Australia' ;;
    4) printf 'South America' ;;
    5) printf 'Japan' ;;
    *) printf 'Unknown(%s)' "${1:-}" ;;
  esac
}

voice_chat_label() {
  case "${1:-0}" in
    0) printf 'disabled' ;;
    1) printf 'enabled' ;;
    *) printf 'Unknown(%s)' "${1:-}" ;;
  esac
}

bool_ini() {
  if truthy "${1:-false}"; then
    printf 'True'
  else
    printf 'False'
  fi
}

require_uint() {
  local name="$1"
  local value="$2"
  if ! [[ "$value" =~ ^[0-9]+$ ]]; then
    echo "$name must be an unsigned integer, got: $value" >&2
    return 1
  fi
}

require_nonempty() {
  local name="$1"
  local value="$2"
  if [[ -z "$value" ]]; then
    echo "$name is required" >&2
    return 1
  fi
}

reject_placeholder() {
  local name="$1"
  local value="$2"
  shift 2
  local placeholder
  for placeholder in "$@"; do
    if [[ "$value" == "$placeholder" ]]; then
      echo "$name must be changed from the example value" >&2
      return 1
    fi
  done
}

require_choice() {
  local name="$1"
  local value="$2"
  shift 2
  local choice
  for choice in "$@"; do
    if [[ "$value" == "$choice" ]]; then
      return 0
    fi
  done
  echo "$name must be one of: $*" >&2
  return 1
}

csv_words() {
  printf '%s\n' "${1:-}" | tr ',;' '  ' | xargs -n1 2>/dev/null || true
}

canonical_day() {
  local value="${1,,}"
  case "$value" in
    mon|monday) printf 'Monday' ;;
    tue|tues|tuesday) printf 'Tuesday' ;;
    wed|wednesday) printf 'Wednesday' ;;
    thu|thur|thurs|thursday) printf 'Thursday' ;;
    fri|friday) printf 'Friday' ;;
    sat|saturday) printf 'Saturday' ;;
    sun|sunday) printf 'Sunday' ;;
    *) return 1 ;;
  esac
}

expand_day_tokens() {
  local token
  while IFS= read -r token; do
    case "${token,,}" in
      weekday|weekdays)
        printf '%s\n' Monday Tuesday Wednesday Thursday Friday
        ;;
      weekend|weekends)
        printf '%s\n' Saturday Sunday
        ;;
      all|daily|everyday)
        printf '%s\n' Monday Tuesday Wednesday Thursday Friday Saturday Sunday
        ;;
      *)
        canonical_day "$token" || {
          echo "Invalid day in schedule: $token" >&2
          return 1
        }
        ;;
    esac
  done < <(csv_words "$1")
}

time_to_minutes() {
  local raw="${1:-}"
  local hour minute
  if [[ "$raw" =~ ^([0-9]{1,2}):([0-9]{2})$ ]]; then
    hour="${BASH_REMATCH[1]}"
    minute="${BASH_REMATCH[2]}"
  elif [[ "$raw" =~ ^([0-9]{1,2})([0-9]{2})$ ]]; then
    hour="${BASH_REMATCH[1]}"
    minute="${BASH_REMATCH[2]}"
  else
    echo "Invalid time '$raw'; expected HH:MM or HHMM" >&2
    return 1
  fi
  if (( 10#$hour > 23 || 10#$minute > 59 )); then
    echo "Invalid time '$raw'; hour must be 0-23 and minute must be 0-59" >&2
    return 1
  fi
  printf '%s\n' "$((10#$hour * 60 + 10#$minute))"
}

normalize_time_for_date() {
  local raw="${1:-}"
  local hour minute
  if [[ "$raw" =~ ^([0-9]{1,2}):([0-9]{2})$ ]]; then
    hour="${BASH_REMATCH[1]}"
    minute="${BASH_REMATCH[2]}"
  elif [[ "$raw" =~ ^([0-9]{1,2})([0-9]{2})$ ]]; then
    hour="${BASH_REMATCH[1]}"
    minute="${BASH_REMATCH[2]}"
  else
    echo "Invalid time '$raw'; expected HH:MM or HHMM" >&2
    return 1
  fi
  printf '%02d:%02d\n' "$((10#$hour))" "$((10#$minute))"
}

local_time_to_utc_day_hhmm() {
  local timezone="$1"
  local day="$2"
  local time_value="$3"
  local add_days="${4:-0}"
  local local_date normalized epoch
  local_date="$(date -d "TZ=\"$timezone\" $day 00:00" '+%F')"
  normalized="$(normalize_time_for_date "$time_value")"
  epoch="$(TZ="$timezone" date -d "$local_date $normalized" '+%s')"
  epoch="$((epoch + add_days * 86400))"
  date -u -d "@$epoch" '+%A %H%M'
}

is_weekend_day() {
  case "$1" in
    Saturday|Sunday) return 0 ;;
    *) return 1 ;;
  esac
}

ini_set() {
  local file="$1"
  local section="$2"
  local key="$3"
  local value="$4"
  local tmp
  tmp="$(mktemp)"
  awk -v section="$section" -v key="$key" -v value="$value" '
    BEGIN {
      target = "[" section "]"
      in_target = 0
      seen_section = 0
      wrote_key = 0
    }
    $0 == target {
      if (seen_section && !wrote_key) {
        print key "=" value
        wrote_key = 1
      }
      in_target = 1
      seen_section = 1
      print
      next
    }
    /^\[/ {
      if (in_target && !wrote_key) {
        print key "=" value
        wrote_key = 1
      }
      in_target = 0
    }
    in_target && index($0, key "=") == 1 {
      if (!wrote_key) {
        print key "=" value
        wrote_key = 1
      }
      next
    }
    { print }
    END {
      if (!seen_section) {
        print ""
        print target
        print key "=" value
      } else if (in_target && !wrote_key) {
        print key "=" value
      }
    }
  ' "$file" > "$tmp"
  cat "$tmp" > "$file"
  rm -f "$tmp"
}

latest_save_mtime() {
  local save_dir="${1:-}"
  local latest=0
  local file ts
  shopt -s nullglob
  for file in "$save_dir"/*.db "$save_dir"/*.db-wal "$save_dir"/*.db-shm; do
    ts="$(stat -c '%Y' "$file" 2>/dev/null || printf '0')"
    if (( ts > latest )); then
      latest="$ts"
    fi
  done
  shopt -u nullglob
  printf '%s\n' "$latest"
}

server_config_dir() {
  printf '%s/ConanSandbox/Saved/Config/LinuxServer\n' "${SERVER_DIR:-/data/server}"
}

saved_dir() {
  printf '%s/ConanSandbox/Saved\n' "${SERVER_DIR:-/data/server}"
}

server_setting_is_sensitive() {
  case "$1" in
    AdminPassword|ServerPassword) return 0 ;;
    *) return 1 ;;
  esac
}

server_setting_allowed() {
  local key="$1"
  local allowlist="$2"
  grep -Fxq "$key" "$allowlist"
}

apply_server_setting_overrides() {
  local file="$1"
  local allowlist="$2"
  local key value line env_name override_key applied=0

  while IFS= read -r key; do
    [[ -z "$key" || "$key" == \#* ]] && continue
    if server_setting_is_sensitive "$key"; then
      continue
    fi
    if printenv "$key" >/dev/null 2>&1; then
      value="$(printenv "$key")"
      ini_set "$file" "ServerSettings" "$key" "$value"
      log_info "Applied ServerSettings override from env: $key"
      applied=$((applied + 1))
    fi
    env_name="CONAN_SETTING_$key"
    if printenv "$env_name" >/dev/null 2>&1; then
      value="$(printenv "$env_name")"
      ini_set "$file" "ServerSettings" "$key" "$value"
      log_info "Applied ServerSettings override from env: $env_name -> $key"
      applied=$((applied + 1))
    fi
  done < "$allowlist"

  while IFS= read -r line; do
    env_name="${line%%=*}"
    [[ "$env_name" == CONAN_SETTING_* ]] || continue
    override_key="${env_name#CONAN_SETTING_}"
    if ! server_setting_allowed "$override_key" "$allowlist"; then
      log_warn "Ignoring unknown ServerSettings override: $env_name"
    fi
  done < <(env)

  log_info "Applied $applied advanced ServerSettings override(s)"
}
