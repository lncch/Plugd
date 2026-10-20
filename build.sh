#!/bin/bash
# Builds Plugd.app, Plugd.zip and Plugd.dmg with the command line tools.
set -euo pipefail
cd "$(dirname "$0")"

APP=Plugd.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/bin" "$APP/Contents/Resources/lib"

# Universal: Apple Silicon and Intel.
[ -d vendor/x86 ] || ./tools/innoextract-x86.sh
OBJ=$(mktemp -d)
for a in arm64 x86_64; do
  swiftc -O -parse-as-library -target $a-apple-macos14.0 Sources/*.swift -o "$OBJ/Plugd-$a"
done
lipo -create "$OBJ"/Plugd-* -output "$APP/Contents/MacOS/Plugd"
rm -rf "$OBJ"

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
  <key>CFBundleShortVersionString</key><string>0.3.3</string>
  <key>CFBundleVersion</key><string>8</string>
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

# Add the Intel half (built by tools/innoextract-x86.sh) to innoextract and each library.
for g in "$APP/Contents/Resources/bin/innoextract" "$APP/Contents/Resources/lib/"*.dylib; do
  lipo -create "$g" "vendor/x86/${g#"$APP/Contents/Resources/"}" -output "$g.fat"
  mv "$g.fat" "$g"
done
# Signing: Developer ID + hardened runtime when that certificate is in the keychain, else ad-hoc (local only).
ID=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)
if [ -n "$ID" ]; then SIGN=(codesign --force --options runtime --timestamp --sign "$ID"); else SIGN=(codesign --force --sign -); fi
"${SIGN[@]}" "$APP/Contents/Resources/lib/"*.dylib
"${SIGN[@]}" "$APP/Contents/Resources/bin/innoextract"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Light, dark and tinted icon, compiled from brand/Plugd.icon by .github/workflows/icon.yml.
[ -f brand/Assets.car ] && cp brand/Assets.car "$APP/Contents/Resources/Assets.car"
cp THIRD_PARTY.md "$APP/Contents/Resources/THIRD_PARTY.md"
"${SIGN[@]}" "$APP"
# Notarize (Apple's malware check) when the "plugd" notarytool profile exists; NOTARIZE=0 skips it.
NOTARY=""
if [ -n "$ID" ] && [ "${NOTARIZE:-1}" = 1 ] && xcrun notarytool history --keychain-profile plugd >/dev/null 2>&1; then
  NOTARY=yes
  ditto -c -k --keepParent "$APP" Plugd.zip
  xcrun notarytool submit Plugd.zip --keychain-profile plugd --wait | tee /dev/stderr | grep -q 'status: Accepted'
  xcrun stapler staple "$APP"
fi
ditto -c -k --keepParent "$APP" Plugd.zip
# Disk image with an Applications shortcut, so people drag the app in like any other.
DMG=$(mktemp -d)
cp -R "$APP" "$DMG/"
ln -s /Applications "$DMG/Applications"
rm -f Plugd.dmg
hdiutil create -quiet -volname Plugd -srcfolder "$DMG" -format UDZO Plugd.dmg
rm -rf "$DMG"
if [ -n "$NOTARY" ]; then
  codesign --force --timestamp --sign "$ID" Plugd.dmg
  xcrun notarytool submit Plugd.dmg --keychain-profile plugd --wait | tee /dev/stderr | grep -q 'status: Accepted'
  xcrun stapler staple Plugd.dmg
  spctl --assess --type open --context context:primary-signature Plugd.dmg
fi
echo "built $(pwd)/$APP (signed: ${ID:-ad-hoc}, notarized: ${NOTARY:-no})"
