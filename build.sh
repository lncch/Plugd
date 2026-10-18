#!/bin/bash
# Builds Plugd.app with the command line tools (no Xcode).
set -euo pipefail
cd "$(dirname "$0")"

APP=Plugd.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/bin" "$APP/Contents/Resources/lib"

swiftc -O -parse-as-library -target arm64-apple-macos14.0 Sources/*.swift -o "$APP/Contents/MacOS/Plugd"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Plugd</string>
  <key>CFBundleDisplayName</key><string>Plugd</string>
  <key>CFBundleIdentifier</key><string>dev.almoayyad.plugd</string>
  <key>CFBundleExecutable</key><string>Plugd</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.3.1</string>
  <key>CFBundleVersion</key><string>6</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>Plugd</string>
</dict>
</plist>
EOF

# innoextract (zlib license) plus its Homebrew libraries, rewritten to load from the bundle.
cp "$(readlink -f "$(command -v innoextract)")" "$APP/Contents/Resources/bin/innoextract"
chmod u+w "$APP/Contents/Resources/bin/innoextract"
dylibbundler -of -b -x "$APP/Contents/Resources/bin/innoextract" \
  -d "$APP/Contents/Resources/lib" -p @executable_path/../lib >/dev/null

codesign --force --sign - "$APP/Contents/Resources/lib/"*.dylib
codesign --force --sign - "$APP/Contents/Resources/bin/innoextract"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Light, dark and tinted icon, compiled from brand/Plugd.icon by .github/workflows/icon.yml.
[ -f brand/Assets.car ] && cp brand/Assets.car "$APP/Contents/Resources/Assets.car"
cp THIRD_PARTY.md "$APP/Contents/Resources/THIRD_PARTY.md"
codesign --force --sign - "$APP"
ditto -c -k --keepParent "$APP" Plugd.zip
# Disk image with an Applications shortcut, so people drag the app in like any other.
DMG=$(mktemp -d)
cp -R "$APP" "$DMG/"
ln -s /Applications "$DMG/Applications"
rm -f Plugd.dmg
hdiutil create -quiet -volname Plugd -srcfolder "$DMG" -format UDZO Plugd.dmg
rm -rf "$DMG"
echo "built $(pwd)/$APP"
