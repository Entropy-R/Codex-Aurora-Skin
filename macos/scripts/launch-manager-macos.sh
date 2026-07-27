#!/bin/bash

set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd -P)/common-macos.sh"

ensure_state_root
ensure_node_runtime
exec "$NODE" "$PROJECT_ROOT/manager/server.mjs" \
  --platform macos \
  --engine-root "$PROJECT_ROOT" \
  --state-root "$STATE_ROOT" \
  --active-root "$THEME_DIR" \
  --node "$NODE" \
  --injector "$INJECTOR" \
  --start "$SCRIPT_DIR/start-aurora-skin-macos.sh" \
  --restore "$SCRIPT_DIR/restore-aurora-skin-macos.sh" \
  --open
