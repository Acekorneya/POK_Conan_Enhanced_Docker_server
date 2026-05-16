#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

SERVER_DIR="${SERVER_DIR:-/data/server}"
BACKUP_DIR="${BACKUP_DIR:-/data/backups}"
BACKUP_RETENTION_COUNT="${BACKUP_RETENTION_COUNT:-30}"
reason="${1:-scheduled}"

mkdir -p "$BACKUP_DIR"

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
workdir="$(mktemp -d)"
archive="$BACKUP_DIR/conan-${timestamp}-${reason}.tar.gz"
trap 'rm -rf "$workdir"' EXIT

saved="$(saved_dir)"
config="$(server_config_dir)"
mkdir -p "$workdir/saves" "$workdir/config" "$workdir/mods"

shopt -s nullglob
for db in "$saved"/*.db; do
  sqlite3 "$db" ".backup '$workdir/saves/$(basename "$db")'" || cp -f "$db" "$workdir/saves/"
done
for sidecar in "$saved"/*.db-wal "$saved"/*.db-shm; do
  cp -f "$sidecar" "$workdir/saves/" 2>/dev/null || true
done
for cfg in "$config"/*.ini; do
  cp -f "$cfg" "$workdir/config/"
done
if [[ -f "$SERVER_DIR/ConanSandbox/Mods/modlist.txt" ]]; then
  cp -f "$SERVER_DIR/ConanSandbox/Mods/modlist.txt" "$workdir/mods/modlist.txt"
fi
shopt -u nullglob

cat > "$workdir/metadata.txt" <<META
created_utc=$timestamp
reason=$reason
server_name=${SERVER_NAME:-}
mod_ids=${MOD_IDS:-}
META

tar -C "$workdir" -czf "$archive" .
echo "Created backup: $archive"

require_uint BACKUP_RETENTION_COUNT "$BACKUP_RETENTION_COUNT"
if (( BACKUP_RETENTION_COUNT > 0 )); then
  mapfile -t old_backups < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name 'conan-*.tar.gz' -printf '%T@ %p\n' | sort -nr | awk -v keep="$BACKUP_RETENTION_COUNT" 'NR > keep {print $2}')
  for old in "${old_backups[@]}"; do
    rm -f "$old"
  done
fi
