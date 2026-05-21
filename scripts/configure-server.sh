#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

SERVER_SETTINGS_KEYS_FILE="${SERVER_SETTINGS_KEYS_FILE:-/usr/local/share/conan-enhanced/config/server-settings-keys.txt}"
if [[ ! -f "$SERVER_SETTINGS_KEYS_FILE" && -f "$SCRIPT_DIR/../config/server-settings-keys.txt" ]]; then
  SERVER_SETTINGS_KEYS_FILE="$SCRIPT_DIR/../config/server-settings-keys.txt"
fi

apply_weekly_schedule() {
  local file="$1"
  local env_prefix="$2"
  local label="$3"
  local restrict_key="$4"
  local enabled_prefix="$5"
  local time_prefix="$6"
  local days_var="${env_prefix}_DAYS"
  local start_var="${env_prefix}_START"
  local end_var="${env_prefix}_END"
  local days="${!days_var-}"
  local start="${!start_var-}"
  local end="${!end_var-}"
  local timezone="${TZ:-UTC}"
  local local_start_minutes local_end_minutes add_end_day
  local expanded_days
  local day utc_start utc_start_day utc_start_time utc_end utc_end_time
  local all_days=(Monday Tuesday Wednesday Thursday Friday Saturday Sunday)

  if [[ -z "$days" && -z "$start" && -z "$end" ]]; then
    return 0
  fi
  require_nonempty "$days_var" "$days"
  require_nonempty "$start_var" "$start"
  require_nonempty "$end_var" "$end"

  local_start_minutes="$(time_to_minutes "$start")"
  local_end_minutes="$(time_to_minutes "$end")"
  add_end_day=0
  if (( local_end_minutes <= local_start_minutes )); then
    add_end_day=1
  fi

  log_info "$label local window: $days $start-$end $timezone"
  expanded_days="$(expand_day_tokens "$days")"
  ini_set "$file" "ServerSettings" "$restrict_key" "True"
  for day in "${all_days[@]}"; do
    ini_set "$file" "ServerSettings" "${enabled_prefix}${day}" "False"
    ini_set "$file" "ServerSettings" "${time_prefix}${day}Start" "0"
    ini_set "$file" "ServerSettings" "${time_prefix}${day}End" "0"
  done

  while IFS= read -r day; do
    [[ -n "$day" ]] || continue
    utc_start="$(local_time_to_utc_day_hhmm "$timezone" "$day" "$start" 0)"
    utc_start_day="${utc_start% *}"
    utc_start_time="${utc_start#* }"
    utc_end="$(local_time_to_utc_day_hhmm "$timezone" "$day" "$end" "$add_end_day")"
    utc_end_time="${utc_end#* }"
    ini_set "$file" "ServerSettings" "${enabled_prefix}${utc_start_day}" "True"
    ini_set "$file" "ServerSettings" "${time_prefix}${utc_start_day}Start" "$utc_start_time"
    ini_set "$file" "ServerSettings" "${time_prefix}${utc_start_day}End" "$utc_end_time"
    log_info "$label UTC window: $utc_start_day $utc_start_time-$utc_end_time"
  done <<< "$expanded_days"
}

reset_weekly_schedule() {
  local file="$1"
  local restrict_key="$2"
  local enabled_prefix="$3"
  local time_prefix="$4"
  local day
  local all_days=(Monday Tuesday Wednesday Thursday Friday Saturday Sunday)

  ini_set "$file" "ServerSettings" "$restrict_key" "False"
  for day in "${all_days[@]}"; do
    ini_set "$file" "ServerSettings" "${enabled_prefix}${day}" "False"
    ini_set "$file" "ServerSettings" "${time_prefix}${day}Start" "0"
    ini_set "$file" "ServerSettings" "${time_prefix}${day}End" "0"
  done
}

