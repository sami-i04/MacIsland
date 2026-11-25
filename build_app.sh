#!/bin/zsh
set -e
cd "$(dirname "$0")"

APP_NAME="MacIsland"
OUT_DIR="final app"
APP="$OUT_DIR/$APP_NAME.app"
BUILD="build_tmp"

rm -rf "$BUILD"
mkdir -p "$BUILD"

echo "→ Kompiliere…"
SOURCES=(main.swift assets/**/*.swift(N))
swiftc -O -swift-version 5 "${SOURCES[@]}" -o "$BUILD/$APP_NAME" \
  -framework AppKit -framework SwiftUI -framework UniformTypeIdentifiers \
  -framework CoreAudio -framework AudioToolbox -framework Accelerate \
  -framework EventKit -framework IOKit

if pgrep -x "$APP_NAME" >/dev/null; then
  echo "→ Beende laufende $APP_NAME-Instanz…"
  pkill -x "$APP_NAME" || true
  for i in {1..20}; do pgrep -x "$APP_NAME" >/dev/null || break; sleep 0.1; done
  pkill -9 -x "$APP_NAME" 2>/dev/null || true
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
mv "$BUILD/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

echo "→ Kompiliere Media-Helfer…"
clang -O2 -dynamiclib -fobjc-arc -framework Foundation MediaHelper.m -o "$APP/Contents/Resources/macisland_media.dylib"
codesign --force --sign - "$APP/Contents/Resources/macisland_media.dylib"

if [ -f notch_config.json ]; then
  cp notch_config.json "$APP/Contents/Resources/notch_config.json"
else
  echo "⚠︎ notch_config.json fehlt – App nutzt eingebaute Standardwerte"
fi

echo "→ Erzeuge Icon…"
if [ -f icon.png ]; then
  cp icon.png "$BUILD/icon_1024.png"
else
  swift make_icon.swift "$BUILD/icon_1024.png"
fi
ICONSET="$BUILD/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$BUILD/icon_1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$BUILD/icon_1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cp -R assets/Sprachen/*.lproj "$APP/Contents/Resources/"

echo "→ Schreibe Info.plist…"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>               <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>        <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>         <string>local.macisland.app</string>
  <key>CFBundleExecutable</key>         <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>           <string>AppIcon</string>
  <key>CFBundleDevelopmentRegion</key>  <string>en</string>
  <key>CFBundleLocalizations</key>      <array><string>de</string><string>en</string></array>
  <key>CFBundlePackageType</key>        <string>APPL</string>
  <key>CFBundleShortVersionString</key> <string>1.1</string>
  <key>CFBundleVersion</key>            <string>$(date +%Y%m%d%H%M)</string>
  <key>LSMinimumSystemVersion</key>     <string>14.2</string>
  <key>LSUIElement</key>                <true/>
  <key>LSAppNapIsDisabled</key>         <true/>
  <key>NSAppSleepDisabled</key>         <true/>
  <key>NSHighResolutionCapable</key>    <true/>
  <key>NSCalendarsFullAccessUsageDescription</key> <string>MacIsland zeigt deinen nächsten Termin neben der Notch an.</string>
  <key>NSAppleEventsUsageDescription</key> <string>MacIsland öffnet beim Klick auf den Download-Kreis die Download-Übersicht von Safari.</string>
  <key>NSAudioCaptureUsageDescription</key> <string>MacIsland hört die Audioausgabe mit, damit der Visualizer zur laufenden Musik passt. Es wird nichts aufgezeichnet oder gespeichert.</string>
</dict>
</plist>
EOF

echo "→ Signiere (ad-hoc)…"
codesign --force --deep --sign - -r='designated => identifier "local.macisland.app"' "$APP"

rm -rf "$BUILD"

echo "→ Aktualisiere Icon-Cache…"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
touch "$APP" "$APP/Contents" "$APP/Contents/Info.plist"
"$LSREGISTER" -f "$APP" >/dev/null 2>&1 || true
osascript -e "tell application \"Finder\" to update (POSIX file \"$PWD/$APP\" as alias)" >/dev/null 2>&1 || true
osascript -e "tell application \"Finder\" to update (POSIX file \"$PWD/$OUT_DIR\" as alias)" >/dev/null 2>&1 || true

echo "✓ Fertig: $APP"

echo "→ Starte $APP_NAME…"
open "$APP"
