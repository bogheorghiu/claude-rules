#!/bin/bash
# Tests for load-rules.sh, run against a local fixture repo served over file://.
#
# What they do NOT prove: that the live harness injects SessionStart stdout into
# context, or that github.com is reachable from a given cloud environment.

set -u

HOOK="$(cd "$(dirname "$0")" && pwd)/load-rules.sh"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Pin ambient git config so a developer's settings can't change results.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

pass=0
fail=0
check() {
    if [ "$2" = "1" ]; then echo "  ok   - $1"; pass=$((pass + 1))
    else echo "  FAIL - $1"; fail=$((fail + 1)); fi
}
has() { case "$1" in *"$2"*) echo 1 ;; *) echo 0 ;; esac; }

# Fixture source repo: one always-on rule, one path-scoped rule, one non-rule file.
SRC="$TMP_DIR/src"
mkdir -p "$SRC/rules"
printf '# Always rule\nALWAYS_BODY\n' > "$SRC/rules/always.md"
printf -- '---\npaths:\n  - "src/**"\n---\n# Scoped rule\nSCOPED_BODY\n' > "$SRC/rules/scoped.md"
printf 'README_BODY\n' > "$SRC/README.md"
git -C "$SRC" init -q && git -C "$SRC" add -A && git -C "$SRC" commit -qm init

# Args: HOME dir, repo url, update mode. Mode defaults to auto here, so the fetch and
# cache tests below see each upstream change at once; the ask-mode section passes
# its own value, including none, to exercise the hook's real default.
run_hook() {
    env -i HOME="$1" PATH="$PATH" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
        CLAUDE_PLUGIN_DATA="$1/data" CLAUDE_PLUGIN_OPTION_RULES_REPO="$2" \
        CLAUDE_PLUGIN_OPTION_UPDATE_MODE="${3-auto}" bash "$HOOK" </dev/null
}

echo "Testing load-rules.sh"
echo "====================="

# --- First run: clones and prints ---
H1="$TMP_DIR/h1"; mkdir -p "$H1"
out=$(run_hook "$H1" "file://$SRC"); rc=$?
check "first run exits 0" "$([ $rc -eq 0 ] && echo 1 || echo 0)"
check "always-on rule printed in full" "$(has "$out" ALWAYS_BODY)"
check "path-scoped rule body NOT printed" "$([ "$(has "$out" SCOPED_BODY)" = 0 ] && echo 1 || echo 0)"
check "path-scoped rule listed with its paths" "$(has "$out" 'src/**')"
check "path-scoped rule listed with its file location" "$(has "$out" "$H1/data/claude-rules/rules/scoped.md")"
check "non-rule README not printed" "$([ "$(has "$out" README_BODY)" = 0 ] && echo 1 || echo 0)"

# --- A rule added upstream reaches the next session (one-file drop) ---
printf '# New rule\nNEW_BODY\n' > "$SRC/rules/new.md"
git -C "$SRC" add -A && git -C "$SRC" commit -qm add
out=$(run_hook "$H1" "file://$SRC")
check "rule dropped upstream appears after pull" "$(has "$out" NEW_BODY)"

# --- Source unreachable, cache present: falls back to cache ---
# Move the source away: the cache pulls from its own recorded origin, not the URL.
mv "$SRC" "$SRC.gone"
out=$(run_hook "$H1" "file://$SRC"); rc=$?
mv "$SRC.gone" "$SRC"
check "unreachable source with cache exits 0" "$([ $rc -eq 0 ] && echo 1 || echo 0)"
check "unreachable source with cache still prints cached rules" "$(has "$out" ALWAYS_BODY)"
check "unreachable source with cache says copies may be stale" "$(has "$out" 'may be out of date')"

