#!/bin/bash

set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd -P)/common-linux.sh"

REQUIRE_LIVE="false"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --require-live) REQUIRE_LIVE="true"; shift ;;
    *) fail "未知诊断参数：$1" ;;
  esac
done

discover_chatgpt
for required in \
  "$ASSETS_ROOT/aurora-skin.css" \
  "$ASSETS_ROOT/renderer-inject.js" \
  "$ASSETS_ROOT/selectors.json" \
  "$SHARED_ROOT/library/catalog.json" \
  "$SHARED_ROOT/manager/server.mjs" \
  "$INJECTOR"; do
  [ -s "$required" ] || fail "运行时文件缺失或为空：$required"
done

PAYLOAD_JSON="$($NODE "$INJECTOR" --check-payload --theme-dir "$SHARED_ROOT/library/preset-red-white-abstract")"
PORT=9341
[ -f "$STATE_PATH" ] && PORT="$(state_field port)"
LIVE="false"
if [ -f "$STATE_PATH" ] && verified_cdp_endpoint "$PORT"; then
  "$NODE" "$INJECTOR" --verify --port "$PORT" --theme-dir "$THEME_DIR" \
    --timeout-ms 12000 >/dev/null
  LIVE="true"
fi
[ "$REQUIRE_LIVE" = "false" ] || [ "$LIVE" = "true" ] \
  || fail "当前没有通过验证的 Linux 主题会话。"

"$NODE" -e '
  const payload = JSON.parse(process.argv[1]);
  console.log(JSON.stringify({
    pass: true,
    product: "Codex Aurora Skin",
    version: process.argv[2],
    platform: `linux-${process.argv[3]}`,
    chatgptVersion: process.argv[4],
    packageKind: process.argv[5],
    nodeVersion: process.argv[6],
    packagedFilesVerified: true,
    modifiesAppAsar: false,
    live: process.argv[7] === "true",
    port: Number(process.argv[8]),
    theme: {
      id: payload.themeId,
      name: payload.themeName,
      imageBytes: payload.imageBytes,
      payloadBytes: payload.payloadBytes,
    },
  }, null, 2));
' "$PAYLOAD_JSON" "$SKIN_VERSION" "$(uname -m)" "$CHATGPT_VERSION" \
  "$CHATGPT_PACKAGE_KIND" "$NODE_VERSION" "$LIVE" "$PORT"
