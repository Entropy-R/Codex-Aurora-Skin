#!/bin/bash

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
LINUX_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
REPOSITORY_ROOT="$(cd "$LINUX_ROOT/.." && pwd -P)"
DESTINATION="${1:-}"

[ -n "$DESTINATION" ] || {
  printf 'Usage: %s DESTINATION\n' "$0" >&2
  exit 2
}
[ ! -e "$DESTINATION" ] || {
  printf 'Destination already exists: %s\n' "$DESTINATION" >&2
  exit 1
}

mkdir -p "$DESTINATION/scripts" "$DESTINATION/assets" "$DESTINATION/vendor"
cp "$LINUX_ROOT/VERSION" "$DESTINATION/VERSION"
cp "$LINUX_ROOT/scripts/"*.sh "$LINUX_ROOT/scripts/injector.mjs" "$DESTINATION/scripts/"
mkdir -p "$DESTINATION/manager/web"
cp "$REPOSITORY_ROOT/manager/server.mjs" \
  "$REPOSITORY_ROOT/manager/theme-store.mjs" \
  "$REPOSITORY_ROOT/manager/image-metadata.mjs" \
  "$REPOSITORY_ROOT/manager/heartbeat-lease.mjs" "$DESTINATION/manager/"
cp "$REPOSITORY_ROOT/manager/web/index.html" \
  "$REPOSITORY_ROOT/manager/web/styles.css" \
  "$REPOSITORY_ROOT/manager/web/app.js" \
  "$REPOSITORY_ROOT/manager/web/api-client.mjs" "$DESTINATION/manager/web/"
cp -a "$REPOSITORY_ROOT/library" "$DESTINATION/library"
cp "$REPOSITORY_ROOT/macos/assets/aurora-skin.css" \
  "$REPOSITORY_ROOT/macos/assets/renderer-inject.js" \
  "$REPOSITORY_ROOT/macos/assets/selectors.json" "$DESTINATION/assets/"
cp "$REPOSITORY_ROOT/macos/scripts/injector.mjs" "$DESTINATION/vendor/injector.mjs"
cp "$REPOSITORY_ROOT/macos/scripts/image-metadata.mjs" \
  "$DESTINATION/vendor/image-metadata.mjs"
cp "$REPOSITORY_ROOT/LICENSE" "$REPOSITORY_ROOT/NOTICE.md" "$DESTINATION/"
cp "$LINUX_ROOT/README.md" "$DESTINATION/README.md"

chmod 755 "$DESTINATION/scripts/"*.sh
chmod 644 "$DESTINATION/scripts/injector.mjs" "$DESTINATION/vendor/"*.mjs
find "$DESTINATION" -type d -exec chmod 755 {} +
find "$DESTINATION" -type f ! -path '*/scripts/*.sh' -exec chmod 644 {} +

printf 'assembled=%s\n' "$DESTINATION"
