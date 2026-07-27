#!/bin/bash

set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd -P)/common-macos.sh"

migrate_legacy_user_data
[ -f "$THEME_BACKUP_PATH" ] || exit 0
[ -f "$CONFIG_PATH" ] || exit 0
ensure_node_runtime
codex_is_running && exit 0

appearance="$("$NODE" -e '
const fs = require("node:fs");
let value = "auto";
try { value = JSON.parse(fs.readFileSync(process.argv[1], "utf8")).appearance; } catch {}
process.stdout.write(value === "light" || value === "dark" ? value : "auto");
' "$THEME_DIR/theme.json")"
archive="$STATE_ROOT/theme-backup.archived.json"
if [ -e "$archive" ]; then
  archive="$STATE_ROOT/theme-backup.archived.$(/bin/date +%Y%m%d%H%M%S).json"
fi
"$NODE" "$SCRIPT_DIR/theme-config.mjs" migrate \
  "$CONFIG_PATH" "$THEME_BACKUP_PATH" "$appearance" "$archive"
