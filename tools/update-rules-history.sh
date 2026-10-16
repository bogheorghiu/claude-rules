#!/bin/bash
# Add the sha256 of every current bundled rule to rules-history.txt (never removes
# lines): a user's copy of any text a release ever shipped counts as the plugin's own.
cd "$(dirname "$0")/../plugins/shared-rules" || exit 1
h() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }
{ cat rules-history.txt 2>/dev/null; find rules -type f | while read -r f; do h "$f"; done; } | LC_ALL=C sort -u > rules-history.txt.new
mv rules-history.txt.new rules-history.txt
echo "rules-history.txt: $(wc -l < rules-history.txt) hashes"
