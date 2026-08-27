#!/bin/bash

set -euo pipefail

USER_HOME="${HOME:-}"
if [ -z "$USER_HOME" ]; then
  USER_HOME="$(getent passwd "$(id -u)" | cut -d: -f6)"
  [ -n "$USER_HOME" ] || {
    printf 'Codex Aurora Skin: 无法确定当前用户主目录。\n' >&2
    exit 1
  }
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PLATFORM_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
if [ -f "$PLATFORM_ROOT/manager/server.mjs" ]; then
  ENGINE_ROOT="$PLATFORM_ROOT"
  SHARED_ROOT="$PLATFORM_ROOT"
  ASSETS_ROOT="$PLATFORM_ROOT/assets"
else
  ENGINE_ROOT="$PLATFORM_ROOT"
  SHARED_ROOT="$(cd "$PLATFORM_ROOT/.." && pwd -P)"
  ASSETS_ROOT="$SHARED_ROOT/macos/assets"
fi

DATA_HOME="${XDG_DATA_HOME:-$USER_HOME/.local/share}"
STATE_HOME="${XDG_STATE_HOME:-$USER_HOME/.local/state}"
INSTALL_ROOT="$DATA_HOME/codex-aurora-skin/engine"
STATE_ROOT="$DATA_HOME/codex-aurora-skin/state"
LOG_ROOT="$STATE_HOME/codex-aurora-skin"
STATE_PATH="$STATE_ROOT/state.json"
THEME_DIR="$STATE_ROOT/theme"
INJECTOR="$SCRIPT_DIR/injector.mjs"
INJECTOR_LOG="$LOG_ROOT/injector.log"
INJECTOR_ERROR_LOG="$LOG_ROOT/injector-error.log"
APP_LOG="$LOG_ROOT/chatgpt-launch.log"
APP_ERROR_LOG="$LOG_ROOT/chatgpt-launch-error.log"
SKIN_VERSION="$(tr -d '\r\n' < "$PLATFORM_ROOT/VERSION")"
CODEX_AURORA_SKIN_ASSETS_ROOT="$ASSETS_ROOT"
export CODEX_AURORA_SKIN_ASSETS_ROOT

fail() {
  printf 'Codex Aurora Skin: %s\n' "$*" >&2
  exit 1
}

ensure_private_directory() {
  local directory="$1"
  mkdir -p "$directory"
  chmod 700 "$directory"
  [ ! -L "$directory" ] || fail "拒绝使用符号链接目录：$directory"
}

ensure_state_root() {
  ensure_private_directory "$STATE_ROOT"
  ensure_private_directory "$LOG_ROOT"
}

canonical_existing_path() {
  local input="$1"
  [ -e "$input" ] || return 1
  readlink -f -- "$input"
}

machine_architecture() {
  case "$(uname -m)" in
    x86_64) printf 'amd64\n' ;;
    aarch64|arm64) printf 'arm64\n' ;;
    *) fail "不支持的处理器架构：$(uname -m)" ;;
  esac
}

