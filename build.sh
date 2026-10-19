#!/bin/zsh
# Builds build/Mochi.app (release build configuration).
#   --install   copy it to /Applications and launch it
#   --release   build for both Apple silicon and Intel, notarize it, and zip it up as build/Mochi.zip
#
# Signing: uses the "Developer ID Application" certificate in your keychain, or $MOCHI_SIGN_IDENTITY.
# Without one (or with MOCHI_SIGN_IDENTITY=-) the app is ad-hoc signed, which is fine for running it yourself.
# Notarizing (--release with a Developer ID) needs notarytool credentials, saved once:
#   xcrun notarytool store-credentials mochi --apple-id <your Apple ID> --team-id <your team ID>
# Set $MOCHI_NOTARY_PROFILE to use a profile name other than "mochi".
set -euo pipefail
cd "$(dirname "$0")"

RELEASE=0
[[ " $* " == *" --release "* ]] && RELEASE=1
ARCHS=()
(( RELEASE )) && ARCHS=(--arch arm64 --arch x86_64)
IDENTITY=${MOCHI_SIGN_IDENTITY-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/"Developer ID Application: /{print $2; exit}' || true)}
[[ -z $IDENTITY ]] && IDENTITY=-

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
  <key>CFBundleShortVersionString</key><string>1.0.1</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>A cat for your desktop.</string>
</dict>
</plist>
PLIST

if [[ $IDENTITY == - ]]; then
  codesign --force --sign - "$APP"
  echo "Built $APP (ad-hoc signed)"
else
  # Hardened runtime and a secure timestamp are what notarization asks for. The timestamp needs the
  # network, so everyday builds skip it.
  TIMESTAMP=--timestamp=none
  (( RELEASE )) && TIMESTAMP=--timestamp
  codesign --force --options runtime $TIMESTAMP --sign "$IDENTITY" "$APP"
  echo "Built $APP (signed by $IDENTITY)"
fi

if (( RELEASE )); then
  rm -f build/Mochi.zip
  if [[ $IDENTITY == - ]]; then
    echo "Note: no Developer ID certificate, so build/Mochi.zip won't be notarized." >&2
  else
    PROFILE=${MOCHI_NOTARY_PROFILE:-mochi}
    echo "Sending it to Apple to notarize (usually a minute or two)…"
    ditto -c -k --keepParent "$APP" build/notarize.zip
    if ! RESULT=$(xcrun notarytool submit build/notarize.zip --keychain-profile "$PROFILE" --wait --output-format json); then
      echo "Couldn't reach the notary service. Saved credentials as \"$PROFILE\"? See the top of build.sh." >&2
      exit 1
    fi
    rm build/notarize.zip
    if [[ $(plutil -extract status raw -o - - <<< "$RESULT") != Accepted ]]; then
      echo "$RESULT" >&2
      xcrun notarytool log "$(plutil -extract id raw -o - - <<< "$RESULT")" --keychain-profile "$PROFILE" >&2
      exit 1
    fi
    xcrun stapler staple -q "$APP"
    spctl --assess --type execute "$APP"
    echo "Notarized"
  fi
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