# --- Upstream history rewritten (force-push): cache follows it, no freeze ---
branch=$(git -C "$SRC" symbolic-ref --short HEAD)
git -C "$SRC" checkout -q --orphan rewritten
printf '# Rewritten\nREWRITTEN_BODY\n' > "$SRC/rules/always.md"
git -C "$SRC" add -A && git -C "$SRC" commit -qm rewritten
git -C "$SRC" branch -q -M rewritten "$branch"
out=$(run_hook "$H1" "file://$SRC")
check "force-pushed upstream content reaches the cache" "$(has "$out" REWRITTEN_BODY)"
check "force-pushed upstream: no stale notice" "$([ "$(has "$out" 'may be out of date')" = 0 ] && echo 1 || echo 0)"

# --- Configured URL changes: the cache is re-cloned from the new source ---
SRC2="$TMP_DIR/src2"; mkdir -p "$SRC2/rules"
printf '# Other\nOTHER_BODY\n' > "$SRC2/rules/other.md"
git -C "$SRC2" init -q && git -C "$SRC2" add -A && git -C "$SRC2" commit -qm init
out=$(run_hook "$H1" "file://$SRC2")
check "changed repo URL: new source's rules printed" "$(has "$out" OTHER_BODY)"
check "changed repo URL: old source's rules gone" "$([ "$(has "$out" REWRITTEN_BODY)" = 0 ] && echo 1 || echo 0)"

# --- CRLF frontmatter is still recognised as path-scoped ---
printf -- '---\r\npaths:\r\n  - "x/**"\r\n---\r\nCRLF_BODY\r\n' > "$SRC2/rules/crlf.md"
git -C "$SRC2" add -A && git -C "$SRC2" commit -qm crlf
out=$(run_hook "$H1" "file://$SRC2")
check "CRLF path-scoped rule body NOT printed" "$([ "$(has "$out" CRLF_BODY)" = 0 ] && echo 1 || echo 0)"

# --- Rules grouped in subfolders are loaded, alongside top-level ones ---
mkdir -p "$SRC2/rules/group"
printf '# Nested\nNESTED_BODY\n' > "$SRC2/rules/group/nested.md"
git -C "$SRC2" add -A && git -C "$SRC2" commit -qm nested
out=$(run_hook "$H1" "file://$SRC2")
check "rule in a subfolder of rules/ printed" "$(has "$out" NESTED_BODY)"
check "subfolder rule named by its path under rules/" "$(has "$out" '=== rule: group/nested.md ===')"
check "top-level rule still printed next to subfolder rules" "$(has "$out" OTHER_BODY)"

# --- Fetch succeeds but the repo has no rules: say that, not "could not fetch" ---
SRC3="$TMP_DIR/src3"; mkdir -p "$SRC3"
printf 'no rules here\n' > "$SRC3/README.md"
git -C "$SRC3" init -q && git -C "$SRC3" add -A && git -C "$SRC3" commit -qm init
H5="$TMP_DIR/h5"; mkdir -p "$H5"
out=$(run_hook "$H5" "file://$SRC3"); rc=$?
check "fetched repo without rules exits 0" "$([ $rc -eq 0 ] && echo 1 || echo 0)"
check "fetched repo without rules says it was fetched" "$(has "$out" 'was fetched but has no .md files')"
check "fetched repo without rules does not blame the fetch" "$([ "$(has "$out" 'could not fetch')" = 0 ] && echo 1 || echo 0)"

