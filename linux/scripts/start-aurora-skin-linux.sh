#!/bin/bash

set -Eeuo pipefail
. "$(cd "$(dirname "$0")" && pwd -P)/common-linux.sh"

PORT=9341
PORT_EXPLICIT="false"
RESTART_EXISTING="false"
FOREGROUND_INJECTOR="false"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --port) PORT="${2:-}"; PORT_EXPLICIT="true"; shift 2 ;;
    --restart-existing) RESTART_EXISTING="true"; shift ;;
    --foreground-injector) FOREGROUND_INJECTOR="true"; shift ;;
    *) fail "未知启动参数：$1" ;;
  esac
done
case "$PORT" in ''|*[!0-9]*) fail "端口无效：$PORT" ;; esac
[ "$PORT" -ge 1024 ] && [ "$PORT" -le 65535 ] || fail "端口必须在 1024 到 65535 之间。"

ensure_state_root
discover_chatgpt
[ -f "$THEME_DIR/theme.json" ] || fail "尚无活动主题，请先打开主题管理器完成初始化。"

if [ "$PORT_EXPLICIT" = "false" ] && [ -f "$STATE_PATH" ]; then
  saved_port="$(state_field port 2>/dev/null || true)"
  case "$saved_port" in ''|*[!0-9]*) ;; *) PORT="$saved_port" ;; esac
fi

DEBUG_READY="false"
verified_cdp_endpoint "$PORT" && DEBUG_READY="true"
if chatgpt_is_running && [ "$DEBUG_READY" = "false" ]; then
  [ "$RESTART_EXISTING" = "true" ] \
    || fail "ChatGPT 已打开但没有已验证的主题 CDP；请关闭应用或明确允许重启。"
  stop_chatgpt true
fi

if [ -f "$STATE_PATH" ]; then
  stop_recorded_injector
fi

if [ "$DEBUG_READY" = "false" ]; then
  PORT="$(select_available_port "$PORT")"
  printf '正在通过回环 CDP 端口 %s 启动 ChatGPT…\n' "$PORT" >&2
  launch_chatgpt_with_cdp "$PORT"
  if ! wait_for_cdp "$PORT"; then
    chatgpt_is_running && stop_chatgpt true || true
    launch_chatgpt_normally || true
    fail "ChatGPT 未在 45 秒内开放已验证的回环 CDP，请查看 $APP_ERROR_LOG"
  fi
fi

if [ "$FOREGROUND_INJECTOR" = "true" ]; then
  exec "$NODE" "$INJECTOR" --watch --port "$PORT" --theme-dir "$THEME_DIR"
fi

INJECTOR_PID="$(launch_injector_daemon "$PORT")"
INJECTOR_STARTED_AT="$(process_start_ticks "$INJECTOR_PID")"
[ -n "$INJECTOR_STARTED_AT" ] || fail "无法记录注入器进程启动时间。"
BROWSER_ID="$(cdp_browser_id "$PORT")" || fail "无法记录 CDP 浏览器身份。"
write_state "$PORT" "$INJECTOR_PID" "$INJECTOR_STARTED_AT" "$BROWSER_ID"

VERIFY_CODE=1
for attempt in 1 2 3; do
  if "$NODE" "$INJECTOR" --verify --port "$PORT" --theme-dir "$THEME_DIR" \
    --timeout-ms 15000 >/dev/null 2>>"$INJECTOR_ERROR_LOG"; then
    VERIFY_CODE=0
    break
  fi
  "$NODE" "$INJECTOR" --once --port "$PORT" --theme-dir "$THEME_DIR" \
    --timeout-ms 12000 >/dev/null 2>>"$INJECTOR_ERROR_LOG" || true
  [ "$attempt" -eq 3 ] || sleep 2
done

if [ "$VERIFY_CODE" -ne 0 ]; then
  stop_recorded_injector || true
  rm -f "$STATE_PATH"
  fail "主题注入未通过显示校验，注入器已停止；请查看 $INJECTOR_ERROR_LOG"
fi

mark_state_active
printf 'Codex Aurora Skin %s 已在回环端口 %s 生效。\n' "$SKIN_VERSION" "$PORT"
