#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

SERVER_DIR="${SERVER_DIR:-/data/server}"
STEAM_DIR="${STEAM_DIR:-/data/steam}"
STEAMCMD_DIR="${STEAMCMD_DIR:-/opt/steamcmd}"
MOD_IDS="${MOD_IDS:-}"
mods_dir="$SERVER_DIR/ConanSandbox/Mods"
workshop_dir="$STEAM_DIR/steamapps/workshop/content/440900"

log_section "Workshop Mods"

mkdir -p "$mods_dir"
modlist="$mods_dir/modlist.txt"
: > "$modlist"

ids=()
while IFS= read -r id; do
  [[ -n "$id" ]] && ids+=("$id")
done < <(csv_words "$MOD_IDS")

if (( ${#ids[@]} == 0 )); then
  log_info "No mods configured"
  exit 0
fi

log_info "Installing ${#ids[@]} Workshop mod(s): ${ids[*]}"

for id in "${ids[@]}"; do
  require_uint MOD_IDS "$id"
  log_info "Downloading Workshop item $id"
  HOME="$STEAM_DIR" "$STEAMCMD_DIR/steamcmd.sh" \
    +force_install_dir "$STEAM_DIR" \
    +login anonymous \
    +workshop_download_item 440900 "$id" \
    +quit

  item_dir="$workshop_dir/$id"
  if [[ ! -d "$item_dir" ]]; then
    echo "Workshop item $id did not download to $item_dir" >&2
    exit 1
  fi

  mapfile -t paks < <(find "$item_dir" -maxdepth 2 -type f -name '*.pak' | sort)
  if (( ${#paks[@]} == 0 )); then
    echo "Workshop item $id does not contain a .pak file" >&2
    exit 1
  fi
  if (( ${#paks[@]} > 1 )); then
    echo "Workshop item $id contains multiple .pak files; refusing ambiguous mod install" >&2
    printf '%s\n' "${paks[@]}" >&2
    exit 1
  fi

  pak="${paks[0]}"
  base="${pak%.pak}"
  log_info "Installing mod package $(basename "$pak")"
  cp -f "$pak" "$mods_dir/"
  for companion in "$base".ucas "$base".utoc; do
    [[ -f "$companion" ]] && cp -f "$companion" "$mods_dir/"
  done
  printf '%s\n' "$(basename "$pak")" >> "$modlist"
done

log_info "Generated mod list: $modlist"