assert_packaged_file() {
  local file="$1"
  [ -f "$file" ] || fail "ChatGPT 包文件不存在：$file"
  [ ! -L "$file" ] || fail "ChatGPT 包文件不能是符号链接：$file"
  [ ! -w "$file" ] || fail "ChatGPT 包文件可被当前用户修改，拒绝使用：$file"

  if [ "$CHATGPT_PACKAGE_KIND" = "deb" ]; then
    dpkg-query -S "$file" 2>/dev/null | grep -Eq '^chatgpt: ' \
      || fail "文件不属于已登记的 chatgpt 软件包：$file"
    local manifest="/var/lib/dpkg/info/chatgpt.md5sums"
    local relative="${file#/}"
    local expected actual
    expected="$(awk -v target="$relative" '$2 == target { print $1; exit }' "$manifest")"
    [ -n "$expected" ] || fail "chatgpt 软件包校验清单缺少：$relative"
    actual="$(md5sum "$file" | awk '{print $1}')"
    [ "$actual" = "$expected" ] || fail "ChatGPT 包文件完整性校验失败：$file"
  else
    rpm -qf "$file" --qf '%{NAME}\n' 2>/dev/null | grep -Fxq chatgpt \
      || fail "文件不属于已登记的 chatgpt RPM：$file"
    local dump algorithm expected actual
    dump="$(rpm -q --dump chatgpt | awk -v target="$file" '$1 == target { print; exit }')"
    [ -n "$dump" ] || fail "chatgpt RPM 校验清单缺少：$file"
    expected="$(awk '{print $4}' <<<"$dump")"
    algorithm="$(rpm -q --qf '%{FILEDIGESTALGO}\n' chatgpt)"
    case "$algorithm" in
      8) actual="$(sha256sum "$file" | awk '{print $1}')" ;;
      1) actual="$(md5sum "$file" | awk '{print $1}')" ;;
      *) fail "不支持的 RPM 文件摘要算法：$algorithm" ;;
    esac
    [ "$actual" = "$expected" ] || fail "ChatGPT RPM 文件完整性校验失败：$file"
  fi
}

discover_chatgpt() {
  local launcher package_status package_arch expected_arch node_major
  launcher="$(command -v chatgpt 2>/dev/null || true)"
  [ -n "$launcher" ] || fail "未找到官方 ChatGPT Linux 桌面端，请先安装 chatgpt 软件包。"
  command -v ss >/dev/null 2>&1 || fail "缺少 iproute2 的 ss 命令，无法验证 CDP 端口。"
  CHATGPT_LAUNCHER="$(canonical_existing_path "$launcher")"
  CHATGPT_ROOT="$(dirname "$CHATGPT_LAUNCHER")"
  CHATGPT_EXE="$CHATGPT_ROOT/ChatGPT"
  NODE="$CHATGPT_ROOT/resources/cua_node/bin/node"
  expected_arch="$(machine_architecture)"

  if command -v dpkg-query >/dev/null 2>&1; then
    package_status="$(dpkg-query -W -f='${Status}' chatgpt 2>/dev/null || true)"
    [ "$package_status" = "install ok installed" ] \
      || fail "chatgpt DEB 软件包未处于完整安装状态。"
    CHATGPT_PACKAGE_KIND="deb"
    CHATGPT_VERSION="$(dpkg-query -W -f='${Version}' chatgpt)"
    package_arch="$(dpkg-query -W -f='${Architecture}' chatgpt)"
    case "$expected_arch:$package_arch" in
      amd64:amd64|arm64:arm64) ;;
      *) fail "ChatGPT 软件包架构 $package_arch 与当前机器 $expected_arch 不匹配。" ;;
    esac
  elif command -v rpm >/dev/null 2>&1 && rpm -q chatgpt >/dev/null 2>&1; then
    CHATGPT_PACKAGE_KIND="rpm"
    CHATGPT_VERSION="$(rpm -q --qf '%{VERSION}-%{RELEASE}' chatgpt)"
    package_arch="$(rpm -q --qf '%{ARCH}' chatgpt)"
    case "$expected_arch:$package_arch" in
      amd64:x86_64|arm64:aarch64) ;;
      *) fail "ChatGPT RPM 架构 $package_arch 与当前机器 $expected_arch 不匹配。" ;;
    esac
  else
    fail "无法通过 dpkg 或 rpm 验证官方 chatgpt 软件包。"
  fi

  [ "$CHATGPT_LAUNCHER" = "/usr/lib/chatgpt/codex-launcher" ] \
    || fail "chatgpt 启动器路径不符合官方 Linux 包结构：$CHATGPT_LAUNCHER"
  assert_packaged_file "$CHATGPT_LAUNCHER"
  assert_packaged_file "$CHATGPT_EXE"
  assert_packaged_file "$NODE"
  [ -x "$CHATGPT_EXE" ] || fail "ChatGPT 主程序不可执行：$CHATGPT_EXE"
  [ -x "$NODE" ] || fail "ChatGPT 随包 Node.js 不可执行：$NODE"

  NODE_VERSION="$($NODE --version)"
  node_major="${NODE_VERSION#v}"
  node_major="${node_major%%.*}"
  case "$node_major" in ''|*[!0-9]*) fail "无法解析随包 Node.js 版本：$NODE_VERSION" ;; esac
  [ "$node_major" -ge 20 ] || fail "随包 Node.js $NODE_VERSION 过旧，需要 20 或更高版本。"
  export CHATGPT_LAUNCHER CHATGPT_ROOT CHATGPT_EXE CHATGPT_VERSION
  export CHATGPT_PACKAGE_KIND NODE NODE_VERSION
}

