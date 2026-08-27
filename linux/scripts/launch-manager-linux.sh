#!/bin/bash

set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd -P)/common-linux.sh"

ensure_state_root
discover_chatgpt
exec "$NODE" "$SHARED_ROOT/manager/server.mjs" \
  --platform linux \
  --engine-root "$SHARED_ROOT" \
  --state-root "$STATE_ROOT" \
  --active-root "$THEME_DIR" \
  --node "$NODE" \
  --injector "$INJECTOR" \
  --start "$SCRIPT_DIR/start-aurora-skin-linux.sh" \
  --restore "$SCRIPT_DIR/restore-aurora-skin-linux.sh" \
  --open
