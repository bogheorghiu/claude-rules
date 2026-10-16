#!/bin/bash
# Tests for sync-repo.sh, against local fixture repos served over file://.
#
# What they do NOT prove: that Claude Code loads ~/.claude/rules natively (observed
# live, see docs/DESIGN-managed-rules.md), or that a given remote is reachable.
# Rule-format and slicing behaviour is shared with shared-rules and tested there.

set -u

HOOK="$(cd "$(dirname "$0")" && pwd)/sync-repo.sh"
BASE_HOOK="$(cd "$(dirname "$0")/../../shared-rules/hooks" && pwd)/sync-rules.sh"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

pass=0
fail=0
check() {
    if [ "$2" = "1" ]; then echo "  ok   - $1"; pass=$((pass + 1))
    else echo "  FAIL - $1"; fail=$((fail + 1)); fi
}
has() { case "$1" in *"$2"*) echo 1 ;; *) echo 0 ;; esac; }

# MODE defaults to auto so fetch tests see each upstream change at once; the ask tests
# pass their own, including none, to exercise the hook's real default.
start() { # HOME URL [MODE]: one session start
    printf '{"session_id":"s%s"}' "$RANDOM$RANDOM" | env -i HOME="$1" PATH="$PATH" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
        CLAUDE_PLUGIN_DATA="$1/data" CLAUDE_PLUGIN_OPTION_RULES_REPO="$2" CLAUDE_PLUGIN_OPTION_UPDATE_MODE="${3-auto}" \
        bash "$HOOK" part 1 1; }
cmd() { local h="$1" u="$2"; shift 2
    env -i HOME="$h" PATH="$PATH" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
        CLAUDE_PLUGIN_DATA="$h/data" CLAUDE_PLUGIN_OPTION_RULES_REPO="$u" bash "$HOOK" "$@"; }
T() { echo "$1/.claude/rules/shared-rules-custom-repo"; }
same_rules() { diff -r -x .custom-repo.manifest "$(T "$1")" "$2/rules" >/dev/null 2>&1 && echo 1 || echo 0; }
repo() { mkdir -p "$1/rules"; git -C "$1" init -q; }
commit() { git -C "$1" add -A && git -C "$1" commit -qm "$2"; }

echo "Testing sync-repo.sh"
echo "===================="