chatgpt_pids() {
  local proc pid actual
  [ -n "${CHATGPT_EXE:-}" ] || return 0
  for proc in /proc/[0-9]*; do
    [ -r "$proc/exe" ] || continue
    pid="${proc##*/}"
    actual="$(readlink -f "$proc/exe" 2>/dev/null || true)"
    [ "$actual" = "$CHATGPT_EXE" ] && printf '%s\n' "$pid"
  done
}

chatgpt_is_running() {
  [ -n "$(chatgpt_pids)" ]
}

process_start_ticks() {
  local pid="$1"
  [ -r "/proc/$pid/stat" ] || return 1
  sed 's/^.*) //' "/proc/$pid/stat" | awk '{print $20}'
}

pid_is_chatgpt() {
  local pid="$1"
  [ "$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)" = "$CHATGPT_EXE" ]
}

listener_pids() {
  local port="$1"
  command -v ss >/dev/null 2>&1 || fail "缺少 ss，无法验证 CDP 监听进程。"
  ss -H -ltnp "sport = :$port" 2>/dev/null \
    | grep -oE 'pid=[0-9]+' | cut -d= -f2 | sort -u || true
}

port_is_available() {
  [ -z "$(ss -H -ltn "sport = :$1" 2>/dev/null || true)" ]
}

port_belongs_to_chatgpt() {
  local port="$1" pid
  while IFS= read -r pid; do
    [ -n "$pid" ] || continue
    # Electron 子进程会继承监听 FD，ss 因此可能同时报告 Codex/Node 子进程。
    # 只要监听者中存在经过包身份校验的 ChatGPT 主程序即可；浏览器实例
    # 仍由 cdp_browser_id 继续校验，避免连接到同端口上的无关 HTTP 服务。
    pid_is_chatgpt "$pid" && return 0
  done < <(listener_pids "$port")
  return 1
}

cdp_http_ready() {
  local port="$1"
  "$NODE" -e '
    const port = Number(process.argv[1]);
    fetch(`http://127.0.0.1:${port}/json/version`, {
      signal: AbortSignal.timeout(1000),
    }).then((response) => {
      if (!response.ok) process.exit(1);
    }).catch(() => process.exit(1));
  ' "$port" >/dev/null 2>&1
}

cdp_browser_id() {
  local port="$1"
  "$NODE" -e '
    const port = Number(process.argv[1]);
    const response = await fetch(`http://127.0.0.1:${port}/json/version`, {
      signal: AbortSignal.timeout(1500),
    });
    if (!response.ok) process.exit(1);
    const value = await response.json();
    const match = /^ws:\/\/(?:127\.0\.0\.1|localhost):\d+\/devtools\/browser\/([A-Za-z0-9._-]+)$/
      .exec(String(value.webSocketDebuggerUrl || ""));
    if (!match) process.exit(1);
    process.stdout.write(match[1]);
  ' "$port"
}

verified_cdp_endpoint() {
  port_belongs_to_chatgpt "$1" \
    && cdp_http_ready "$1" \
    && cdp_browser_id "$1" >/dev/null 2>&1
}

