#!/bin/bash
# Builds build/TabPulse.app. Usage: scripts/build.sh [--universal]
# Calls swiftc directly (not SwiftPM) so it works with just the Xcode Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(cat VERSION)
APP=build/TabPulse.app
OBJ=.build/tabpulse
archs=("$(uname -m)")
if [ "${1:-}" = "--universal" ]; then archs=(arm64 x86_64); fi
flags=(-O -swift-version 5)

# Some Command Line Tools releases ship a stale duplicate SwiftBridging module map
# ("redefinition of module 'SwiftBridging'"). A VFS overlay hides it without sudo.
clt=/Library/Developer/CommandLineTools/usr/include/swift
if [ -f "$clt/bridging.modulemap" ] && grep -qs "SwiftBridging" "$clt/module.modulemap"; then
  mkdir -p "$OBJ" && : >"$OBJ/empty.modulemap"
  printf '{"version":0,"case-sensitive":"false","roots":[{"type":"file","name":"%s","external-contents":"%s"}]}\n' \
    "$clt/module.modulemap" "$PWD/$OBJ/empty.modulemap" >"$OBJ/overlay.yaml"
  flags+=(-vfsoverlay "$OBJ/overlay.yaml" -Xcc -ivfsoverlay -Xcc "$OBJ/overlay.yaml")
fi

mkdir -p "$OBJ"
slices=()
for arch in "${archs[@]}"; do
  swiftc "${flags[@]}" -target "$arch-apple-macos14.0" -o "$OBJ/TabPulse-$arch" Sources/TabPulse/*.swift
  slices+=("$OBJ/TabPulse-$arch")
done

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "${slices[@]}" -output "$APP/Contents/MacOS/TabPulse"
cp plugin/hooks/tabpulse-hook.sh "$APP/Contents/Resources/"
cat >"$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.tabpulse.TabPulse</string>
  <key>CFBundleName</key><string>TabPulse</string>
  <key>CFBundleExecutable</key><string>TabPulse</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>TabPulse puts a live spinner in the titles of Ghostty tabs running Claude Code, and jumps to a session's tab when you click it.</string>
</dict></plist>
PLIST
if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/"
  plutil -insert CFBundleIconFile -string AppIcon "$APP/Contents/Info.plist"
fi
xattr -cr "$APP"   # codesign rejects files carrying Finder info or resource forks
# ad-hoc: Apple Silicon won't run unsigned code. Its output is noise unless signing fails.
if ! out=$(codesign --force --sign - "$APP" 2>&1); then
  printf 'codesign failed:\n%s\n' "$out" >&2
  exit 1
fi
echo "Built $APP $VERSION (${archs[*]})"