# --- Ask mode (the default): changes wait for approval of the exact version shown ---
SRC4="$TMP_DIR/src4"; mkdir -p "$SRC4/rules"
printf '# Base\nBASE_BODY\n' > "$SRC4/rules/base.md"
git -C "$SRC4" init -q && git -C "$SRC4" add -A && git -C "$SRC4" commit -qm init
H6="$TMP_DIR/h6"; mkdir -p "$H6"
out=$(run_hook "$H6" "file://$SRC4" "")
check "ask (unset mode): first clone loads its rules" "$(has "$out" BASE_BODY)"
printf '# Added\nADDED_BODY\n' > "$SRC4/rules/added.md"
git -C "$SRC4" add -A && git -C "$SRC4" commit -qm added
want=$(git -C "$SRC4" rev-parse HEAD)
out=$(run_hook "$H6" "file://$SRC4" "")
check "ask: new upstream rule not loaded before approval" "$([ "$(has "$out" ADDED_BODY)" = 0 ] && echo 1 || echo 0)"
check "ask: approved rules still load" "$(has "$out" BASE_BODY)"
check "ask: notice names the pending version" "$(has "$out" "newer version $want")"
check "ask: notice lists the changed rule file" "$(has "$out" 'rules/added.md')"
approve=$(printf '%s\n' "$out" | grep -E '^ +CLAUDE_PLUGIN_DATA=.* approve ' | sed 's/^ *//')
check "ask: notice carries an approve command for that version" "$(has "$approve" "approve $want")"
env -i HOME="$H6" PATH="$PATH" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
    bash -c "$approve" >/dev/null 2>&1; rc=$?
check "ask: the printed approve command succeeds as printed" "$([ $rc -eq 0 ] && echo 1 || echo 0)"
out=$(run_hook "$H6" "file://$SRC4" "")
check "ask: after approval the new rule loads" "$(has "$out" ADDED_BODY)"
check "ask: after approval no pending notice" "$([ "$(has "$out" 'awaiting the user')" = 0 ] && echo 1 || echo 0)"
printf 'docs only\n' > "$SRC4/README.md"
git -C "$SRC4" add -A && git -C "$SRC4" commit -qm readme
out=$(run_hook "$H6" "file://$SRC4" "")
check "ask: a change outside rules/ asks nothing" "$([ "$(has "$out" 'awaiting the user')" = 0 ] && echo 1 || echo 0)"
check "ask: a change outside rules/ advances the cache" "$([ "$(git -C "$H6/data/claude-rules" rev-parse HEAD)" = "$(git -C "$SRC4" rev-parse HEAD)" ] && echo 1 || echo 0)"
env -i HOME="$H6" PATH="$PATH" CLAUDE_PLUGIN_DATA="$H6/data" bash "$HOOK" approve 0000000000000000000000000000000000000000 >/dev/null 2>&1; rc=$?
check "ask: approving an unknown version fails" "$([ $rc -ne 0 ] && echo 1 || echo 0)"
env -i HOME="$H6" PATH="$PATH" CLAUDE_PLUGIN_DATA="$H6/data" bash "$HOOK" approve FETCH_HEAD >/dev/null 2>&1; rc=$?
check "ask: approve refuses a moving name like FETCH_HEAD" "$([ $rc -ne 0 ] && echo 1 || echo 0)"
printf 'x' > "$SRC4/rules/diagram.png"
git -C "$SRC4" add -A && git -C "$SRC4" commit -qm image
out=$(run_hook "$H6" "file://$SRC4" "")
check "ask: a non-.md file under rules/ asks nothing" "$([ "$(has "$out" 'awaiting the user')" = 0 ] && echo 1 || echo 0)"
printf '# Later\nLATER_BODY\n' > "$SRC4/rules/later.md"
git -C "$SRC4" add -A && git -C "$SRC4" commit -qm later
out=$(run_hook "$H6" "file://$SRC4" "sometimes")
check "unrecognised mode behaves as ask" "$([ "$(has "$out" LATER_BODY)" = 0 ] && [ "$(has "$out" 'awaiting the user')" = 1 ] && echo 1 || echo 0)"

# --- Without CLAUDE_PLUGIN_DATA (cache under ~/.cache), the printed approve command still works ---
SRC5="$TMP_DIR/src5"; mkdir -p "$SRC5/rules"
printf '# One\nONE_BODY\n' > "$SRC5/rules/one.md"
git -C "$SRC5" init -q && git -C "$SRC5" add -A && git -C "$SRC5" commit -qm init
H7="$TMP_DIR/h7"; mkdir -p "$H7"
nodata() { env -i HOME="$H7" PATH="$PATH" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
    CLAUDE_PLUGIN_OPTION_RULES_REPO="file://$SRC5" bash "$HOOK" </dev/null; }