apply_avatar_schedule() {
  local file="$1"
  local days="${AVATAR_SUMMONING_DAYS:-}"
  local start="${AVATAR_SUMMONING_START:-}"
  local end="${AVATAR_SUMMONING_END:-}"
  local timezone="${TZ:-UTC}"
  local local_start_minutes local_end_minutes add_end_day
  local expanded_days
  local day utc_start utc_start_time utc_end utc_end_time group
  local weekday_written=false weekend_written=false

  if [[ -z "$days" && -z "$start" && -z "$end" ]]; then
    # Clean reset if no summon schedule is set
    ini_set "$file" "ServerSettings" "RestrictAvatarSummoningTime" "False"
    ini_set "$file" "ServerSettings" "AvatarSummoningTimeWeekdayStart" "0"
    ini_set "$file" "ServerSettings" "AvatarSummoningTimeWeekdayEnd" "0"
    ini_set "$file" "ServerSettings" "AvatarSummoningTimeWeekendStart" "0"
    ini_set "$file" "ServerSettings" "AvatarSummoningTimeWeekendEnd" "0"
    return 0
  fi
  require_nonempty AVATAR_SUMMONING_DAYS "$days"
  require_nonempty AVATAR_SUMMONING_START "$start"
  require_nonempty AVATAR_SUMMONING_END "$end"

  local_start_minutes="$(time_to_minutes "$start")"
  local_end_minutes="$(time_to_minutes "$end")"
  add_end_day=0
  if (( local_end_minutes <= local_start_minutes )); then
    add_end_day=1
  fi

  log_info "Avatar summoning local window: $days $start-$end $timezone"
  expanded_days="$(expand_day_tokens "$days")"
  ini_set "$file" "ServerSettings" "RestrictAvatarSummoningTime" "True"
  ini_set "$file" "ServerSettings" "AvatarSummoningTimeWeekdayStart" "0"
  ini_set "$file" "ServerSettings" "AvatarSummoningTimeWeekdayEnd" "0"
  ini_set "$file" "ServerSettings" "AvatarSummoningTimeWeekendStart" "0"
  ini_set "$file" "ServerSettings" "AvatarSummoningTimeWeekendEnd" "0"

  while IFS= read -r day; do
    [[ -n "$day" ]] || continue
    if is_weekend_day "$day"; then
      group="Weekend"
      if [[ "$weekend_written" == true ]]; then
        continue
      fi
      weekend_written=true
    else
      group="Weekday"
      if [[ "$weekday_written" == true ]]; then
        continue
      fi
      weekday_written=true
    fi
    utc_start="$(local_time_to_utc_day_hhmm "$timezone" "$day" "$start" 0)"
    utc_start_time="${utc_start#* }"
    utc_end="$(local_time_to_utc_day_hhmm "$timezone" "$day" "$end" "$add_end_day")"
    utc_end_time="${utc_end#* }"
    ini_set "$file" "ServerSettings" "AvatarSummoningTime${group}Start" "$utc_start_time"
    ini_set "$file" "ServerSettings" "AvatarSummoningTime${group}End" "$utc_end_time"
    log_info "Avatar summoning UTC $group window: $utc_start_time-$utc_end_time"
  done <<< "$expanded_days"

  if [[ "$days" != *Saturday* && "$days" != *Sunday* && "${days,,}" != *weekend* ]]; then
    log_warn "Avatar summoning supports only weekday/weekend windows, not individual weekday selection"
  fi
}

schedule_summary() {
  local prefix="$1"
  local days_var="${prefix}_DAYS"
  local start_var="${prefix}_START"
  local end_var="${prefix}_END"
  local days="${!days_var-}"
  local start="${!start_var-}"
  local end="${!end_var-}"
  if [[ -n "$days" || -n "$start" || -n "$end" ]]; then
    printf '%s %s-%s %s' "$days" "$start" "$end" "${TZ:-UTC}"
  else
    printf 'unrestricted'
  fi
}

log_effective_server_settings() {
  log_section "Effective Server Settings"
  log_info "Browser: Community=$(community_label "${COMMUNITY:-0}") Region=$(region_label "${SERVER_REGION:-0}") VoiceChat=$(voice_chat_label "${SERVER_VOICE_CHAT:-0}")"
  log_info "Rules: PvP=${PVP_ENABLED:-true} BuildingDamage=${CAN_DAMAGE_PLAYER_OWNED_STRUCTURES:-false} BattlEye=${ENABLE_BATTLEYE:-true} ClanMaxSize=${CLAN_MAX_SIZE:-10} BuildingAnywhere=${ALLOW_BUILDING_ANYWHERE:-false} BuildingAbandonment=${BUILDING_ABANDONMENT_ENABLED:-true}"
  log_info "Death and avatars: DropEquipment=${DROP_EQUIPMENT_ON_DEATH:-1} DropBackpack=${DROP_BACKPACK_ON_DEATH:-1} EverybodyCanLootCorpse=${EVERYBODY_CAN_LOOT_CORPSE:-true} Avatars=${AVATAR_ENABLED:-true} MaxNudity=${MAX_NUDITY:-0}"
  log_info "Progression rates: Harvest=${HARVEST_AMOUNT_MULTIPLIER:-1.0} XP=${XP_RATE_MULTIPLIER:-1.0} KillXP=${PLAYER_XP_KILL_MULTIPLIER:-1.0} TimeXP=${PLAYER_XP_TIME_MULTIPLIER:-1.0} CraftXP=${PLAYER_XP_CRAFT_MULTIPLIER:-1.0} HarvestXP=${PLAYER_XP_HARVEST_MULTIPLIER:-1.0}"
  log_info "World rates: DayCycle=${DAY_CYCLE_SPEED_SCALE:-1.0} Day=${DAY_TIME_SPEED_SCALE:-1.0} Night=${NIGHT_TIME_SPEED_SCALE:-1.0} HealthRegen=${PLAYER_HEALTH_REGEN_SPEED_SCALE:-1.0} SprintStamina=${PLAYER_STAMINA_COST_SPRINT_MULTIPLIER:-1.0} Stamina=${PLAYER_STAMINA_COST_MULTIPLIER:-1.0}"
  log_info "Crafting and NPC rates: NPCRespawn=${NPC_RESPAWN_MULTIPLIER:-1.0} ThrallConversion=${THRALL_CONVERSION_MULTIPLIER:-0.5} CraftingCost=${CRAFTING_COST_MULTIPLIER:-1.0} FuelBurn=${FUEL_BURN_TIME_MULTIPLIER:-1.0} Spoil=${ITEM_SPOIL_RATE_SCALE:-1.0}"
  log_info "Schedules: PvP=$(schedule_summary PVP_TIME) BuildingDamage=$(schedule_summary PVP_BUILDING_DAMAGE) AvatarSummoning=$(schedule_summary AVATAR_SUMMONING)"
}

