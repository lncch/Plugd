#!/bin/bash
# Writes and signs Sparkle's update feed for one release.
# Usage: tools/appcast.sh VERSION BUILD ZIP DOWNLOAD_URL OUT
# The zip is signed with the key in the login keychain (account "plugd"), then the feed itself is signed,
# because Plugd sets SURequireSignedFeed.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$1 BUILD=$2 ZIP=$3 URL=$4 OUT=$5
SIGN=vendor/sparkle/bin/sign_update
ENCLOSURE=$("$SIGN" --account plugd "$ZIP")   # sparkle:edSignature="…" length="…"
cat > "$OUT" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
<channel>
<title>Plugd</title>
<item>
<title>Plugd $VERSION</title>
<pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
<sparkle:version>$BUILD</sparkle:version>
<sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
<sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
<sparkle:fullReleaseNotesLink>https://github.com/lncch/Plugd/releases/tag/v$VERSION</sparkle:fullReleaseNotesLink>
<enclosure url="$URL" $ENCLOSURE type="application/octet-stream"/>
</item>
</channel>
</rss>
EOF
"$SIGN" --account plugd "$OUT" >/dev/null
"$SIGN" --account plugd --verify "$OUT"
echo "feed $OUT: Plugd $VERSION ($BUILD) -> $URL"