nodata >/dev/null
printf '# Two\nTWO_BODY\n' > "$SRC5/rules/two.md"
git -C "$SRC5" add -A && git -C "$SRC5" commit -qm two
out=$(nodata)
approve=$(printf '%s\n' "$out" | grep -E '^ +CLAUDE_PLUGIN_DATA=.* approve ' | sed 's/^ *//')
env -i HOME="$H7" PATH="$PATH" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null bash -c "$approve" >/dev/null 2>&1; rc=$?
check "no plugin data dir: notice prints an approve command for the new version" "$(has "$approve" "approve $(git -C "$SRC5" rev-parse HEAD)")"
check "no plugin data dir: printed approve command works" "$([ $rc -eq 0 ] && echo 1 || echo 0)"
check "no plugin data dir: approved rule then loads" "$(has "$(nodata)" TWO_BODY)"

# --- A repo cloned while still empty loads its first rules once they are pushed ---
SRC9="$TMP_DIR/src9"; mkdir -p "$SRC9"; git -C "$SRC9" init -q
H19="$TMP_DIR/h19"; mkdir -p "$H19"
run_hook "$H19" "file://$SRC9" "" >/dev/null
mkdir -p "$SRC9/rules"; printf '# Early\nEARLY_BODY\n' > "$SRC9/rules/early.md"
git -C "$SRC9" add -A && git -C "$SRC9" commit -qm early
check "repo empty at first clone: its first rules load once pushed" "$(has "$(run_hook "$H19" "file://$SRC9" "")" EARLY_BODY)"

# --- A data path containing a quote still yields a working approve command ---
H8="$TMP_DIR/h8"; D8="$TMP_DIR/d a'ta"; mkdir -p "$H8"
quoted() { env -i HOME="$H8" PATH="$PATH" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
    CLAUDE_PLUGIN_DATA="$D8" CLAUDE_PLUGIN_OPTION_RULES_REPO="file://$SRC5" bash "$HOOK" </dev/null; }
quoted >/dev/null
printf '# Three\nTHREE_BODY\n' > "$SRC5/rules/three.md"
git -C "$SRC5" add -A && git -C "$SRC5" commit -qm three
approve=$(quoted | grep -E '^ +CLAUDE_PLUGIN_DATA=.* approve ' | sed 's/^ *//')
env -i HOME="$H8" PATH="$PATH" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null bash -c "$approve" >/dev/null 2>&1; rc=$?
want=$(git -C "$SRC5" rev-parse HEAD)
check "data path with a quote: notice prints an approve command for the new version" "$(has "$approve" "approve $want")"
check "data path with a quote: printed approve command works" "$([ $rc -eq 0 ] && echo 1 || echo 0)"
check "data path with a quote: the approved rule then loads" "$(has "$(quoted)" THREE_BODY)"

# --- Source unreachable, no cache: one-line notice, exit 0 ---
H2="$TMP_DIR/h2"; mkdir -p "$H2"
out=$(run_hook "$H2" "file://$TMP_DIR/missing"); rc=$?
check "offline with no cache exits 0" "$([ $rc -eq 0 ] && echo 1 || echo 0)"
check "offline with no cache says nothing was loaded" "$(has "$out" 'No shared rules loaded')"
check "failed clone leaves no half-made cache" "$([ ! -e "$H2/data/claude-rules" ] && echo 1 || echo 0)"

# --- Local install of the same repo present: silent, to avoid loading every rule twice ---
H3="$TMP_DIR/h3"; mkdir -p "$H3/.claude/rules"
git clone -q "file://$SRC" "$H3/.claude/rules/shared"
out=$(run_hook "$H3" "file://$SRC"); rc=$?
check "local install of the same repo: exits 0" "$([ $rc -eq 0 ] && echo 1 || echo 0)"
check "local install of the same repo: prints nothing" "$([ -z "$out" ] && echo 1 || echo 0)"
out=$(run_hook "$H3" "file://$SRC2")
check "local install of a different repo: configured repo still loads" "$(has "$out" OTHER_BODY)"