# Support both ENABLE_BATTLEYE and enable_battleye (case-insensitive env var fallback)
ENABLE_BATTLEYE="${ENABLE_BATTLEYE:-${enable_battleye:-true}}"

require_nonempty ADMIN_PASSWORD "${ADMIN_PASSWORD:-}"
reject_placeholder ADMIN_PASSWORD "${ADMIN_PASSWORD:-}" change-me admin password
if truthy "${RCON_ENABLED:-true}"; then
  require_nonempty RCON_PASSWORD "${RCON_PASSWORD:-}"
  reject_placeholder RCON_PASSWORD "${RCON_PASSWORD:-}" change-me-rcon rcon password
fi
require_choice COMMUNITY "${COMMUNITY:-0}" 0 1 2 3 4
require_choice SERVER_REGION "${SERVER_REGION:-0}" 0 1 2 3 4 5
require_choice SERVER_VOICE_CHAT "${SERVER_VOICE_CHAT:-0}" 0 1
if [[ ! -f "$SERVER_SETTINGS_KEYS_FILE" ]]; then
  log_error "ServerSettings allowlist not found: $SERVER_SETTINGS_KEYS_FILE"
  exit 1
fi

log_section "Conan Configuration"
log_info "Server name: ${SERVER_NAME:-Conan Exiles Enhanced Server}"
log_info "Message of the Day: ${SERVER_MESSAGE_OF_THE_DAY:-none}"
log_info "Max players: ${MAX_PLAYERS:-40}"
log_info "Join password: $(password_state "${SERVER_PASSWORD:-}")"
log_info "Admin password: $(secret_state "${ADMIN_PASSWORD:-}")"
log_info "RCON: $(truthy "${RCON_ENABLED:-true}" && echo enabled || echo disabled), password=$(secret_state "${RCON_PASSWORD:-}"), port=${RCON_PORT:-25575}"
log_info "Ports: game=${SERVER_PORT:-7777}/udp raw=${RAW_UDP_PORT:-7778}/udp query=${QUERY_PORT:-27015}/udp bind=${MULTIHOME:-0.0.0.0}"
log_info "Rules: PvP=${PVP_ENABLED:-true} Community=$(community_label "${COMMUNITY:-0}") Region=$(region_label "${SERVER_REGION:-0}") VoiceChat=$(voice_chat_label "${SERVER_VOICE_CHAT:-0}")"
log_info "Advanced ServerSettings allowlist: $SERVER_SETTINGS_KEYS_FILE"

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

ini_set "$game_ini" "RconPlugin" "RconEnabled" "$(truthy "${RCON_ENABLED:-true}" && echo 1 || echo 0)"
ini_set "$game_ini" "RconPlugin" "RconPassword" "${RCON_PASSWORD:-}"
ini_set "$game_ini" "RconPlugin" "RconPort" "${RCON_PORT:-25575}"