select_available_port() {
  local candidate="$1" last
  last=$((candidate + 100))
  [ "$last" -le 65535 ] || last=65535
  while [ "$candidate" -le "$last" ]; do
    if port_is_available "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
    candidate=$((candidate + 1))
  done
  fail "端口范围 $1-$last 中没有可用的回环端口。"
}

wait_for_cdp() {
  local port="$1" deadline=$((SECONDS + 45))
  while [ "$SECONDS" -lt "$deadline" ]; do
    verified_cdp_endpoint "$port" && return 0
    sleep 0.35
  done
  return 1
}

stop_chatgpt() {
  local allow_force="${1:-false}" pid deadline
  chatgpt_is_running || return 0
  while IFS= read -r pid; do
    [ -n "$pid" ] && kill -TERM "$pid" 2>/dev/null || true
  done < <(chatgpt_pids)
  deadline=$((SECONDS + 15))
  while chatgpt_is_running && [ "$SECONDS" -lt "$deadline" ]; do sleep 0.25; done
  chatgpt_is_running || return 0
  [ "$allow_force" = "true" ] \
    || fail "ChatGPT 在 15 秒内未退出；强制停止需要明确的重启授权。"
  while IFS= read -r pid; do
    [ -n "$pid" ] && pid_is_chatgpt "$pid" && kill -KILL "$pid" 2>/dev/null || true
  done < <(chatgpt_pids)
  sleep 0.5
  chatgpt_is_running && fail "无法安全停止 ChatGPT。"
}

launch_chatgpt_with_cdp() {
  local port="$1"
  : > "$APP_LOG"
  : > "$APP_ERROR_LOG"
  nohup "$CHATGPT_LAUNCHER" \
    --remote-debugging-address=127.0.0.1 \
    --remote-debugging-port="$port" \
    >>"$APP_LOG" 2>>"$APP_ERROR_LOG" &
  CHATGPT_LAUNCHED_PID="$!"
}

launch_chatgpt_normally() {
  nohup "$CHATGPT_LAUNCHER" >>"$APP_LOG" 2>>"$APP_ERROR_LOG" &
}

state_field() {
  local key="$1"
  [ -f "$STATE_PATH" ] || return 1
  "$NODE" -e '
    const fs = require("node:fs");
    const value = JSON.parse(fs.readFileSync(process.argv[1], "utf8"))[process.argv[2]];
    if (value !== undefined && value !== null) process.stdout.write(String(value));
  ' "$STATE_PATH" "$key"
}

write_state() {
  local port="$1" injector_pid="$2" injector_start="$3" browser_id="$4"
  local session="${5:-applying}"
  "$NODE" -e '
    const fs = require("node:fs");
    const [file, version, port, pid, start, injector, node, nodeVersion,
      exe, appVersion, packageKind, engine, theme, arch, browserId, session] = process.argv.slice(1);
    const state = {
      schemaVersion: 4,
      platform: `linux-${arch}`,
      skinVersion: version,
      injectorProtocol: 3,
      port: Number(port),
      browserId,
      injectorPid: Number(pid),
      injectorStartedAt: start,
      injectorPath: injector,
      nodePath: node,
      nodeVersion,
      chatgptExe: exe,
      chatgptVersion: appVersion,
      packageKind,
      engineRoot: engine,
      themeDir: theme,
      session,
      createdAt: new Date().toISOString(),
    };
    const temporary = `${file}.${process.pid}.tmp`;
    fs.writeFileSync(temporary, `${JSON.stringify(state, null, 2)}\n`, { mode: 0o600 });
    fs.renameSync(temporary, file);
  ' "$STATE_PATH" "$SKIN_VERSION" "$port" "$injector_pid" "$injector_start" \
    "$INJECTOR" "$NODE" "$NODE_VERSION" "$CHATGPT_EXE" "$CHATGPT_VERSION" \
    "$CHATGPT_PACKAGE_KIND" "$ENGINE_ROOT" "$THEME_DIR" "$(uname -m)" "$browser_id" "$session"
}

