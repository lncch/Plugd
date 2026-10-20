#!/bin/bash
# Builds the Intel half of the bundled innoextract into vendor/x86, so build.sh can make it universal.
# Homebrew on Apple Silicon only installs arm64, so this takes Homebrew's Intel (sonoma) bottles,
# and builds liblzma from source because xz has no Intel bottle any more. Every download is hash-checked.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=vendor/x86
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
rm -rf "$OUT"
mkdir -p "$OUT/bin" "$OUT/lib"

for f in innoextract boost zstd; do
  read -r url sha < <(curl -fsS "https://formulae.brew.sh/api/formula/$f.json" | python3 -c \
    "import json,sys; d=json.load(sys.stdin)['bottle']['stable']['files']['sonoma']; print(d['url'], d['sha256'])")
  curl -fsSL -H 'Authorization: Bearer QQ==' -o "$TMP/$f.tar.gz" "$url"
  echo "$sha  $TMP/$f.tar.gz" | shasum -a 256 -c - >/dev/null
  tar -xzf "$TMP/$f.tar.gz" -C "$TMP"
done

XZ=5.8.4
curl -fsSL -o "$TMP/xz.tar.gz" "https://github.com/tukaani-project/xz/releases/download/v$XZ/xz-$XZ.tar.gz"
echo "0014c7886930454fe8bd4228665b51af55eeae560ea135c9c4cd33f55b2591d9  $TMP/xz.tar.gz" | shasum -a 256 -c - >/dev/null
tar -xzf "$TMP/xz.tar.gz" -C "$TMP"
(cd "$TMP/xz-$XZ" && CFLAGS="-arch x86_64 -O2 -mmacosx-version-min=10.15" ./configure --host=x86_64-apple-darwin \
  --disable-static --disable-xz --disable-xzdec --disable-lzmadec --disable-lzmainfo --disable-scripts \
  --disable-doc --disable-nls --prefix="$TMP/xzout" >/dev/null && make -j8 >/dev/null && make install >/dev/null)

cp "$TMP"/innoextract/*/bin/innoextract "$OUT/bin/"
for l in atomic container date_time filesystem iostreams program_options random; do
  cp "$TMP"/boost/*/lib/libboost_$l.dylib "$OUT/lib/"
done
cp "$TMP"/zstd/*/lib/libzstd.1.*.*.dylib "$OUT/lib/"
cp "$TMP/xzout/lib/liblzma.5.dylib" "$OUT/lib/"
chmod u+w "$OUT"/bin/* "$OUT"/lib/*

# Point every library path at the app bundle, using the same file names as the arm64 half.
zstd=$(basename "$OUT"/lib/libzstd.1.*.*.dylib)
for f in "$OUT"/bin/innoextract "$OUT"/lib/*.dylib; do
  [[ $f == *.dylib ]] && install_name_tool -id "@executable_path/../lib/$(basename "$f")" "$f" 2>/dev/null
  { otool -L "$f" | tail -n +2 | awk '{print $1}' | grep -E '^(@@HOMEBREW|@loader_path|/.*xzout)' || true; } | while read -r dep; do
    name=$(basename "$dep")
    [[ $name == libzstd.1.dylib ]] && name=$zstd
    install_name_tool -change "$dep" "@executable_path/../lib/$name" "$f" 2>/dev/null
  done
  codesign --force --sign - "$f" 2>/dev/null
done
echo "built $(pwd)/$OUT"