ini_set "$settings_ini" "ServerSettings" "AdminPassword" "${ADMIN_PASSWORD:-}"
ini_set "$settings_ini" "ServerSettings" "ServerPassword" "${SERVER_PASSWORD:-}"
ini_set "$settings_ini" "ServerSettings" "ServerMessageOfTheDay" "${SERVER_MESSAGE_OF_THE_DAY:-}"
ini_set "$settings_ini" "ServerSettings" "MaxPlayers" "${MAX_PLAYERS:-40}"
ini_set "$settings_ini" "ServerSettings" "PVPEnabled" "$(bool_ini "${PVP_ENABLED:-true}")"
ini_set "$settings_ini" "ServerSettings" "ServerCommunity" "${COMMUNITY:-0}"
ini_set "$settings_ini" "ServerSettings" "serverRegion" "${SERVER_REGION:-0}"
ini_set "$settings_ini" "ServerSettings" "serverVoiceChat" "${SERVER_VOICE_CHAT:-0}"
ini_set "$settings_ini" "ServerSettings" "IsBattlEyeEnabled" "$(bool_ini "${ENABLE_BATTLEYE:-true}")"
ini_set "$settings_ini" "ServerSettings" "CanDamagePlayerOwnedStructures" "$(bool_ini "${CAN_DAMAGE_PLAYER_OWNED_STRUCTURES:-false}")"
ini_set "$settings_ini" "ServerSettings" "clanMaxSize" "${CLAN_MAX_SIZE:-10}"
ini_set "$settings_ini" "ServerSettings" "AllowBuildingAnywhere" "${ALLOW_BUILDING_ANYWHERE:-false}"
ini_set "$settings_ini" "ServerSettings" "BuildingAbandonmentEnabled" "${BUILDING_ABANDONMENT_ENABLED:-true}"
ini_set "$settings_ini" "ServerSettings" "DropEquipmentOnDeath" "${DROP_EQUIPMENT_ON_DEATH:-1}"
ini_set "$settings_ini" "ServerSettings" "DropBackpackOnDeath" "${DROP_BACKPACK_ON_DEATH:-1}"
ini_set "$settings_ini" "ServerSettings" "EverybodyCanLootCorpse" "${EVERYBODY_CAN_LOOT_CORPSE:-true}"
ini_set "$settings_ini" "ServerSettings" "AvatarsDisabled" "$(truthy "${AVATAR_ENABLED:-true}" && echo false || echo true)"
ini_set "$settings_ini" "ServerSettings" "MaxNudity" "${MAX_NUDITY:-0}"
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
ini_set "$settings_ini" "ServerSettings" "ThrallConversionMultiplier" "${THRALL_CONVERSION_MULTIPLIER:-0.5}"
ini_set "$settings_ini" "ServerSettings" "CraftingCostMultiplier" "${CRAFTING_COST_MULTIPLIER:-1.0}"
ini_set "$settings_ini" "ServerSettings" "FuelBurnTimeMultiplier" "${FUEL_BURN_TIME_MULTIPLIER:-1.0}"
ini_set "$settings_ini" "ServerSettings" "ItemSpoilRateScale" "${ITEM_SPOIL_RATE_SCALE:-1.0}"

# PvP schedule configuration (respected regardless of PVP_ENABLED for PvE with PvP times)
if [[ -n "${PVP_TIME_DAYS:-}" && -n "${PVP_TIME_START:-}" && -n "${PVP_TIME_END:-}" ]]; then
  apply_weekly_schedule "$settings_ini" "PVP_TIME" "PvP" "RestrictPVPTime" "PVPEnabled" "PVPTime"
else
  reset_weekly_schedule "$settings_ini" "RestrictPVPTime" "PVPEnabled" "PVPTime"
fi

# Building damage (Raid) schedule configuration (respected regardless of PVP_ENABLED for PvE with scheduled raid times)
if [[ -n "${PVP_BUILDING_DAMAGE_DAYS:-}" && -n "${PVP_BUILDING_DAMAGE_START:-}" && -n "${PVP_BUILDING_DAMAGE_END:-}" ]]; then
  apply_weekly_schedule "$settings_ini" "PVP_BUILDING_DAMAGE" "Building damage" "RestrictPVPBuildingDamageTime" "PVPBuildingDamageEnabled" "PVPBuildingDamageTime"
  ini_set "$settings_ini" "ServerSettings" "CanDamagePlayerOwnedStructures" "True"
else
  reset_weekly_schedule "$settings_ini" "RestrictPVPBuildingDamageTime" "PVPBuildingDamageEnabled" "PVPBuildingDamageTime"
  if truthy "${PVP_ENABLED:-true}" && truthy "${CAN_DAMAGE_PLAYER_OWNED_STRUCTURES:-false}"; then
    ini_set "$settings_ini" "ServerSettings" "CanDamagePlayerOwnedStructures" "True"
  else
    ini_set "$settings_ini" "ServerSettings" "CanDamagePlayerOwnedStructures" "False"
  fi
fi
apply_avatar_schedule "$settings_ini"
apply_server_setting_overrides "$settings_ini" "$SERVER_SETTINGS_KEYS_FILE"
log_effective_server_settings

log_info "Config files written to $config_dir"
