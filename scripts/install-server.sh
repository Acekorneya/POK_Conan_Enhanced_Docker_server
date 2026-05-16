#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

SERVER_DIR="${SERVER_DIR:-/data/server}"
STEAM_DIR="${STEAM_DIR:-/data/steam}"
AUTO_UPDATE="${AUTO_UPDATE:-true}"
STEAM_BRANCH="${STEAM_BRANCH:-public}"
STEAM_VALIDATE="${STEAM_VALIDATE:-false}"

server_binary="$SERVER_DIR/ConanSandbox/Binaries/Linux/ConanSandboxServer-Linux-Shipping"
force="${1:-}"

if [[ "$force" != "force" ]] && [[ -x "$server_binary" ]] && ! truthy "$AUTO_UPDATE"; then
  echo "Server files already exist and AUTO_UPDATE is false; skipping SteamCMD update."
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

HOME="$STEAM_DIR" /opt/steamcmd/steamcmd.sh "${args[@]}"