# --- Setting checks ---
H0="$TMP_DIR/h0"; mkdir -p "$H0"
check "no repo set: says how to set one" "$(has "$(start "$H0" "")" '/plugin configure')"
check "repo set to the shared-rules repo itself: says so, loads nothing" "$([ "$(has "$(start "$H0" "https://github.com/bogheorghiu/claude-rules.git")" 'already installs')" = 1 ] && [ ! -e "$(T "$H0")" ] && echo 1 || echo 0)"

# --- First clone ---
SRC="$TMP_DIR/src"; repo "$SRC"
printf '# Always\nALWAYS_BODY\n' > "$SRC/rules/always.md"
mkdir -p "$SRC/rules/sub"; printf '# Sub\nSUB_BODY\n' > "$SRC/rules/sub/n.md"
printf 'README_BODY\n' > "$SRC/README.md"; commit "$SRC" init
A="$TMP_DIR/a"; mkdir -p "$A"
o=$(start "$A" "file://$SRC"); rc=$?
check "first clone: exits 0" "$([ $rc -eq 0 ] && echo 1 || echo 0)"
check "first clone: folder mirrors the repo's rules/ exactly" "$(same_rules "$A" "$SRC")"
check "first clone: nothing outside rules/ is copied" "$([ ! -e "$(T "$A")/README.md" ] && echo 1 || echo 0)"
check "first clone: prints the rules for this session" "$([ "$(has "$o" ALWAYS_BODY)" = 1 ] && [ "$(has "$o" SUB_BODY)" = 1 ] && echo 1 || echo 0)"
check "first clone: asks whether to keep both sets" "$([ "$(has "$o" 'combine both')" = 1 ] && [ "$(has "$o" 'combine replace')" = 1 ] && echo 1 || echo 0)"
cmd "$A" "file://$SRC" combine both >/dev/null
check "after answering: same version prints nothing" "$([ -z "$(start "$A" "file://$SRC")" ] && echo 1 || echo 0)"

# --- Upstream changes, auto mode ---
printf '# Two\nTWO_BODY\n' > "$SRC/rules/two.md"; git -C "$SRC" rm -q rules/sub/n.md; commit "$SRC" two
o=$(start "$A" "file://$SRC")
check "auto: a new rule is mirrored and printed" "$([ "$(same_rules "$A" "$SRC")" = 1 ] && [ "$(has "$o" TWO_BODY)" = 1 ] && echo 1 || echo 0)"
check "auto: unchanged rules are not reprinted" "$([ "$(has "$o" ALWAYS_BODY)" = 0 ] && echo 1 || echo 0)"
check "auto: a rule removed upstream leaves the folder" "$([ ! -e "$(T "$A")/sub/n.md" ] && echo 1 || echo 0)"

# --- Source unreachable ---
mv "$SRC" "$SRC.gone"
o=$(start "$A" "file://$SRC")
check "unreachable, folder present: prints nothing, folder kept" "$([ -z "$o" ] && [ -f "$(T "$A")/two.md" ] && echo 1 || echo 0)"
mv "$SRC.gone" "$SRC"
B="$TMP_DIR/b"; mkdir -p "$B"
check "unreachable, nothing cached: one-line notice" "$(has "$(start "$B" "file://$TMP_DIR/nope")" 'could not fetch')"

# --- Force-pushed upstream: the mirror follows it ---
git -C "$SRC" checkout -q --orphan fresh && git -C "$SRC" rm -rqf . && repo "$SRC"
printf '# New history\nNEWHIST_BODY\n' > "$SRC/rules/h.md"; commit "$SRC" rewrite
git -C "$SRC" branch -D master >/dev/null 2>&1 || git -C "$SRC" branch -D main >/dev/null 2>&1
git -C "$SRC" branch -m "$(git -C "$SRC" branch --show-current)" master 2>/dev/null
git -C "$SRC" symbolic-ref HEAD refs/heads/master
check "force-push: the folder follows the rewritten history" "$([ "$(has "$(start "$A" "file://$SRC")" NEWHIST_BODY)" = 1 ] && [ "$(same_rules "$A" "$SRC")" = 1 ] && echo 1 || echo 0)"

# --- The rules_repo setting changes: the new repo replaces the old one's rules ---
SRC2="$TMP_DIR/src2"; repo "$SRC2"; printf '# Other\nOTHER_BODY\n' > "$SRC2/rules/o.md"; commit "$SRC2" init
check "URL change: the folder mirrors the new repo" "$([ "$(has "$(start "$A" "file://$SRC2")" OTHER_BODY)" = 1 ] && [ "$(same_rules "$A" "$SRC2")" = 1 ] && echo 1 || echo 0)"

# --- Ask mode (the default): changes wait for approval of the exact version shown ---
SRC4="$TMP_DIR/src4"; repo "$SRC4"; printf '# One\nONE_BODY\n' > "$SRC4/rules/one.md"; commit "$SRC4" init
C="$TMP_DIR/c"; mkdir -p "$C"
start "$C" "file://$SRC4" "" >/dev/null; cmd "$C" "file://$SRC4" combine both >/dev/null
printf '# Two\nTWO_BODY\n' > "$SRC4/rules/two.md"; commit "$SRC4" two
o=$(start "$C" "file://$SRC4" ""); want=$(git -C "$SRC4" rev-parse HEAD)
check "ask: the update waits, folder unchanged" "$([ ! -e "$(T "$C")/two.md" ] && echo 1 || echo 0)"
check "ask: notice names the new rule and the exact version" "$([ "$(has "$o" two.md)" = 1 ] && [ "$(has "$o" "approve $want")" = 1 ] && echo 1 || echo 0)"
approve=$(printf '%s\n' "$o" | grep -E '^ +CLAUDE_PLUGIN_DATA=.* approve ' | sed 's/^ *//')
env -i HOME="$C" PATH="$PATH" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null bash -c "$approve" >/dev/null 2>&1; rc=$?
check "ask: the printed approve command works and mirrors the version" "$([ $rc -eq 0 ] && [ "$(same_rules "$C" "$SRC4")" = 1 ] && echo 1 || echo 0)"
check "ask: after approving, the next session prints nothing" "$([ -z "$(start "$C" "file://$SRC4" "")" ] && echo 1 || echo 0)"
printf 'readme\n' > "$SRC4/README.md"; commit "$SRC4" readme
check "ask: a change outside rules/ asks nothing" "$([ "$(has "$(start "$C" "file://$SRC4" "")" 'awaiting')" = 0 ] && echo 1 || echo 0)"
printf '# Three\nTHREE_BODY\n' > "$SRC4/rules/three.md"; commit "$SRC4" three
check "an unrecognised mode behaves as ask" "$([ "$(has "$(start "$C" "file://$SRC4" sometimes)" 'awaiting')" = 1 ] && [ ! -e "$(T "$C")/three.md" ] && echo 1 || echo 0)"
check "mode is case-insensitive (AUTO applies)" "$([ "$(has "$(start "$C" "file://$SRC4" AUTO)" THREE_BODY)" = 1 ] && echo 1 || echo 0)"
check "approve refuses an unknown version" "$(cmd "$C" "file://$SRC4" approve 0000000000000000000000000000000000000000 >/dev/null 2>&1; [ $? -ne 0 ] && echo 1 || echo 0)"
check "approve refuses a moving name like FETCH_HEAD" "$(cmd "$C" "file://$SRC4" approve FETCH_HEAD >/dev/null 2>&1; [ $? -ne 0 ] && echo 1 || echo 0)"
mkdir "$C/data/cache.lock"; ( sleep 2; rmdir "$C/data/cache.lock" ) &
t0=$(date +%s%N); cmd "$C" "file://$SRC4" approve "$(git -C "$SRC4" rev-parse HEAD)" >/dev/null 2>&1; rc=$?; ms=$(( ($(date +%s%N) - t0) / 1000000 )); wait
check "approve waits for a held lock, then succeeds" "$([ $rc -eq 0 ] && [ $ms -ge 1500 ] && echo 1 || echo 0)"

# Without CLAUDE_PLUGIN_DATA, and with a quote in the data path, the printed command still works.
for kind in nodata quoted; do
    SRC5="$TMP_DIR/src5$kind"; repo "$SRC5"; printf '# One\nONE\n' > "$SRC5/rules/one.md"; commit "$SRC5" init
    H="$TMP_DIR/h$kind"; mkdir -p "$H"; D="$TMP_DIR/d a'ta$kind"
    env5() { if [ "$kind" = nodata ]; then env -i HOME="$H" PATH="$PATH" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null CLAUDE_PLUGIN_OPTION_RULES_REPO="file://$SRC5" "$@"
             else env -i HOME="$H" PATH="$PATH" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null CLAUDE_PLUGIN_DATA="$D" CLAUDE_PLUGIN_OPTION_RULES_REPO="file://$SRC5" "$@"; fi; }
    env5 bash "$HOOK" </dev/null >/dev/null
    printf '# Two\nTWO\n' > "$SRC5/rules/two.md"; commit "$SRC5" two
    approve=$(env5 bash "$HOOK" </dev/null | grep -E '^ +CLAUDE_PLUGIN_DATA=.* approve ' | sed 's/^ *//')
    env -i HOME="$H" PATH="$PATH" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null bash -c "$approve" >/dev/null 2>&1; rc=$?
    check "$kind: notice prints an approve command for the new version" "$(has "$approve" "approve $(git -C "$SRC5" rev-parse HEAD)")"
    check "$kind: printed approve command works" "$([ $rc -eq 0 ] && [ -f "$(T "$H")/two.md" ] && echo 1 || echo 0)"
done

# --- A repo cloned while still empty loads its first rules once they are pushed ---
SRC9="$TMP_DIR/src9"; mkdir -p "$SRC9"; git -C "$SRC9" init -q
E="$TMP_DIR/e"; mkdir -p "$E"; start "$E" "file://$SRC9" "" >/dev/null
mkdir -p "$SRC9/rules"; printf '# Early\nEARLY_BODY\n' > "$SRC9/rules/early.md"; commit "$SRC9" early
check "repo empty at first clone: its first rules load once pushed" "$(has "$(start "$E" "file://$SRC9" "")" EARLY_BODY)"

# --- A cache folder left without .git doesn't swallow later clones ---
F="$TMP_DIR/f"; mkdir -p "$F/data/repo/rules"
check "leftover cache folder without .git: rules still load" "$(has "$(start "$F" "file://$SRC4")" ONE_BODY)"

# --- A repo with no rules says so ---
SRC3="$TMP_DIR/src3"; mkdir -p "$SRC3"; git -C "$SRC3" init -q; printf 'x\n' > "$SRC3/README.md"; commit "$SRC3" init
G="$TMP_DIR/g"; mkdir -p "$G"
check "fetched repo without rules says so" "$(has "$(start "$G" "file://$SRC3")" 'no files under rules/')"

# --- A token in the repo URL never reaches the session's context ---
I="$TMP_DIR/i"; mkdir -p "$I"
o=$(start "$I" "https://user:SECRET_TOKEN@127.0.0.1:1/none.git")
check "token in repo URL: not printed" "$([ "$(has "$o" SECRET_TOKEN)" = 0 ] && [ "$(has "$o" '127.0.0.1:1/none.git')" = 1 ] && echo 1 || echo 0)"

# --- A SHA-256 rules repo: its 64-digit versions can be approved ---
SRC11="$TMP_DIR/src11"; mkdir -p "$SRC11/rules"
if git -C "$SRC11" init -q --object-format=sha256 2>/dev/null; then
    printf '# A\nA_BODY\n' > "$SRC11/rules/a.md"; commit "$SRC11" init
    J="$TMP_DIR/j"; mkdir -p "$J"; start "$J" "file://$SRC11" "" >/dev/null
    printf '# B\nB_BODY\n' > "$SRC11/rules/b.md"; commit "$SRC11" b
    approve=$(start "$J" "file://$SRC11" "" | grep -E '^ +CLAUDE_PLUGIN_DATA=.* approve ' | sed 's/^ *//')
    env -i HOME="$J" PATH="$PATH" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null bash -c "$approve" >/dev/null 2>&1; rc=$?
    check "sha256 repo: printed approve command works" "$([ $rc -eq 0 ] && [ -f "$(T "$J")/b.md" ] && echo 1 || echo 0)"
fi

# --- A later start of the session that printed the rules (/compact, resume) prints them again ---
K="$TMP_DIR/k"; mkdir -p "$K"
ks() { printf '{"session_id":"%s"}' "$1" | env -i HOME="$K" PATH="$PATH" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
    CLAUDE_PLUGIN_DATA="$K/data" CLAUDE_PLUGIN_OPTION_RULES_REPO="file://$SRC4" CLAUDE_PLUGIN_OPTION_UPDATE_MODE=auto bash "$HOOK"; }
ks sessK >/dev/null
check "compact/resume of the installing session: rules printed again" "$(has "$(ks sessK)" ONE_BODY)"
check "a new session after it: no rule bodies" "$([ "$(has "$(ks sessL)" ONE_BODY)" = 0 ] && echo 1 || echo 0)"

# --- Keep both, or replace the bundled shared-rules set ---
L="$TMP_DIR/l"; mkdir -p "$L"
printf '{"session_id":"b1"}' | env -i HOME="$L" PATH="$PATH" CLAUDE_PLUGIN_DATA="$L/bdata" bash "$BASE_HOOK" >/dev/null   # shared-rules installs its set
start "$L" "file://$SRC4" >/dev/null
cmd "$L" "file://$SRC4" combine replace "$L/bk" >/dev/null 2>&1; rc=$?
check "replace: exits 0" "$([ $rc -eq 0 ] && echo 1 || echo 0)"
check "replace: the bundled set moves to the backup" "$([ ! -e "$L/.claude/rules/shared-rules" ] && [ -f "$L/bk/shared-rules/.shared-rules.manifest" ] && echo 1 || echo 0)"
check "replace: shared-rules then installs and prints nothing" "$(o=$(printf '{"session_id":"b2"}' | env -i HOME="$L" PATH="$PATH" CLAUDE_PLUGIN_DATA="$L/bdata" bash "$BASE_HOOK"); [ -z "$o" ] && [ ! -e "$L/.claude/rules/shared-rules" ] && echo 1 || echo 0)"
check "replace: the question is not asked again" "$([ "$(has "$(start "$L" "file://$SRC4")" 'combine')" = 0 ] && echo 1 || echo 0)"
cmd "$L" "file://$SRC4" combine both >/dev/null
printf '{"session_id":"b3"}' | env -i HOME="$L" PATH="$PATH" CLAUDE_PLUGIN_DATA="$L/bdata" bash "$BASE_HOOK" >/dev/null
check "both, after replace: shared-rules installs its set again" "$([ -f "$L/.claude/rules/shared-rules/.shared-rules.manifest" ] && echo 1 || echo 0)"
M="$TMP_DIR/m"; mkdir -p "$M/.claude/rules/shared-rules"; printf 'x\n' > "$M/.claude/rules/shared-rules/theirs.md"
cmd "$M" "file://$SRC4" combine replace "$M/bk" >/dev/null 2>&1
check "replace: a shared-rules folder the plugin didn't make is left alone" "$([ -f "$M/.claude/rules/shared-rules/theirs.md" ] && echo 1 || echo 0)"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
