#!/bin/bash
# The helpers block and the renderer/slicing tail are the same in both plugins: each
# plugin folder must stand alone (a plugin can't read files outside its own root), so
# the code is copied, and this check keeps the copies from drifting.
cd "$(dirname "$0")/.." || exit 1
a=plugins/shared-rules/hooks/sync-rules.sh
b=plugins/shared-rules-custom-repo/hooks/sync-repo.sh
fail=0
block() { sed -n "/^# ==== $2/,/^# ==== end $2/p" "$1"; }
tail_of() { sed -n '/^# ==== shared tail/,$p' "$1"; }
for name in "shared helpers"; do
    if [ -z "$(block "$a" "$name")" ]; then echo "FAIL - no '$name' block in $a"; fail=1
    elif diff <(block "$a" "$name") <(block "$b" "$name"); then echo "ok   - $name identical in both plugins"
    else echo "FAIL - $name differ (diff above)"; fail=1; fi
done
if [ -z "$(tail_of "$a")" ]; then echo "FAIL - no shared tail marker in $a"; fail=1
elif diff <(tail_of "$a") <(tail_of "$b"); then echo "ok   - shared tail identical in both plugins"
else echo "FAIL - shared tails differ (diff above)"; fail=1; fi
exit $fail
