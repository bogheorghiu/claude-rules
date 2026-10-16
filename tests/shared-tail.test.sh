#!/bin/bash
# The renderer and slicing code after the "shared tail" marker is the same in both
# plugins: each plugin folder must stand alone (a plugin can't read files outside its
# own root), so the code is copied, and this check keeps the copies from drifting.
cd "$(dirname "$0")/.." || exit 1
tail_of() { sed -n '/^# ==== shared tail/,$p' "$1"; }
a=plugins/shared-rules/hooks/sync-rules.sh
b=plugins/shared-rules-custom-repo/hooks/sync-repo.sh
if [ -z "$(tail_of "$a")" ]; then echo "FAIL - no shared tail marker in $a"; exit 1; fi
if diff <(tail_of "$a") <(tail_of "$b"); then echo "ok   - shared tail identical in both plugins"; else echo "FAIL - shared tails differ (diff above)"; exit 1; fi
