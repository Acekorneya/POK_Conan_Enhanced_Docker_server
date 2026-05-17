#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

SERVER_DIR="${SERVER_DIR:-/data/server}"
STEAM_DIR="${STEAM_DIR:-/data/steam}"
STEAMCMD_DIR="${STEAMCMD_DIR:-/opt/steamcmd}"
AUTO_UPDATE="${AUTO_UPDATE:-true}"
STEAM_BRANCH="${STEAM_BRANCH:-public}"
STEAM_VALIDATE="${STEAM_VALIDATE:-false}"

server_binary="$SERVER_DIR/ConanSandbox/Binaries/Linux/ConanSandboxServer-Linux-Shipping"
force="${1:-}"

log_section "SteamCMD Server Install/Update"
log_info "Steam app: 443030"
log_info "Server files: $SERVER_DIR"
log_info "Steam cache: $STEAM_DIR"
log_info "AUTO_UPDATE=$AUTO_UPDATE STEAM_BRANCH=$STEAM_BRANCH STEAM_VALIDATE=$STEAM_VALIDATE"

if [[ "$force" != "force" ]] && [[ -x "$server_binary" ]] && ! truthy "$AUTO_UPDATE"; then
  log_info "Server binary exists and AUTO_UPDATE is false; skipping SteamCMD update"
  exit 0
fi

mkdir -p "$SERVER_DIR" "$STEAM_DIR"

args=(
  +force_install_dir "$SERVER_DIR"
  +login anonymous
  +app_update 443030
)

if [[ "$STEAM_BRANCH" != "public" && -n "$STEAM_BRANCH" ]]; then
  args+=(-beta "$STEAM_BRANCH")
fi

if truthy "$STEAM_VALIDATE"; then
  args+=(validate)
fi

args+=(+quit)

if [[ ! -x "$STEAMCMD_DIR/steamcmd.sh" ]]; then
  log_error "$STEAMCMD_DIR/steamcmd.sh is not executable"
  ls -la "$STEAMCMD_DIR" >&2 || true
  exit 1
fi

if [[ "$force" == "force" ]]; then
  log_info "Manual update requested; running SteamCMD"
elif [[ -x "$server_binary" ]]; then
  log_info "Server binary exists; checking for updates with SteamCMD"
else
  log_info "Server binary not found; installing server with SteamCMD"
fi

HOME="$STEAM_DIR" "$STEAMCMD_DIR/steamcmd.sh" "${args[@]}"
log_info "SteamCMD install/update completed successfully"
