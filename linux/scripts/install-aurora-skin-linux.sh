#!/bin/bash

set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd -P)/common-linux.sh"

CREATE_LAUNCHERS="true"
LAUNCH_AFTER_INSTALL="true"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --no-launchers) CREATE_LAUNCHERS="false"; shift ;;
    --no-launch) LAUNCH_AFTER_INSTALL="false"; shift ;;
    *) fail "未知安装参数：$1" ;;
  esac
done

discover_chatgpt
if [ -f "$STATE_PATH" ]; then
  fail "检测到现有主题会话；升级前请先执行恢复官方外观。"
fi

SOURCE_LINK="$(find "$PLATFORM_ROOT/scripts" "$SHARED_ROOT/manager" \
  "$SHARED_ROOT/library" "$ASSETS_ROOT" -type l -print -quit 2>/dev/null || true)"
[ -z "$SOURCE_LINK" ] || fail "安装源包含符号链接，拒绝部署：$SOURCE_LINK"

DATA_ROOT="$DATA_HOME/codex-aurora-skin"
STAGING_ROOT="$DATA_ROOT/.engine-staging-$$"
BACKUP_ROOT="$DATA_ROOT/engine.backup.$(date -u '+%Y%m%dT%H%M%SZ')"
ensure_private_directory "$DATA_ROOT"
[ ! -e "$STAGING_ROOT" ] || fail "临时安装目录已存在：$STAGING_ROOT"
mkdir -p "$STAGING_ROOT/scripts" "$STAGING_ROOT/assets" "$STAGING_ROOT/vendor" \
  "$STAGING_ROOT/manager/web"
chmod 700 "$STAGING_ROOT" "$STAGING_ROOT/scripts" "$STAGING_ROOT/assets" \
  "$STAGING_ROOT/vendor" "$STAGING_ROOT/manager" "$STAGING_ROOT/manager/web"

cp "$PLATFORM_ROOT/VERSION" "$STAGING_ROOT/VERSION"
cp "$PLATFORM_ROOT/scripts/"*.sh "$PLATFORM_ROOT/scripts/injector.mjs" "$STAGING_ROOT/scripts/"
cp "$SHARED_ROOT/manager/server.mjs" "$SHARED_ROOT/manager/theme-store.mjs" \
  "$SHARED_ROOT/manager/image-metadata.mjs" \
  "$SHARED_ROOT/manager/heartbeat-lease.mjs" "$STAGING_ROOT/manager/"
cp "$SHARED_ROOT/manager/web/index.html" "$SHARED_ROOT/manager/web/styles.css" \
  "$SHARED_ROOT/manager/web/app.js" "$SHARED_ROOT/manager/web/api-client.mjs" \
  "$STAGING_ROOT/manager/web/"
cp -a "$SHARED_ROOT/library" "$STAGING_ROOT/library"
cp "$ASSETS_ROOT/aurora-skin.css" "$ASSETS_ROOT/renderer-inject.js" \
  "$ASSETS_ROOT/selectors.json" "$STAGING_ROOT/assets/"
if [ -f "$SHARED_ROOT/macos/scripts/injector.mjs" ]; then
  INJECTOR_SOURCE="$SHARED_ROOT/macos/scripts/injector.mjs"
  IMAGE_METADATA_SOURCE="$SHARED_ROOT/macos/scripts/image-metadata.mjs"
else
  INJECTOR_SOURCE="$PLATFORM_ROOT/vendor/injector.mjs"
  IMAGE_METADATA_SOURCE="$PLATFORM_ROOT/vendor/image-metadata.mjs"
fi
cp "$INJECTOR_SOURCE" "$STAGING_ROOT/vendor/injector.mjs"
cp "$IMAGE_METADATA_SOURCE" "$STAGING_ROOT/vendor/image-metadata.mjs"
cp "$SHARED_ROOT/LICENSE" "$SHARED_ROOT/NOTICE.md" "$STAGING_ROOT/"
chmod 700 "$STAGING_ROOT/scripts/"*.sh
chmod 600 "$STAGING_ROOT/scripts/injector.mjs" "$STAGING_ROOT/vendor/injector.mjs"