H4="$TMP_DIR/h4"; mkdir -p "$H4/.claude/rules"
git -C "$H3/.claude/rules/shared" worktree add -q --detach "$H4/.claude/rules/shared"
out=$(run_hook "$H4" "file://$SRC")
check "local install as a worktree (.git file): prints nothing" "$([ -z "$out" ] && echo 1 || echo 0)"

# --- No repo configured: the rules bundled in the plugin load, with no network ---
PLUG="$TMP_DIR/plug"; mkdir -p "$PLUG/hooks" "$PLUG/rules"
cp "$HOOK" "$PLUG/hooks/"
printf '# Bundled\nBUNDLED_BODY\n' > "$PLUG/rules/bundled.md"
H9="$TMP_DIR/h9"; mkdir -p "$H9"
bundled() { env -i HOME="$1" PATH="$PATH" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
    CLAUDE_PLUGIN_DATA="$1/data" bash "$PLUG/hooks/load-rules.sh" </dev/null; }
out=$(bundled "$H9"); rc=$?
check "bundled: exits 0" "$([ $rc -eq 0 ] && echo 1 || echo 0)"
check "bundled: plugin's own rules load" "$(has "$out" BUNDLED_BODY)"
check "bundled: source names the plugin" "$(has "$out" 'rules bundled with this plugin')"
check "bundled: nothing fetched or cached" "$([ ! -e "$H9/data/claude-rules" ] && echo 1 || echo 0)"
H10="$TMP_DIR/h10"; mkdir -p "$H10/.claude/rules"
git clone -q "file://$SRC" "$H10/.claude/rules/shared"
git -C "$H10/.claude/rules/shared" remote set-url origin https://github.com/bogheorghiu/claude-rules
check "bundled + local install of this repo: prints nothing" "$([ -z "$(bundled "$H10")" ] && echo 1 || echo 0)"

# --- Slicing: output over the 10,000-character hook limit is split across hooks ---
BIG="$TMP_DIR/big"; mkdir -p "$BIG/hooks" "$BIG/rules"
cp "$HOOK" "$BIG/hooks/"
for i in 1 2 3 4 5 6 7 8; do
    { printf '# Big rule %s\nBIGMARK_%s\n' "$i" "$i"; head -c 3000 /dev/zero | tr '\0' 'x'; echo; } > "$BIG/rules/big$i.md"
done
H11="$TMP_DIR/h11"; mkdir -p "$H11"
part() { # args: home, session id, part, parts
    printf '{"session_id":"%s","hook_event_name":"SessionStart"}' "$2" | \
    env -i HOME="$1" PATH="$PATH" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
        CLAUDE_PLUGIN_DATA="$1/data" bash "$BIG/hooks/load-rules.sh" part "$3" "$4"; }
