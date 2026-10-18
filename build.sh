#!/bin/bash
# Builds OBDock.app with the command line tools (no Xcode).
set -euo pipefail
cd "$(dirname "$0")"

APP=OBDock.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/bin" "$APP/Contents/Resources/lib"

swiftc -O -parse-as-library -target arm64-apple-macos14.0 Sources/*.swift -o "$APP/Contents/MacOS/OBDock"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>OBDock</string>
  <key>CFBundleDisplayName</key><string>OBDock</string>
  <key>CFBundleIdentifier</key><string>dev.almoayyad.obdock</string>
  <key>CFBundleExecutable</key><string>OBDock</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.2.1</string>
  <key>CFBundleVersion</key><string>4</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleIconFile</key><string>AppIcon</string>
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
cp THIRD_PARTY.md "$APP/Contents/Resources/THIRD_PARTY.md"
codesign --force --sign - "$APP"
ditto -c -k --keepParent "$APP" OBDock.zip
echo "built $(pwd)/$APP"
