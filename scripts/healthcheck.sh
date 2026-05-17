#!/usr/bin/env bash
set -euo pipefail

if ! pgrep -f 'ConanSandboxServer' >/dev/null; then
  echo "ConanSandboxServer process not found" >&2
  exit 1
fi

if [[ "${HEALTHCHECK_REQUIRE_RCON:-false}" == "true" || "${HEALTHCHECK_REQUIRE_RCON:-false}" == "1" ]]; then
  /usr/local/bin/rcon-wrapper.sh help >/dev/null
  exit $?
fi

if [[ "${RCON_ENABLED:-true}" == "true" || "${RCON_ENABLED:-true}" == "1" ]]; then
  /usr/local/bin/rcon-wrapper.sh help >/dev/null 2>&1 || true
fi

exit 0
