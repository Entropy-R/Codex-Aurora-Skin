#!/bin/bash

set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd -P)/common-linux.sh"

PORT=9341
PORT_EXPLICIT="false"
RESTART_CHATGPT="false"
UNINSTALL="false"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --port) PORT="${2:-}"; PORT_EXPLICIT="true"; shift 2 ;;
    --restart-codex|--restart-chatgpt) RESTART_CHATGPT="true"; shift ;;
    --uninstall) UNINSTALL="true"; shift ;;
    *) fail "未知恢复参数：$1" ;;
  esac
done

discover_chatgpt
ensure_state_root
HAD_SESSION="false"
if [ -f "$STATE_PATH" ]; then
  HAD_SESSION="true"
  if [ "$PORT_EXPLICIT" = "false" ]; then
    PORT="$(state_field port 2>/dev/null || true)"
  fi
  case "$PORT" in ''|*[!0-9]*) fail "已保存的 CDP 端口无效，状态已保留。" ;; esac
  stop_recorded_injector
fi

DEBUG_READY="false"
verified_cdp_endpoint "$PORT" && DEBUG_READY="true"
if [ "$DEBUG_READY" = "true" ]; then
  "$NODE" "$INJECTOR" --remove --port "$PORT" --theme-dir "$THEME_DIR" \
    --timeout-ms 10000 >/dev/null \
    || fail "实时皮肤未能安全移除，恢复操作已停止。"
elif [ "$HAD_SESSION" = "true" ] && chatgpt_is_running && [ "$RESTART_CHATGPT" != "true" ]; then
  fail "ChatGPT 仍在运行，但已保存的 CDP 无法验证；完整恢复需要明确允许重启。"
fi

if [ "$RESTART_CHATGPT" = "true" ] && [ "$HAD_SESSION" = "true" ]; then
  chatgpt_is_running && stop_chatgpt true
  launch_chatgpt_normally
fi

rm -f "$STATE_PATH"
if [ "$UNINSTALL" = "true" ]; then
  applications_dir="${XDG_DATA_HOME:-$USER_HOME/.local/share}/applications"
  bin_dir="$USER_HOME/.local/bin"
  for launcher in \
    "$applications_dir/codex-aurora-skin.desktop" \
    "$applications_dir/codex-aurora-skin-restore.desktop" \
    "$bin_dir/codex-aurora-skin" \
    "$bin_dir/codex-aurora-skin-restore"; do
    if [ -f "$launcher" ] && [ ! -L "$launcher" ] \
      && grep -Fq 'CodexAuroraSkin launcher' "$launcher"; then
      rm -f "$launcher"
    fi
  done
fi

printf 'Codex Aurora Skin 已恢复为 ChatGPT 官方外观。\n'
