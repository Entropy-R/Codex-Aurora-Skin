#!/bin/bash

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
REPOSITORY_ROOT="$(cd "$ROOT/.." && pwd -P)"
NODE="${NODE:-$(command -v node)}"
PACKAGE_ROOT="$ROOT/menubar-app"
VERSION="$(/usr/bin/tr -d '[:space:]' < "$ROOT/VERSION")"
OUTPUT_APP="$ROOT/release/Codex Aurora Skin.app"
SKIP_TESTS="false"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --skip-tests) SKIP_TESTS="true"; shift ;;
    --output) OUTPUT_APP="${2:-}"; shift 2 ;;
    *) printf 'Unknown app build argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

printf '%s' "$VERSION" | /usr/bin/grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' \
  || { printf 'Invalid VERSION: %s\n' "$VERSION" >&2; exit 1; }
[ -n "$OUTPUT_APP" ] || { printf 'Output app path cannot be empty.\n' >&2; exit 1; }
"$NODE" "$REPOSITORY_ROOT/tools/verify-library.mjs" >/dev/null
case "$(/usr/bin/basename "$OUTPUT_APP")" in
  *.app) ;;
  *) printf 'Output path must end in an .app bundle name: %s\n' "$OUTPUT_APP" >&2; exit 1 ;;
esac
[ ! -L "$OUTPUT_APP" ] || { printf 'Refusing to replace a symbolic-link output: %s\n' "$OUTPUT_APP" >&2; exit 1; }

if [ "$SKIP_TESTS" != "true" ]; then
  /usr/bin/swift test --package-path "$PACKAGE_ROOT"
fi

TMP="$(/usr/bin/mktemp -d /tmp/codex-aurora-skin-app.XXXXXX)"
# Preserve the real exit status; a plain cleanup trap masks fatal errors as
# success on the /bin/bash 3.2 this shebang resolves to.
trap 'status=$?; /bin/rm -rf "$TMP"; exit "$status"' EXIT
ARCH_TEXT="${AURORASKIN_ARCHS:-arm64 x86_64}"
read -r -a ARCHS <<< "$ARCH_TEXT"
[ "${#ARCHS[@]}" -gt 0 ] || { printf 'No build architectures selected.\n' >&2; exit 1; }

