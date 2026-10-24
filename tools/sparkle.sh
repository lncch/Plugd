#!/bin/bash
# Downloads Sparkle (Plugd's updater) into vendor/sparkle: the framework plus sign_update and generate_keys.
# Pinned to one release; the download must match the SHA-256 GitHub publishes for it.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=2.10.0
SHA=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
OUT=vendor/sparkle
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl -fsSL -o "$TMP/sparkle.tar.xz" "https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-$VERSION.tar.xz"
echo "$SHA  $TMP/sparkle.tar.xz" | shasum -a 256 -c -
rm -rf "$OUT"
mkdir -p "$OUT"
tar -xf "$TMP/sparkle.tar.xz" -C "$OUT"
echo "Sparkle $VERSION in $OUT"
