#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

require_nonempty ADMIN_PASSWORD "${ADMIN_PASSWORD:-}"
reject_placeholder ADMIN_PASSWORD "${ADMIN_PASSWORD:-}" change-me admin password
if truthy "${RCON_ENABLED:-true}"; then
  require_nonempty RCON_PASSWORD "${RCON_PASSWORD:-}"
  reject_placeholder RCON_PASSWORD "${RCON_PASSWORD:-}" change-me-rcon rcon password
fi
require_choice COMMUNITY "${COMMUNITY:-0}" 0 1 2 3 4
require_choice SERVER_REGION "${SERVER_REGION:-0}" 0 1 2 3 4 5
require_choice SERVER_VOICE_CHAT "${SERVER_VOICE_CHAT:-0}" 0 1

config_dir="$(server_config_dir)"
mkdir -p "$config_dir"

engine_ini="$config_dir/Engine.ini"
game_ini="$config_dir/Game.ini"
settings_ini="$config_dir/ServerSettings.ini"
touch "$engine_ini" "$game_ini" "$settings_ini"

ini_set "$engine_ini" "OnlineSubsystemSteam" "ServerName" "${SERVER_NAME:-Conan Exiles Enhanced Server}"
ini_set "$engine_ini" "OnlineSubsystemSteam" "ServerPassword" "${SERVER_PASSWORD:-}"
ini_set "$engine_ini" "URL" "Port" "${SERVER_PORT:-7777}"
ini_set "$engine_ini" "URL" "PeerPort" "${RAW_UDP_PORT:-7778}"

ini_set "$game_ini" "RconPlugin" "RconEnabled" "$(truthy "${RCON_ENABLED:-true}" && echo True || echo False)"
ini_set "$game_ini" "RconPlugin" "RconPassword" "${RCON_PASSWORD:-}"
ini_set "$game_ini" "RconPlugin" "RconPort" "${RCON_PORT:-25575}"

ini_set "$settings_ini" "ServerSettings" "AdminPassword" "${ADMIN_PASSWORD:-}"
ini_set "$settings_ini" "ServerSettings" "ServerPassword" "${SERVER_PASSWORD:-}"
ini_set "$settings_ini" "ServerSettings" "MaxPlayers" "${MAX_PLAYERS:-40}"
ini_set "$settings_ini" "ServerSettings" "PVPEnabled" "${PVP_ENABLED:-true}"
ini_set "$settings_ini" "ServerSettings" "ServerCommunity" "${COMMUNITY:-0}"
ini_set "$settings_ini" "ServerSettings" "serverRegion" "${SERVER_REGION:-0}"
ini_set "$settings_ini" "ServerSettings" "serverVoiceChat" "${SERVER_VOICE_CHAT:-0}"
ini_set "$settings_ini" "ServerSettings" "BattlEyeEnabled" "${ENABLE_BATTLEYE:-true}"
ini_set "$settings_ini" "ServerSettings" "CanDamagePlayerOwnedStructures" "${CAN_DAMAGE_PLAYER_OWNED_STRUCTURES:-false}"
ini_set "$settings_ini" "ServerSettings" "clanMaxSize" "${CLAN_MAX_SIZE:-10}"
ini_set "$settings_ini" "ServerSettings" "AllowBuildingAnywhere" "${ALLOW_BUILDING_ANYWHERE:-false}"
ini_set "$settings_ini" "ServerSettings" "BuildingAbandonmentEnabled" "${BUILDING_ABANDONMENT_ENABLED:-true}"
ini_set "$settings_ini" "ServerSettings" "DropEquipmentOnDeath" "${DROP_EQUIPMENT_ON_DEATH:-true}"
ini_set "$settings_ini" "ServerSettings" "DropBackpackOnDeath" "${DROP_BACKPACK_ON_DEATH:-true}"
ini_set "$settings_ini" "ServerSettings" "AvatarsDisabled" "$(truthy "${AVATAR_ENABLED:-true}" && echo false || echo true)"
ini_set "$settings_ini" "ServerSettings" "HarvestAmountMultiplier" "${HARVEST_AMOUNT_MULTIPLIER:-1.0}"
ini_set "$settings_ini" "ServerSettings" "PlayerXPRateMultiplier" "${XP_RATE_MULTIPLIER:-1.0}"
ini_set "$settings_ini" "ServerSettings" "PlayerXPKillMultiplier" "${PLAYER_XP_KILL_MULTIPLIER:-1.0}"
ini_set "$settings_ini" "ServerSettings" "PlayerXPTimeMultiplier" "${PLAYER_XP_TIME_MULTIPLIER:-1.0}"
ini_set "$settings_ini" "ServerSettings" "PlayerXPCraftMultiplier" "${PLAYER_XP_CRAFT_MULTIPLIER:-1.0}"
ini_set "$settings_ini" "ServerSettings" "PlayerXPHarvestMultiplier" "${PLAYER_XP_HARVEST_MULTIPLIER:-1.0}"
ini_set "$settings_ini" "ServerSettings" "DayCycleSpeedScale" "${DAY_CYCLE_SPEED_SCALE:-1.0}"
ini_set "$settings_ini" "ServerSettings" "DayTimeSpeedScale" "${DAY_TIME_SPEED_SCALE:-1.0}"
ini_set "$settings_ini" "ServerSettings" "NightTimeSpeedScale" "${NIGHT_TIME_SPEED_SCALE:-1.0}"
ini_set "$settings_ini" "ServerSettings" "PlayerHealthRegenSpeedScale" "${PLAYER_HEALTH_REGEN_SPEED_SCALE:-1.0}"
ini_set "$settings_ini" "ServerSettings" "PlayerStaminaCostSprintMultiplier" "${PLAYER_STAMINA_COST_SPRINT_MULTIPLIER:-1.0}"
ini_set "$settings_ini" "ServerSettings" "PlayerStaminaCostMultiplier" "${PLAYER_STAMINA_COST_MULTIPLIER:-1.0}"
ini_set "$settings_ini" "ServerSettings" "NPCRespawnMultiplier" "${NPC_RESPAWN_MULTIPLIER:-1.0}"
ini_set "$settings_ini" "ServerSettings" "ThrallConversionMultiplier" "${THRALL_CONVERSION_MULTIPLIER:-1.0}"
ini_set "$settings_ini" "ServerSettings" "CraftingCostMultiplier" "${CRAFTING_COST_MULTIPLIER:-1.0}"
ini_set "$settings_ini" "ServerSettings" "FuelBurnTimeMultiplier" "${FUEL_BURN_TIME_MULTIPLIER:-1.0}"
ini_set "$settings_ini" "ServerSettings" "ItemSpoilRateScale" "${ITEM_SPOIL_RATE_SCALE:-1.0}"
