#!/usr/bin/env bash
set -euo pipefail

if [[ "${RCON_ENABLED:-true}" != "true" && "${RCON_ENABLED:-true}" != "1" ]]; then
  pgrep -f 'ConanSandboxServer' >/dev/null
  exit $?
fi

/usr/local/bin/rcon-wrapper.sh help >/dev/null

