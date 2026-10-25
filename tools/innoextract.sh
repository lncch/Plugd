#!/bin/bash
# Builds the bundled innoextract from source into vendor/innoextract: one universal file
# (Apple Silicon + Intel) that runs on macOS 12 and newer, with Boost and liblzma linked in.
# Same recipe as Homebrew's: innoextract 1.9 plus its 3 patches, Boost 1.92. Every download is hash-checked.
# Needs cmake (brew install cmake). Takes a few minutes.
set -euo pipefail
cd "$(dirname "$0")/.."
MIN=12.0
OUT=vendor/innoextract
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
JOBS=$(sysctl -n hw.ncpu)

get() { # url sha256 file
  curl -fsSL -o "$TMP/$3" "$1"
  echo "$2  $TMP/$3" | shasum -a 256 -c - >/dev/null
}
GH=https://github.com/dscharrer/innoextract/commit
get https://constexpr.org/innoextract/files/innoextract-1.9.tar.gz 6344a69fc1ed847d4ed3e272e0da5998948c6b828cb7af39c6321aba6cf88126 ie.tar.gz
get "$GH/83d0bf4365b09ddd17dddb400ba5d262ddf16fb8.patch?full_index=1" fe5299d1fdea5c66287aef2f70fee41d86aedc460c5b165da621d699353db07d cmake4.patch
get "$GH/264c2fe6b84f90f6290c670e5f676660ec7b2387.patch?full_index=1" f968a9c0521083dd4076ce5eed56127099a9c9888113fc50f476b914396045cc boost185.patch
get "$GH/882796e0e9b134b02deeaae4bbfe92920adb6fe2.patch?full_index=1" d5af3e86eb2b74bff559885440d330678e5dbb028ce165bb836ddb14224af201 boost189.patch
get https://github.com/boostorg/boost/releases/download/boost-1.92.0/boost-1.92.0-b2-nodocs.tar.xz ea7b982002cc9dfbe59b0b217b206f470dc75f3de0bb2973d844118934d82411 boost.tar.xz
XZ=5.8.4
get "https://github.com/tukaani-project/xz/releases/download/v$XZ/xz-$XZ.tar.gz" 0014c7886930454fe8bd4228665b51af55eeae560ea135c9c4cd33f55b2591d9 xz.tar.gz

tar -xzf "$TMP/ie.tar.gz" -C "$TMP"
(cd "$TMP/innoextract-1.9" && for p in cmake4 boost185 boost189; do patch -s -p1 < "$TMP/$p.patch"; done)
tar -xJf "$TMP/boost.tar.xz" -C "$TMP"
tar -xzf "$TMP/xz.tar.gz" -C "$TMP"
(cd "$TMP/boost-1.92.0" && ./bootstrap.sh --with-toolset=clang \
  --with-libraries=atomic,container,date_time,filesystem,iostreams,program_options,random,system >/dev/null)

for a in arm64 x86_64; do
  F="-arch $a -mmacosx-version-min=$MIN -O2"
  P="$TMP/prefix-$a"
  # liblzma, static
  (cd "$TMP/xz-$XZ" && make distclean >/dev/null 2>&1 || true
   CFLAGS="$F" ./configure --host=$a-apple-darwin --enable-static --disable-shared --disable-xz --disable-xzdec \
     --disable-lzmadec --disable-lzmainfo --disable-scripts --disable-doc --disable-nls --prefix="$P" >/dev/null
   make -j"$JOBS" >/dev/null && make install >/dev/null)
  # Boost, static. iostreams uses the system zlib and bzip2; its lzma and zstd filters aren't needed.
  [ $a = arm64 ] && arch=arm || arch=x86
  (cd "$TMP/boost-1.92.0" && ./b2 -q -j"$JOBS" toolset=clang link=static variant=release threading=multi \
     architecture=$arch address-model=64 cflags="$F" cxxflags="$F" linkflags="$F" \
     -sNO_LZMA=1 -sNO_ZSTD=1 --build-dir="$TMP/boost-build-$a" --prefix="$P" install >/dev/null)
  # innoextract, linked against the static Boost and liblzma above.
  cmake -S "$TMP/innoextract-1.9" -B "$TMP/ie-$a" -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=$a \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=$MIN -DCMAKE_PREFIX_PATH="$P" -DBoost_USE_STATIC_LIBS=ON \
    -DLZMA_USE_STATIC_LIBS=ON -DUSE_LTO=OFF >/dev/null
  cmake --build "$TMP/ie-$a" -j"$JOBS" >/dev/null
  # Only system libraries may be left as dynamic links, or the app would need to ship them.
  if otool -L "$TMP/ie-$a/innoextract" | tail -n +2 | grep -v -E '^\s+(/usr/lib|/System)/'; then
    echo "innoextract ($a) links a library outside the system" >&2; exit 1
  fi
done

rm -rf "$OUT"
mkdir -p "$OUT"
lipo -create "$TMP/ie-arm64/innoextract" "$TMP/ie-x86_64/innoextract" -output "$OUT/innoextract"
"$OUT/innoextract" --version | head -1