BINARIES=()
for arch in "${ARCHS[@]}"; do
  case "$arch" in arm64|x86_64) ;; *) printf 'Unsupported architecture: %s\n' "$arch" >&2; exit 1 ;; esac
  triple="${arch}-apple-macosx13.0"
  if [ -n "${AURORASKIN_SDK:-}" ]; then
    direct="$TMP/direct-$arch"
    /bin/mkdir -p "$direct"
    /usr/bin/swiftc -O -sdk "$AURORASKIN_SDK" -target "$triple" \
      -parse-as-library -emit-module -emit-library -static -module-name AuroraSkinCore \
      "$PACKAGE_ROOT"/Sources/AuroraSkinCore/*.swift \
      -emit-module-path "$direct/AuroraSkinCore.swiftmodule" \
      -o "$direct/libAuroraSkinCore.a"
    /usr/bin/swiftc -O -sdk "$AURORASKIN_SDK" -target "$triple" \
      -I "$direct" -L "$direct" -lAuroraSkinCore \
      "$PACKAGE_ROOT"/Sources/CodexAuroraSkinMenuBar/*.swift \
      -o "$direct/CodexAuroraSkinMenuBar"
    binary="$direct/CodexAuroraSkinMenuBar"
  else
    scratch="$PACKAGE_ROOT/.build-$arch"
    /usr/bin/swift build --package-path "$PACKAGE_ROOT" --scratch-path "$scratch" \
      --configuration release --triple "$triple" --product CodexAuroraSkinMenuBar
    binary_dir="$(/usr/bin/swift build --package-path "$PACKAGE_ROOT" \
      --scratch-path "$scratch" --configuration release --triple "$triple" \
      --show-bin-path)"
    binary="$binary_dir/CodexAuroraSkinMenuBar"
  fi
  [ -x "$binary" ] || { printf 'Built executable missing: %s\n' "$binary" >&2; exit 1; }
  /bin/cp "$binary" "$TMP/CodexAuroraSkinMenuBar-$arch"
  BINARIES+=("$TMP/CodexAuroraSkinMenuBar-$arch")
done

APP="$TMP/Codex Aurora Skin.app"
CONTENTS="$APP/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
ENGINE="$RESOURCES/engine"
/bin/mkdir -p "$MACOS_DIR" "$ENGINE" "$(dirname "$OUTPUT_APP")"

if [ "${#BINARIES[@]}" -eq 1 ]; then
  /bin/cp "${BINARIES[0]}" "$MACOS_DIR/CodexAuroraSkinMenuBar"
else
  /usr/bin/lipo -create "${BINARIES[@]}" -output "$MACOS_DIR/CodexAuroraSkinMenuBar"
fi
/bin/chmod 755 "$MACOS_DIR/CodexAuroraSkinMenuBar"

/usr/bin/sed "s/__VERSION__/$VERSION/g" \
  "$PACKAGE_ROOT/Resources/Info.plist.template" > "$CONTENTS/Info.plist"
/usr/bin/plutil -lint "$CONTENTS/Info.plist" >/dev/null

RUNTIME_SCRIPTS=(
  common-macos.sh
  image-metadata.mjs
  injector.mjs
  launch-manager-macos.sh
  migrate-config-macos.sh
  restore-aurora-skin-macos.sh
  start-aurora-skin-macos.sh
  theme-config.mjs
)
/bin/mkdir -p "$ENGINE/scripts"
for name in "${RUNTIME_SCRIPTS[@]}"; do
  [ -f "$ROOT/scripts/$name" ] || { printf 'Runtime script missing: %s\n' "$name" >&2; exit 1; }
  /bin/cp "$ROOT/scripts/$name" "$ENGINE/scripts/$name"
done
[ -d "$ROOT/assets" ] || { printf 'Engine directory missing: assets\n' >&2; exit 1; }
/usr/bin/rsync -a "$ROOT/assets/" "$ENGINE/assets/"
PUBLIC_PRESET="preset-red-white-abstract"
PUBLIC_PRESET_SHA256="31bde93bb02d6723e0b6aa0ead675577604120acb0a6799163dd37f5cdd0a08e"
PUBLIC_PRESET_THEME_SHA256="1d2fbbd9323739e7720f9f17c96b7f617e3b596c21f0d976e9ceaed2fb8a109b"
[ -d "$REPOSITORY_ROOT/library/$PUBLIC_PRESET" ] \
  || { printf 'Public release preset missing: %s\n' "$PUBLIC_PRESET" >&2; exit 1; }
actual_public_preset_sha256="$(LC_ALL=C /usr/bin/shasum -a 256 \
  "$REPOSITORY_ROOT/library/$PUBLIC_PRESET/background.png" | /usr/bin/awk '{print $1}')"
[ "$actual_public_preset_sha256" = "$PUBLIC_PRESET_SHA256" ] \
  || { printf 'Reviewed public preset hash changed: %s\n' "$actual_public_preset_sha256" >&2; exit 1; }
actual_public_preset_theme_sha256="$(LC_ALL=C /usr/bin/shasum -a 256 \
  "$REPOSITORY_ROOT/library/$PUBLIC_PRESET/theme.json" | /usr/bin/awk '{print $1}')"
[ "$actual_public_preset_theme_sha256" = "$PUBLIC_PRESET_THEME_SHA256" ] \
  || { printf 'Reviewed public preset metadata hash changed: %s\n' "$actual_public_preset_theme_sha256" >&2; exit 1; }
/bin/mkdir -p "$ENGINE/manager/web"
for relative in \
  image-metadata.mjs \
  server.mjs \
  theme-store.mjs \
  web/app.js \
  web/index.html \
  web/styles.css; do
  /bin/cp "$REPOSITORY_ROOT/manager/$relative" "$ENGINE/manager/$relative"
done
/usr/bin/rsync -a "$REPOSITORY_ROOT/library/" "$ENGINE/library/"
/bin/cp "$ROOT/VERSION" "$ENGINE/VERSION"
/bin/cp "$ROOT/LICENSE" "$RESOURCES/LICENSE.txt"
/bin/cp "$ROOT/NOTICE.md" "$RESOURCES/NOTICE.md"
/bin/chmod 755 "$ENGINE/scripts/"*.sh
/bin/chmod 644 "$ENGINE/scripts/"*.mjs
/bin/chmod 644 "$ENGINE/VERSION"
"$ROOT/scripts/generate-app-icon.sh" "$RESOURCES/AuroraSkin.icns"
[ -s "$RESOURCES/AuroraSkin.icns" ] \
  || { printf 'App icon is missing after generation: %s\n' "$RESOURCES/AuroraSkin.icns" >&2; exit 1; }
/usr/bin/codesign --force --deep --sign - --timestamp=none "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"

/bin/rm -rf "$OUTPUT_APP"
/usr/bin/ditto "$APP" "$OUTPUT_APP"
/usr/bin/codesign --verify --deep --strict "$OUTPUT_APP"
/usr/bin/printf 'Created %s\n' "$OUTPUT_APP"
/usr/bin/file "$OUTPUT_APP/Contents/MacOS/CodexAuroraSkinMenuBar"
ACTUAL_ARCHS="$(/usr/bin/lipo -archs "$OUTPUT_APP/Contents/MacOS/CodexAuroraSkinMenuBar")"
for arch in "${ARCHS[@]}"; do
  case " $ACTUAL_ARCHS " in
    *" $arch "*) ;;
    *) printf 'Built app is missing architecture %s: %s\n' "$arch" "$ACTUAL_ARCHS" >&2; exit 1 ;;
  esac
done
