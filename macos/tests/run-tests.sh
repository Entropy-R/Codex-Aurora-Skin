#!/bin/bash

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
REPOSITORY_ROOT="$(cd "$ROOT/.." && pwd -P)"
NODE="${NODE:-$(command -v node)}"

while IFS= read -r script; do
  /bin/bash -n "$script"
done < <(/usr/bin/find "$ROOT/scripts" -type f -name '*.sh' -print)

while IFS= read -r source; do
  "$NODE" --check "$source" >/dev/null
done < <(/usr/bin/find "$ROOT/scripts" "$REPOSITORY_ROOT/manager" \
  -type f \( -name '*.mjs' -o -name '*.js' \) -print)

"$NODE" --test "$ROOT"/tests/*.test.mjs
"$NODE" --test "$REPOSITORY_ROOT"/manager/*.test.mjs
"$NODE" "$ROOT/scripts/injector.mjs" --check-payload \
  --theme-dir "$REPOSITORY_ROOT/library/preset-red-white-abstract" >/dev/null
"$NODE" "$REPOSITORY_ROOT/tools/sync-runtime-assets.mjs" --check >/dev/null
"$NODE" "$REPOSITORY_ROOT/tools/verify-library.mjs" >/dev/null

for forbidden in \
  "$ROOT/scripts/check-update-macos.sh" \
  "$ROOT/scripts/install-menubar-macos.sh" \
  "$ROOT/menubar/codex_dream_skin.10s.sh"; do
  [ ! -e "$forbidden" ] || {
    printf '已移除功能或受限素材仍存在：%s\n' "$forbidden" >&2
    exit 1
  }
done

if /usr/bin/grep -R -n -E 'promo(Title|Sub|Url)' \
  "$REPOSITORY_ROOT/library" "$REPOSITORY_ROOT/manager" "$ROOT/scripts" \
  "$ROOT/menubar-app" >/dev/null; then
  printf '公开运行时仍包含推广、旧仓库或宣传字段。\n' >&2
  exit 1
fi

printf 'PASS: macOS 启动器、共享管理器、离线主题库与运行时资源。\n'
