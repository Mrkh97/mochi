#!/bin/zsh
# Builds build/Mochi.app (release, ad-hoc signed).
#   --install   copy it to /Applications and launch it
#   --release   build for both Apple silicon and Intel, and zip it up as build/Mochi.zip
set -euo pipefail
cd "$(dirname "$0")"

ARCHS=()
[[ " $* " == *" --release "* ]] && ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/Mochi"
APP=build/Mochi.app
rm -rf "$APP" build/Mochi.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/Mochi.iconset
cp "$BIN" "$APP/Contents/MacOS/Mochi"

"$BIN" --icon build/icon-1024.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon-1024.png --out build/Mochi.iconset/icon_${s}x${s}.png >/dev/null
  sips -z $((s * 2)) $((s * 2)) build/icon-1024.png --out build/Mochi.iconset/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns build/Mochi.iconset -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Mochi</string>
  <key>CFBundleDisplayName</key><string>Mochi</string>
  <key>CFBundleIdentifier</key><string>dev.mochi.desktopcat</string>
  <key>CFBundleExecutable</key><string>Mochi</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>A cat for your desktop.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"

if [[ " $* " == *" --release "* ]]; then
  rm -f build/Mochi.zip
  ditto -c -k --norsrc --noextattr --keepParent "$APP" build/Mochi.zip
  echo "Zipped build/Mochi.zip"
fi

if [[ " $* " == *" --install "* ]]; then
  pkill -x Mochi 2>/dev/null || true
  sleep 1
  rm -rf /Applications/Mochi.app
  cp -R "$APP" /Applications/Mochi.app
  open /Applications/Mochi.app || { sleep 2; open /Applications/Mochi.app; }
  echo "Installed to /Applications/Mochi.app"
fi
