#!/bin/bash
# Builds Plugd.app, Plugd.zip and Plugd.dmg with the command line tools.
set -euo pipefail
cd "$(dirname "$0")"

APP=Plugd.app
VERSION=0.3.5
BUILD=10   # Sparkle compares this number, so it goes up by one every release
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/bin" "$APP/Contents/Resources/lib" "$APP/Contents/Frameworks"

# Universal: Apple Silicon and Intel.
[ -d vendor/x86 ] || ./tools/innoextract-x86.sh
[ -d vendor/sparkle ] || ./tools/sparkle.sh
OBJ=$(mktemp -d)
for a in arm64 x86_64; do
  swiftc -O -parse-as-library -target $a-apple-macos14.0 -F vendor/sparkle -framework Sparkle \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks Sources/*.swift -o "$OBJ/Plugd-$a"
done
lipo -create "$OBJ"/Plugd-* -output "$APP/Contents/MacOS/Plugd"
rm -rf "$OBJ"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Plugd</string>
  <key>CFBundleDisplayName</key><string>Plugd</string>
  <key>CFBundleIdentifier</key><string>dev.almoayyad.plugd</string>
  <key>CFBundleExecutable</key><string>Plugd</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>Plugd</string>
  <key>SUFeedURL</key><string>https://plugd.almoayyad.dev/appcast.xml</string>
  <key>SUPublicEDKey</key><string>TpAfV3C6ywJEXiUYDqid4f8fZ58vLYMr3q2rZ8NXt9o=</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUVerifyUpdateBeforeExtraction</key><true/>
  <key>SURequireSignedFeed</key><true/>
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
# Sparkle, Plugd's updater. Plugd isn't sandboxed, so Sparkle's XPC helpers aren't needed.
# Sign each part on its own, inside out; Sparkle's docs warn against --deep.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
ditto vendor/sparkle/Sparkle.framework "$SPARKLE"
rm -rf "$SPARKLE/Versions/B/XPCServices" "$SPARKLE/XPCServices"
"${SIGN[@]}" "$SPARKLE/Versions/B/Autoupdate"
"${SIGN[@]}" "$SPARKLE/Versions/B/Updater.app"
"${SIGN[@]}" "$SPARKLE"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Light, dark and tinted icon, compiled from brand/Plugd.icon by .github/workflows/icon.yml.
[ -f brand/Assets.car ] && cp brand/Assets.car "$APP/Contents/Resources/Assets.car"
cp THIRD_PARTY.md "$APP/Contents/Resources/THIRD_PARTY.md"
cp vendor/sparkle/LICENSE "$APP/Contents/Resources/Sparkle-LICENSE.txt"
"${SIGN[@]}" "$APP"
# Notarize (Apple's malware check) when the "plugd" notarytool profile exists; NOTARIZE=0 skips it.
NOTARY=""
if [ -n "$ID" ] && [ "${NOTARIZE:-1}" = 1 ] && xcrun notarytool history --keychain-profile plugd >/dev/null 2>&1; then
  NOTARY=yes
  ditto -c -k --keepParent "$APP" Plugd.zip
  xcrun notarytool submit Plugd.zip --keychain-profile plugd --wait | tee /dev/stderr | grep 'status: Accepted' >/dev/null
  xcrun stapler staple "$APP"
fi
ditto -c -k --keepParent "$APP" Plugd.zip
# Sparkle's update feed, pointing at this zip on the GitHub release and signed with the key in the
# keychain (account "plugd"). Publish it only after the release is up, or the download link 404s.
if [ -n "$NOTARY" ]; then
  ./tools/appcast.sh "$VERSION" "$BUILD" Plugd.zip "https://github.com/lncch/Plugd/releases/download/v$VERSION/Plugd.zip" docs/appcast.xml
fi
# Disk image with an Applications shortcut, so people drag the app in like any other.
DMG=$(mktemp -d)
cp -R "$APP" "$DMG/"
ln -s /Applications "$DMG/Applications"
rm -f Plugd.dmg
hdiutil create -quiet -volname Plugd -srcfolder "$DMG" -format UDZO Plugd.dmg
rm -rf "$DMG"
if [ -n "$NOTARY" ]; then
  codesign --force --timestamp --sign "$ID" Plugd.dmg
  xcrun notarytool submit Plugd.dmg --keychain-profile plugd --wait | tee /dev/stderr | grep 'status: Accepted' >/dev/null
  xcrun stapler staple Plugd.dmg
  spctl --assess --type open --context context:primary-signature Plugd.dmg
fi
echo "built $(pwd)/$APP (signed: ${ID:-ad-hoc}, notarized: ${NOTARY:-no})"
