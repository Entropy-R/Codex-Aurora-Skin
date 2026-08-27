#!/bin/bash

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
LINUX_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
REPOSITORY_ROOT="$(cd "$LINUX_ROOT/.." && pwd -P)"
VERSION="$(tr -d '\r\n' < "$LINUX_ROOT/VERSION")"
OUTPUT_ROOT="${1:-$REPOSITORY_ROOT/release}"
BUILD_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-aurora-linux-build.XXXXXX")"
RUNTIME_ROOT="$BUILD_ROOT/runtime"

mkdir -p "$OUTPUT_ROOT"
"$SCRIPT_DIR/assemble-runtime.sh" "$RUNTIME_ROOT" >/dev/null

TAR_PATH="$OUTPUT_ROOT/CodexAuroraSkin-v$VERSION-linux.tar.gz"
[ ! -e "$TAR_PATH" ] || {
  printf 'Refusing to overwrite existing artifact: %s\n' "$TAR_PATH" >&2
  exit 1
}
# 公开 TAR 不保留构建机用户名；路径和权限仍保持运行时原样。
tar --owner=0 --group=0 --numeric-owner -C "$BUILD_ROOT" -czf "$TAR_PATH" runtime
printf 'built=%s\n' "$TAR_PATH"

if command -v dpkg-deb >/dev/null 2>&1; then
  DEB_ROOT="$BUILD_ROOT/deb"
  mkdir -p "$DEB_ROOT/DEBIAN" "$DEB_ROOT/opt" "$DEB_ROOT/usr/share/applications"
  cp "$SCRIPT_DIR/debian/control" "$DEB_ROOT/DEBIAN/control"
  cp -a "$RUNTIME_ROOT" "$DEB_ROOT/opt/codex-aurora-skin"
  cp "$SCRIPT_DIR/debian/"*.desktop "$DEB_ROOT/usr/share/applications/"
  chmod 755 "$DEB_ROOT" "$DEB_ROOT/DEBIAN" "$DEB_ROOT/opt" \
    "$DEB_ROOT/usr" "$DEB_ROOT/usr/share" "$DEB_ROOT/usr/share/applications"
  chmod 644 "$DEB_ROOT/DEBIAN/control" "$DEB_ROOT/usr/share/applications/"*.desktop
  DEB_PATH="$OUTPUT_ROOT/codex-aurora-skin_${VERSION}_all.deb"
  [ ! -e "$DEB_PATH" ] || {
    printf 'Refusing to overwrite existing artifact: %s\n' "$DEB_PATH" >&2
    exit 1
  }
  dpkg-deb --root-owner-group --build "$DEB_ROOT" "$DEB_PATH" >/dev/null
  printf 'built=%s\n' "$DEB_PATH"
fi

if command -v rpmbuild >/dev/null 2>&1; then
  RPM_TOP="$BUILD_ROOT/rpmbuild"
  mkdir -p "$RPM_TOP/BUILD" "$RPM_TOP/BUILDROOT" "$RPM_TOP/RPMS" \
    "$RPM_TOP/SOURCES" "$RPM_TOP/SPECS" "$RPM_TOP/SRPMS"
  cp -a "$RUNTIME_ROOT" "$RPM_TOP/SOURCES/runtime"
  cp "$SCRIPT_DIR/debian/"*.desktop "$RPM_TOP/SOURCES/"
  cp "$SCRIPT_DIR/rpm/codex-aurora-skin.spec" "$RPM_TOP/SPECS/"
  rpmbuild -bb --define "_topdir $RPM_TOP" \
    "$RPM_TOP/SPECS/codex-aurora-skin.spec" >/dev/null
  while IFS= read -r rpm_path; do
    target="$OUTPUT_ROOT/$(basename "$rpm_path")"
    [ ! -e "$target" ] || {
      printf 'Refusing to overwrite existing artifact: %s\n' "$target" >&2
      exit 1
    }
    cp "$rpm_path" "$target"
    printf 'built=%s\n' "$target"
  done < <(find "$RPM_TOP/RPMS" -type f -name '*.rpm' -print)
else
  printf 'skipped=rpm (rpmbuild is unavailable)\n'
fi

printf 'build-workspace=%s\n' "$BUILD_ROOT"
