#!/usr/bin/env bash

truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
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
