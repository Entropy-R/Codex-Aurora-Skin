#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
. "$ROOT/scripts/common-linux.sh"

TEST_NODE_SOURCE="${NODE:-$(command -v node)}"
TEST_NODE_SOURCE="$(readlink -f "$TEST_NODE_SOURCE")"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-aurora-identity.XXXXXX")"
TEST_NODE="$TEMP_ROOT/node"
REPLACEMENT_NODE="$TEMP_ROOT/node.replacement"
OTHER_NODE="$TEMP_ROOT/other-node"
TEST_INJECTOR="$TEMP_ROOT/injector.mjs"
TEST_PID=""

cleanup() {
  if [ -n "$TEST_PID" ] && kill -0 "$TEST_PID" 2>/dev/null; then
    kill -TERM "$TEST_PID" 2>/dev/null || true
    wait "$TEST_PID" 2>/dev/null || true
  fi
  rm -f "$TEST_NODE" "$REPLACEMENT_NODE" "$OTHER_NODE" "$TEST_INJECTOR"
  rmdir "$TEMP_ROOT" 2>/dev/null || true
}
trap cleanup EXIT

cp "$TEST_NODE_SOURCE" "$TEST_NODE"
cp "$TEST_NODE_SOURCE" "$REPLACEMENT_NODE"
cp "$TEST_NODE_SOURCE" "$OTHER_NODE"
printf 'setInterval(() => {}, 1000);\n' > "$TEST_INJECTOR"

"$TEST_NODE" "$TEST_INJECTOR" --watch --port 19431 &
TEST_PID="$!"
sleep 0.2
TEST_STARTED_AT="$(process_start_ticks "$TEST_PID")"
[ -n "$TEST_STARTED_AT" ]

# 原路径被新包文件替换后，运行中进程的 /proc/exe 带有内核 deleted 标记。
mv "$REPLACEMENT_NODE" "$TEST_NODE"
[ "$(readlink "/proc/$TEST_PID/exe")" = "$TEST_NODE (deleted)" ]
process_executable_matches_path "$TEST_PID" "$TEST_NODE"
CHATGPT_EXE="$TEST_NODE"
pid_is_chatgpt "$TEST_PID"
grep -Fxq "$TEST_PID" < <(chatgpt_pids)
recorded_injector_matches \
  "$TEST_PID" "$TEST_STARTED_AT" "$TEST_NODE" "$TEST_INJECTOR" 19431

if process_executable_matches_path "$TEST_PID" "$OTHER_NODE"; then
  printf 'FAIL: 不同的可执行文件路径不应通过身份校验。\n' >&2
  exit 1
fi
if recorded_injector_matches \
  "$TEST_PID" "$TEST_STARTED_AT" "$OTHER_NODE" "$TEST_INJECTOR" 19431; then
  printf 'FAIL: 不同的 Node 路径不应通过身份校验。\n' >&2
  exit 1
fi
if recorded_injector_matches \
  "$TEST_PID" "$TEST_STARTED_AT" "$TEST_NODE" "$TEST_INJECTOR" 19432; then
  printf 'FAIL: 不同的端口不应通过身份校验。\n' >&2
  exit 1
fi

printf 'PASS: Linux 注入器身份支持软件包升级后的 deleted 可执行文件。\n'
