#!/bin/bash

set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd -P)/common-macos.sh"

PORT=9341
CREATE_LAUNCHERS="true"
LAUNCH_AFTER_INSTALL="true"
IN_PLACE="false"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --port) PORT="${2:-}"; shift 2 ;;
    --no-launchers) CREATE_LAUNCHERS="false"; shift ;;
    --no-launch) LAUNCH_AFTER_INSTALL="false"; shift ;;
    --in-place) IN_PLACE="true"; shift ;;
    *) fail "Unknown installer argument: $1" ;;
  esac
done
case "$PORT" in ''|*[!0-9]*) fail "Invalid port: $PORT" ;; esac
[ "$PORT" -ge 1024 ] && [ "$PORT" -le 65535 ] || fail "Port must be between 1024 and 65535."

deploy_project() {
  local temporary="$INSTALL_ROOT.installing.$$"
  local previous="$INSTALL_ROOT.previous.$$"
  /bin/rm -rf "$temporary"
  /bin/mkdir -p "$temporary"
  /usr/bin/rsync -a \
    --exclude '.git/' \
    --exclude '.DS_Store' \
    --exclude 'release/' \
    --exclude 'runtime/' \
    "$PROJECT_ROOT/" "$temporary/"
  /bin/chmod 700 "$temporary"/*.command "$temporary"/scripts/*.sh 2>/dev/null || true
  /bin/rm -rf "$previous"
  if [ -e "$INSTALL_ROOT" ]; then /bin/mv "$INSTALL_ROOT" "$previous"; fi
  if ! /bin/mv "$temporary" "$INSTALL_ROOT"; then
    [ -e "$previous" ] && /bin/mv "$previous" "$INSTALL_ROOT"
    fail "Could not install the project at $INSTALL_ROOT"
  fi
  DEPLOY_PREVIOUS="$previous"
}

commit_deployed_project() {
  [ -n "${DEPLOY_PREVIOUS:-}" ] || return 0
  /bin/rm -rf "$DEPLOY_PREVIOUS" || true
  DEPLOY_PREVIOUS=""
}

rollback_deployed_project() {
  local status="$1"
  local broken="$INSTALL_ROOT.broken.$$"
  # Swap with renames only: `rm -rf` on the live root is not atomic, and an
  # interrupted deletion leaves a mixed-version engine behind.  Deleting the
  # detached broken tree afterwards is safe to interrupt.
  if [ -e "$INSTALL_ROOT" ]; then
    /bin/mv "$INSTALL_ROOT" "$broken" \
      || fail "Installation failed and the broken engine could not be moved aside."
  fi
  if [ -n "${DEPLOY_PREVIOUS:-}" ] && [ -e "$DEPLOY_PREVIOUS" ]; then
    /bin/mv "$DEPLOY_PREVIOUS" "$INSTALL_ROOT" \
      || fail "Installation failed and the previous engine could not be restored."
  fi
  /bin/rm -rf "$broken" 2>/dev/null || true
  DEPLOY_PREVIOUS=""
  return "$status"
}

DEPLOY_PREVIOUS=""

if [ "$IN_PLACE" = "false" ] && [ "$PROJECT_ROOT" != "$INSTALL_ROOT" ]; then
  # Run the cheap precondition before any engine bytes move: aborting after
  # the copy forces a rollback of a perfectly good previous engine, and an
  # interrupted rollback is how a mixed-version tree ships.
  codex_is_running && fail "Close Codex before installation so config.toml cannot be rewritten while the app is saving it."
  /bin/mkdir -p "$(dirname "$INSTALL_ROOT")"
  deploy_project
  install_args=(--in-place --port "$PORT")
  [ "$CREATE_LAUNCHERS" = "true" ] || install_args+=(--no-launchers)
  [ "$LAUNCH_AFTER_INSTALL" = "true" ] || install_args+=(--no-launch)
  if "$INSTALL_ROOT/scripts/install-aurora-skin-macos.sh" "${install_args[@]}"; then
    commit_deployed_project
    exit 0
  else
    status=$?
    rollback_deployed_project "$status"
    exit "$status"
  fi
fi

discover_codex_app
require_macos_runtime
codex_is_running && fail "Close Codex before installation so the runtime can be upgraded safely."
migrate_legacy_user_data
ensure_state_root

shell_quote() {
  "$NODE" -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$1"
}

write_launcher() {
  local target="$1"
  local command="$2"
  if [ -e "$target" ] && ! /usr/bin/grep -q '^# CodexAuroraSkin launcher$' "$target" 2>/dev/null; then
    fail "Refusing to overwrite an unrelated Desktop file: $target"
  fi
  /usr/bin/printf '%s\n' \
    '#!/bin/bash' \
    '# CodexAuroraSkin launcher' \
    'set -e' \
    "$command" > "$target"
  /bin/chmod 700 "$target"
}

if [ "$CREATE_LAUNCHERS" = "true" ]; then
  /bin/mkdir -p "$HOME/Desktop"
  start_script="$(shell_quote "$SCRIPT_DIR/launch-manager-macos.sh")"
  restore_script="$(shell_quote "$SCRIPT_DIR/restore-aurora-skin-macos.sh")"
  write_launcher "$HOME/Desktop/Codex Aurora Skin.command" "exec $start_script"
  write_launcher "$HOME/Desktop/Codex Aurora Skin - Restore.command" "exec $restore_script --restart-codex"
fi

printf 'Codex Aurora Skin %s installed at %s for Codex %s using its signed Node.js %s.\n' \
  "$SKIN_VERSION" "$PROJECT_ROOT" "$CODEX_VERSION" "$NODE_VERSION"
printf 'Use the Desktop launchers to open the theme manager or restore the official appearance.\n'

if [ "$LAUNCH_AFTER_INSTALL" = "true" ]; then
  "$SCRIPT_DIR/launch-manager-macos.sh"
fi
