#!/usr/bin/env bash
# Builds build/Overhang.app (universal, ad-hoc signed).
#   CONFIG=debug ./scripts/build-app.sh      # debug build
#   ARCHS=arm64 ./scripts/build-app.sh       # single architecture (faster)
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
ARCHS="${ARCHS:-arm64 x86_64}"
arch_flags=()
for arch in $ARCHS; do arch_flags+=(--arch "$arch"); done

swift build -c "$CONFIG" "${arch_flags[@]}"
BIN_DIR="$(swift build -c "$CONFIG" "${arch_flags[@]}" --show-bin-path)"

APP="build/Overhang.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Overhang" "$APP/Contents/MacOS/Overhang"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" || true
fi

# Ad-hoc signature: enough to run locally. macOS ties privacy permissions to the signature,
# so after a rebuild you may need to re-grant Accessibility/Automation.
codesign --force --sign - "$APP"

echo "Built $APP"
lipo -info "$APP/Contents/MacOS/Overhang" || true