all=""; maxlen=0
for k in 1 2 3 4 5 6; do
    o=$(part "$H11" sessA "$k" 6); all="$all$o"
    [ ${#o} -gt $maxlen ] && maxlen=${#o}
done
check "slicing: every slice under 10,000 characters (max ${maxlen})" "$([ $maxlen -le 10000 ] && echo 1 || echo 0)"
ok=1; for i in 1 2 3 4 5 6 7 8; do [ "$(printf '%s' "$all" | grep -c "BIGMARK_$i\$")" = 1 ] || ok=0; done
check "slicing: all slices together carry every rule exactly once" "$ok"
check "slicing: unused slices print nothing" "$([ -z "$(part "$H11" sessA 6 6)" ] && echo 1 || echo 0)"

# Parallel slices of one session render once and agree.
H12="$TMP_DIR/h12"; mkdir -p "$H12"
for k in 1 2 3 4 5 6; do part "$H12" sessB "$k" 6 > "$TMP_DIR/par$k.out" & done; wait
ok=1; for i in 1 2 3 4 5 6 7 8; do [ "$(cat "$TMP_DIR"/par*.out | grep -c "BIGMARK_$i\$")" = 1 ] || ok=0; done
check "slicing: six parallel slices still carry every rule exactly once" "$ok"

# Fewer hooks than slices: the last hook names the rules left out and where to read them.
o=$(part "$H11" sessA 2 2)
check "overflow: last hook says more rules did not fit" "$(has "$o" 'did not fit')"
check "overflow: says where to resume reading" "$(has "$o" 'from line')"
ln=$(printf '%s' "$o" | sed -n 's/.* from line \([0-9]*\) to the end.*/\1/p')
first_left=$(sed -n "${ln}p" "$H11/data/render-sessA.txt")
check "overflow: that line is where the first left-out slice begins" "$([ "$(has "$all" "$first_left")" = 0 ] || [ "$(has "$(part "$H11" sessA 1 2)$(part "$H11" sessA 2 2)" "$first_left")" = 0 ] && echo 1 || echo 0)"
check "overflow: points at the full render" "$(has "$o" "$H11/data/render-sessA.txt")"

# One render per session: a source change mid-start doesn't split versions across slices.
SRC6="$TMP_DIR/src6"; mkdir -p "$SRC6/rules"
{ echo '# Filler'; head -c 8950 /dev/zero | tr '\0' 'f'; echo; } > "$SRC6/rules/a-filler.md"
printf '# S6\nS6_BODY\n' > "$SRC6/rules/s6.md"
git -C "$SRC6" init -q && git -C "$SRC6" add -A && git -C "$SRC6" commit -qm init
H13="$TMP_DIR/h13"; mkdir -p "$H13"
fpart() { printf '{"session_id":"%s"}' "$2" | env -i HOME="$H13" PATH="$PATH" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
    CLAUDE_PLUGIN_DATA="$H13/data" CLAUDE_PLUGIN_OPTION_RULES_REPO="file://$SRC6" CLAUDE_PLUGIN_OPTION_UPDATE_MODE=auto \
    bash "$HOOK" part "$1" 2; }
fpart 1 sessC >/dev/null
printf '# S6b\nS6B_BODY\n' > "$SRC6/rules/s6b.md"
git -C "$SRC6" add -A && git -C "$SRC6" commit -qm more
o2=$(fpart 2 sessC)
check "one render per start: slice 2 prints from slice 1's version" "$([ "$(has "$o2" S6_BODY)" = 1 ] && [ "$(has "$o2" S6B_BODY)" = 0 ] && echo 1 || echo 0)"
check "a later start of the same session (compact, resume) renders afresh" "$(has "$(fpart 1 sessC)$(fpart 2 sessC)" S6B_BODY)"
check "a new session renders afresh" "$(has "$(fpart 1 sessD)$(fpart 2 sessD)" S6B_BODY)"

# --- Hostile sizes: many rules, one huge line ---
MANY="$TMP_DIR/many"; mkdir -p "$MANY/hooks" "$MANY/rules"; cp "$HOOK" "$MANY/hooks/"
for i in $(seq 1 200); do printf '# Rule %s with a fairly long title to pad the heading line\n%s\n' "$i" "$(head -c 300 /dev/zero | tr '\0' 'y')" > "$MANY/rules/a-rather-long-rule-file-name-number-$i.md"; done
H14="$TMP_DIR/h14"; mkdir -p "$H14"
mpart() { printf '{"session_id":"m"}' | env -i HOME="$H14" PATH="$PATH" CLAUDE_PLUGIN_DATA="$H14/data" bash "$MANY/hooks/load-rules.sh" part "$1" 6; }
mpart 1 >/dev/null; o=$(mpart 6)
check "200 rules: the last slice stays under 10,000 characters (${#o})" "$([ ${#o} -le 10000 ] && echo 1 || echo 0)"
check "200 rules: the last slice says the rest did not fit" "$(has "$o" 'did not fit')"
LONG="$TMP_DIR/long"; mkdir -p "$LONG/hooks" "$LONG/rules"; cp "$HOOK" "$LONG/hooks/"
{ echo '# Long'; head -c 25000 /dev/zero | tr '\0' 'z'; echo; } > "$LONG/rules/long.md"
H15="$TMP_DIR/h15"; mkdir -p "$H15"
lpart() { printf '{"session_id":"l"}' | env -i HOME="$H15" PATH="$PATH" CLAUDE_PLUGIN_DATA="$H15/data" bash "$LONG/hooks/load-rules.sh" part "$1" 6; }
lpart 1 >/dev/null; maxlen=0; total=0
for k in 1 2 3 4 5 6; do o=$(lpart $k); [ ${#o} -gt $maxlen ] && maxlen=${#o}; total=$((total + $(printf '%s' "$o" | tr -cd z | wc -c))); done
check "a 25,000-character line: every slice under 10,000 characters (max $maxlen)" "$([ $maxlen -le 10000 ] && echo 1 || echo 0)"
check "a 25,000-character line: all of it delivered across slices" "$([ $total -eq 25000 ] && echo 1 || echo 0)"

# --- Local install of the same repo under another spelling of its URL ---
for variant in "https://github.com/bogheorghiu/claude-rules.git" "https://github.com/bogheorghiu/claude-rules/" "git@github.com:bogheorghiu/claude-rules.git" "ssh://git@github.com/bogheorghiu/claude-rules.git" "https://github.com/BogHeorghiu/Claude-Rules"; do
    git -C "$H10/.claude/rules/shared" remote set-url origin "$variant"
    check "bundled + local install as $variant: prints nothing" "$([ -z "$(bundled "$H10")" ] && echo 1 || echo 0)"
done

# --- A cache folder left without .git doesn't swallow later clones ---
H16="$TMP_DIR/h16"; mkdir -p "$H16/data/claude-rules/junk"
check "leftover cache folder without .git: rules still load" "$(has "$(run_hook "$H16" "file://$SRC6")" '# Filler')"

# --- Ask mode from an approved version with no rules: the pending update still shows ---
SRC7="$TMP_DIR/src7"; mkdir -p "$SRC7"
printf 'readme only\n' > "$SRC7/README.md"
git -C "$SRC7" init -q && git -C "$SRC7" add -A && git -C "$SRC7" commit -qm init
H17="$TMP_DIR/h17"; mkdir -p "$H17"
run_hook "$H17" "file://$SRC7" "" >/dev/null
mkdir -p "$SRC7/rules"; printf '# First\nFIRST_BODY\n' > "$SRC7/rules/first.md"
git -C "$SRC7" add -A && git -C "$SRC7" commit -qm first
o=$(run_hook "$H17" "file://$SRC7" "")
check "ask from an empty approved version: pending update is shown" "$(has "$o" 'awaiting the user')"
check "ask from an empty approved version: no 'has no .md files' claim" "$([ "$(has "$o" 'has no .md files')" = 0 ] && echo 1 || echo 0)"

# --- Unreachable source, cached copy without rules: blame the refresh, not the repo ---
mv "$SRC3" "$SRC3.gone"
o=$(run_hook "$H5" "file://$SRC3")
mv "$SRC3.gone" "$SRC3"
check "unreachable source, empty cache: says the refresh failed" "$(has "$o" 'could not refresh')"

# --- Mode is case-insensitive ---
printf '# Second\nSECOND_BODY\n' > "$SRC7/rules/second.md"
git -C "$SRC7" add -A && git -C "$SRC7" commit -qm second
check "update mode 'Auto' counts as auto" "$(has "$(run_hook "$H17" "file://$SRC7" "Auto")" SECOND_BODY)"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
