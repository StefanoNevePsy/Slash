#!/bin/bash
# Builds Slash.app (universal: Apple silicon + Intel) and zips it.
# Usage: scripts/build-app.sh [version]     e.g. scripts/build-app.sh 1.0.3
# Runs on macOS with Xcode installed (also used by GitHub Actions).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-0.0.1}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
OUT=build
APP="$OUT/Slash.app"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Slash"

rm -rf "$OUT" && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Slash"

# Icon: 1024px PNG -> .icns
ICONSET="$OUT/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# macOS 26+ adaptive icon (light / dark / tinted / clear) from the Icon Composer file.
# Needs Xcode 26+; on older Xcode we silently keep only the classic .icns above.
if xcrun actool --version >/dev/null 2>&1; then
  if xcrun actool Resources/AppIcon.icon \
      --compile "$APP/Contents/Resources" \
      --platform macosx --minimum-deployment-target 14.0 \
      --app-icon AppIcon \
      --output-partial-info-plist "$OUT/icon-partial.plist" \
      --output-format human-readable-text; then
    # actool may write its own AppIcon.icns; regenerate ours if it was removed
    [ -f "$APP/Contents/Resources/AppIcon.icns" ] || iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
    echo "Adaptive icon compiled into Assets.car"
  else
    echo "warning: actool could not compile AppIcon.icon; using classic icon only"
  fi
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Slash</string>
  <key>CFBundleDisplayName</key><string>Slash</string>
  <key>CFBundleIdentifier</key><string>com.stefanoneve.slash</string>
  <key>CFBundleExecutable</key><string>Slash</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Slash asks Finder to show the Get Info window for the selected items.</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Folder</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key><array><string>public.folder</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST

# Ad-hoc signature (no Apple Developer account needed)
codesign --force --deep --sign - "$APP"

ditto -c -k --keepParent "$APP" "$OUT/Slash.zip"
echo "Built $APP ($VERSION) and $OUT/Slash.zip"