for required in \
  VERSION scripts/common-linux.sh scripts/launch-manager-linux.sh \
  scripts/start-aurora-skin-linux.sh scripts/restore-aurora-skin-linux.sh \
  scripts/injector.mjs vendor/injector.mjs vendor/image-metadata.mjs assets/aurora-skin.css \
  assets/renderer-inject.js assets/selectors.json manager/server.mjs \
  library/catalog.json; do
  [ -f "$STAGING_ROOT/$required" ] || fail "暂存引擎不完整：$required"
done

if [ -e "$INSTALL_ROOT" ]; then
  [ ! -e "$BACKUP_ROOT" ] || fail "备份目录已存在：$BACKUP_ROOT"
  mv "$INSTALL_ROOT" "$BACKUP_ROOT"
fi
if ! mv "$STAGING_ROOT" "$INSTALL_ROOT"; then
  [ ! -e "$BACKUP_ROOT" ] || mv "$BACKUP_ROOT" "$INSTALL_ROOT"
  fail "无法提交 Linux 引擎安装。"
fi

write_launcher_script() {
  local target="$1" command="$2"
  if [ -e "$target" ] && ! grep -Fq 'CodexAuroraSkin launcher' "$target" 2>/dev/null; then
    fail "拒绝覆盖无关启动文件：$target"
  fi
  printf '%s\n' \
    '#!/bin/bash' \
    '# CodexAuroraSkin launcher' \
    'set -e' \
    "exec $(printf '%q' "$command") \"\$@\"" > "$target"
  chmod 700 "$target"
}

write_desktop_entry() {
  local target="$1" name="$2" executable="$3"
  if [ -e "$target" ] && ! grep -Fq 'CodexAuroraSkin launcher' "$target" 2>/dev/null; then
    fail "拒绝覆盖无关桌面入口：$target"
  fi
  printf '%s\n' \
    '# CodexAuroraSkin launcher' \
    '[Desktop Entry]' \
    'Type=Application' \
    "Name=$name" \
    'Comment=管理 Codex Aurora Skin 本地主题' \
    "Exec=\"$executable\"" \
    'Icon=preferences-desktop-theme' \
    'Terminal=false' \
    'Categories=Utility;' > "$target"
  chmod 600 "$target"
}

if [ "$CREATE_LAUNCHERS" = "true" ]; then
  BIN_DIR="$USER_HOME/.local/bin"
  APPLICATIONS_DIR="$DATA_HOME/applications"
  mkdir -p "$BIN_DIR" "$APPLICATIONS_DIR"
  write_launcher_script "$BIN_DIR/codex-aurora-skin" \
    "$INSTALL_ROOT/scripts/launch-manager-linux.sh"
  write_launcher_script "$BIN_DIR/codex-aurora-skin-restore" \
    "$INSTALL_ROOT/scripts/restore-aurora-skin-linux.sh"
  write_desktop_entry "$APPLICATIONS_DIR/codex-aurora-skin.desktop" \
    'Codex Aurora Skin' "$BIN_DIR/codex-aurora-skin"
  write_desktop_entry "$APPLICATIONS_DIR/codex-aurora-skin-restore.desktop" \
    'Codex Aurora Skin - 恢复官方外观' "$BIN_DIR/codex-aurora-skin-restore"
  command -v update-desktop-database >/dev/null 2>&1 \
    && update-desktop-database "$APPLICATIONS_DIR" >/dev/null 2>&1 || true
fi

printf 'Codex Aurora Skin %s 已安装到 %s，ChatGPT %s，Node.js %s。\n' \
  "$SKIN_VERSION" "$INSTALL_ROOT" "$CHATGPT_VERSION" "$NODE_VERSION"
[ ! -e "$BACKUP_ROOT" ] || printf '上一版引擎已保留在 %s。\n' "$BACKUP_ROOT"

if [ "$LAUNCH_AFTER_INSTALL" = "true" ]; then
  exec "$INSTALL_ROOT/scripts/launch-manager-linux.sh"
fi
