#!/bin/bash

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
REPOSITORY_ROOT="$(cd "$ROOT/.." && pwd -P)"
if [ -z "${NODE:-}" ] && [ -x /usr/lib/chatgpt/resources/cua_node/bin/node ]; then
  NODE=/usr/lib/chatgpt/resources/cua_node/bin/node
else
  NODE="${NODE:-$(command -v node)}"
fi

while IFS= read -r script; do
  bash -n "$script"
done < <(find "$ROOT/scripts" "$ROOT/installer" -type f -name '*.sh' -print 2>/dev/null)

while IFS= read -r source; do
  "$NODE" --check "$source" >/dev/null
done < <(find "$ROOT/scripts" "$REPOSITORY_ROOT/manager" \
  -type f \( -name '*.mjs' -o -name '*.js' \) -print)

"$NODE" --test "$ROOT"/tests/*.test.mjs
"$NODE" --test "$REPOSITORY_ROOT"/manager/*.test.mjs
CODEX_AURORA_SKIN_ASSETS_ROOT="$REPOSITORY_ROOT/macos/assets" \
  "$NODE" "$ROOT/scripts/injector.mjs" --check-payload \
  --theme-dir "$REPOSITORY_ROOT/library/preset-red-white-abstract" >/dev/null
"$NODE" "$REPOSITORY_ROOT/tools/sync-runtime-assets.mjs" --check >/dev/null
"$NODE" "$REPOSITORY_ROOT/tools/verify-library.mjs" >/dev/null

printf 'PASS: Linux 脚本、共享管理器、离线主题库与注入载荷。\n'
