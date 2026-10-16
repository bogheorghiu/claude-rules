#!/bin/bash
# Add "<sha256>  <path>" for every current bundled rule to rules-history.txt (never
# removes lines): a user's file holding text a release shipped under that same name
# counts as the plugin's own.
cd "$(dirname "$0")/../plugins/shared-rules" || exit 1
h() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }
{ cat rules-history.txt 2>/dev/null; (cd rules && find . -type f | sed 's#^\./##' | while IFS= read -r f; do printf '%s  %s\n' "$(h "$f")" "$f"; done); } | LC_ALL=C sort -u > rules-history.txt.new
mv rules-history.txt.new rules-history.txt
echo "rules-history.txt: $(wc -l < rules-history.txt) entries"