mark_state_active() {
  "$NODE" -e '
    const fs = require("node:fs");
    const [file, themeDir] = process.argv.slice(1);
    const state = JSON.parse(fs.readFileSync(file, "utf8"));
    const theme = JSON.parse(fs.readFileSync(`${themeDir}/theme.json`, "utf8"));
    state.session = "active";
    state.appliedThemeId = String(theme.id || "");
    state.appliedThemeName = String(theme.name || theme.id || "");
    state.verifiedAt = new Date().toISOString();
    const temporary = `${file}.${process.pid}.tmp`;
    fs.writeFileSync(temporary, `${JSON.stringify(state, null, 2)}\n`, { mode: 0o600 });
    fs.renameSync(temporary, file);
  ' "$STATE_PATH" "$THEME_DIR"
}

recorded_injector_matches() {
  local pid="$1" expected_start="$2" expected_node="$3" expected_injector="$4" expected_port="$5"
  local actual_start actual_node command_line
  [ -r "/proc/$pid/cmdline" ] || return 1
  actual_node="$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)"
  [ "$actual_node" = "$(readlink -f "$expected_node")" ] || return 1
  actual_start="$(process_start_ticks "$pid")"
  [ -n "$actual_start" ] && [ "$actual_start" = "$expected_start" ] || return 1
  command_line="$(tr '\0' '\n' < "/proc/$pid/cmdline")"
  grep -Fxq "$expected_injector" <<<"$command_line" || return 1
  grep -Fxq -- '--watch' <<<"$command_line" || return 1
  awk -v port="$expected_port" 'previous == "--port" && $0 == port { found=1 } { previous=$0 } END { exit !found }' \
    <<<"$command_line"
}

stop_recorded_injector() {
  [ -f "$STATE_PATH" ] || return 0
  local pid start node injector port deadline
  pid="$(state_field injectorPid 2>/dev/null || true)"
  start="$(state_field injectorStartedAt 2>/dev/null || true)"
  node="$(state_field nodePath 2>/dev/null || true)"
  injector="$(state_field injectorPath 2>/dev/null || true)"
  port="$(state_field port 2>/dev/null || true)"
  case "$pid:$port" in *[!0-9:]*|:*) fail "记录的注入器身份无效，状态已保留。" ;; esac
  [ -d "/proc/$pid" ] || return 0
  recorded_injector_matches "$pid" "$start" "$node" "$injector" "$port" \
    || fail "PID $pid 与记录的注入器身份不符，拒绝发送信号。"
  kill -TERM "$pid" 2>/dev/null || true
  deadline=$((SECONDS + 6))
  while recorded_injector_matches "$pid" "$start" "$node" "$injector" "$port" \
    && [ "$SECONDS" -lt "$deadline" ]; do sleep 0.2; done
  if recorded_injector_matches "$pid" "$start" "$node" "$injector" "$port"; then
    kill -KILL "$pid" 2>/dev/null || true
  fi
  sleep 0.2
  recorded_injector_matches "$pid" "$start" "$node" "$injector" "$port" \
    && fail "无法停止已记录的注入器 PID $pid。"
  return 0
}

launch_injector_daemon() {
  local port="$1" pid
  : > "$INJECTOR_LOG"
  : > "$INJECTOR_ERROR_LOG"
  nohup "$NODE" "$INJECTOR" --watch --port "$port" --theme-dir "$THEME_DIR" \
    >>"$INJECTOR_LOG" 2>>"$INJECTOR_ERROR_LOG" &
  pid="$!"
  sleep 0.2
  [ -d "/proc/$pid" ] || fail "注入器未能启动，请查看 $INJECTOR_ERROR_LOG"
  printf '%s\n' "$pid"
}
