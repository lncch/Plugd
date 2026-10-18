#!/bin/bash
# Builds ScanBridge.app with the command line tools (no Xcode).
set -euo pipefail
cd "$(dirname "$0")"

APP=ScanBridge.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/bin" "$APP/Contents/Resources/lib"

swiftc -O -parse-as-library -target arm64-apple-macos14.0 Sources/*.swift -o "$APP/Contents/MacOS/ScanBridge"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>ScanBridge</string>
  <key>CFBundleDisplayName</key><string>ScanBridge</string>
  <key>CFBundleIdentifier</key><string>dev.almoayyad.scanbridge</string>
  <key>CFBundleExecutable</key><string>ScanBridge</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
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
codesign --force --sign - "$APP"
ditto -c -k --keepParent "$APP" ScanBridge.zip
echo "built $(pwd)/$APP"
