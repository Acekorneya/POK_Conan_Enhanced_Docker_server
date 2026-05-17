# Conan Exiles Enhanced Dedicated Server for Linux

Docker project for the native Linux Conan Exiles Enhanced dedicated server. It installs Steam app `443030`, uses the Linux depot, keeps all mutable data on host volumes, runs the game as `pokuser`, supports RCON health checks, installs ordered Workshop mods, and creates automatic backups.

The default Compose file pulls the published image:

```text
acekorneya/conan_enhanced_server:latest
```

## Quick Start

```bash
cp .env.example .env
edit .env
docker compose up -d
```

Required settings before first start:

```env
ADMIN_PASSWORD=your-strong-admin-password
RCON_PASSWORD=your-strong-rcon-password
```

The first boot downloads the server, so it can take a while.

For end users, the only required files are:

```text
docker-compose.yml
.env
```

They do not need the Dockerfile or scripts when using the published image. If they prefer the `.yaml` extension, they can rename `docker-compose.yml` to `docker-compose.yaml`; Docker Compose accepts either.

## Volumes

```text
./data/server   Steam server install, Conan saves, configs, and mods
./data/steam    SteamCMD cache and Workshop downloads
./data/backups  Backup archives
```

These paths are bind-mounted so restarts, rebuilds, and container replacement keep the server state.

## Ports

Default published ports:

```text
7777/udp   Game
7778/udp   Raw UDP peer port
27015/udp  Steam query
```

RCON is enabled inside the container for health checks and shutdown saves, but it is not published to the host by default. To expose it:

```bash
docker compose -f docker-compose.yml -f docker-compose.rcon.yml up -d
```

## User and Permissions

Set `PUID` and `PGID` in `.env` to match the host account that should own files under `./data`.

The image default user is `pokuser`, so interactive shells are non-root:

```bash
docker compose exec conan bash
id
```

Startup uses a narrow sudo helper to update `pokuser` to the configured UID/GID and chown mounted volumes before the server process starts.

## Updates

`AUTO_UPDATE=true` runs SteamCMD update on container start and enables the periodic update monitor while the server is running. Set it to `false` to skip startup updates when server files already exist and disable the monitor.

The monitor checks Steam build IDs on this interval:

```env
AUTO_UPDATE_CHECK_INTERVAL_HOURS=6
AUTO_UPDATE_RESTART_NOTICE_MINUTES=30
```

When a new build is detected, the container broadcasts restart warnings at countdown marks, sends RCON `shutdown`, waits for save-file timestamp activity, updates the server with SteamCMD, reapplies config and mods, relaunches the game, and verifies health with RCON.

Manual update:

```bash
docker compose run --rm conan update
```

## Watchdog

The container has an internal watchdog that restarts only the Conan server process when repeated health checks fail:

```env
SERVER_WATCHDOG_ENABLED=true
SERVER_WATCHDOG_INTERVAL_SECONDS=60
SERVER_WATCHDOG_FAILURE_THRESHOLD=3
SERVER_WATCHDOG_STARTUP_GRACE_SECONDS=600
SERVER_WATCHDOG_RESTART_COOLDOWN_SECONDS=300
SERVER_WATCHDOG_MAX_RESTARTS=3
SERVER_STOP_GRACE_SECONDS=10
```

The watchdog checks that the tracked Conan process is still running. It no longer restarts the game only because RCON misses a reply, which avoids launching a second server while the first one is still alive. After the failure threshold is reached, it uses the same graceful RCON `shutdown` path, verifies that all Conan processes stopped, relaunches the server, and verifies health again. If the old process cannot stop within `SERVER_STOP_GRACE_SECONDS`, or repeated recovery restarts exceed `SERVER_WATCHDOG_MAX_RESTARTS`, the container exits non-zero so Docker's restart policy can recreate it.

## Local Image Builds

Most users should not build the image locally. Maintainers can build from this repository with:

```bash
docker compose -f docker-compose.yml -f docker-compose.build.yml build
```

## Mods

Set ordered Workshop IDs in `.env`:

```env
MOD_IDS=123456789,987654321
```

On start, each item is downloaded with SteamCMD, its `.pak` plus matching `.ucas/.utoc` files are copied into `ConanSandbox/Mods`, and `modlist.txt` is generated in the same order.

## Server Settings

Common settings are documented in `.env.example`. Advanced `ServerSettings.ini` keys can also be passed directly without adding every possible key to the example file:

```env
AvatarLifetime=600
MaxAllowedPing=300
BuildingPickupEnabled=False
```

Local-time schedule helpers use `TZ` and render UTC values into `ServerSettings.ini`:

```env
TZ=America/Los_Angeles
PVP_BUILDING_DAMAGE_DAYS=weekends
PVP_BUILDING_DAMAGE_START=11:00
PVP_BUILDING_DAMAGE_END=23:00
RAID_BROADCASTS_ENABLED=true
AVATAR_SUMMONING_DAYS=weekends
AVATAR_SUMMONING_START=11:00
AVATAR_SUMMONING_END=23:00
```

Days accept `Monday` through `Sunday` plus shortcuts: `weekdays`, `weekends`, and `all`.

When `RAID_BROADCASTS_ENABLED=true`, the container sends raid-window warnings 1 hour, 30 minutes, and 5 minutes before the building damage window starts and ends, plus start/end notices.

## Backups

Backups run every `BACKUP_INTERVAL_MINUTES` and again during graceful shutdown when `BACKUP_ON_STOP=true`.

Each archive includes:

- save databases from `ConanSandbox/Saved`
- Linux server config INI files
- `Mods/modlist.txt`
- metadata

Retention is controlled with `BACKUP_RETENTION_COUNT`.

Manual backup:

```bash
docker compose run --rm conan backup
```

## Graceful Shutdown

On `docker compose stop`, restart, or a normal TERM/INT signal, the container:

1. sends an optional RCON broadcast
2. runs Conan RCON `shutdown`
3. waits for save-file timestamp activity
4. creates a final backup
5. terminates the server process

Normal Docker stops use this immediate graceful path rather than the automatic update countdown. A raw `SIGKILL` cannot be trapped by Docker or the game, so scheduled backups are still important.

## RCON

Run RCON commands from inside the container:

```bash
docker compose exec conan rcon help
docker compose exec conan rcon listplayers
```

## Scheduled Broadcasts

Set an optional repeating message in `.env` to promote Discord or send any recurring admin notice:

```env
SERVER_BROADCAST_MESSAGE=Join our Discord: https://discord.gg/example
SERVER_BROADCAST_INTERVAL_MINUTES=120
```

Leave `SERVER_BROADCAST_MESSAGE` blank to disable scheduled broadcasts. The first message is sent after one full interval, then repeats on the same interval.

## Tests

Run shell tests with Bats:

```bash
tests/run_tests.sh
```

Useful static checks:

```bash
docker compose config
shellcheck scripts/*.sh scripts/entrypoint scripts/root-entrypoint
```

## Notes

This project targets Conan Exiles Enhanced native Linux server files. Legacy Wine/Xvfb server setups are intentionally out of scope.
