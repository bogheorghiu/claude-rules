#!/bin/bash
# Tests for sync-rules.sh. Each fixture is a copy of the plugin at some version, so a
# "plugin update" is running a newer copy against the same HOME.
#
# What they do NOT prove: that Claude Code loads ~/.claude/rules natively, or when.
# That was observed live (tests/live/) and is recorded in docs/DESIGN-managed-rules.md.

set -u

HOOK="$(cd "$(dirname "$0")" && pwd)/sync-rules.sh"
PLUGIN="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

pass=0
fail=0
check() {
    if [ "$2" = "1" ]; then echo "  ok   - $1"; pass=$((pass + 1))
    else echo "  FAIL - $1"; fail=$((fail + 1)); fi
}
has() { case "$1" in *"$2"*) echo 1 ;; *) echo 0 ;; esac; }
sha() { sha256sum "$1" | cut -d' ' -f1; }

# make_plugin DIR VERSION: a plugin copy at VERSION with rules from stdin as
# "name|body" lines. Its history holds its own rules plus any listed in $HIST_FROM.
make_plugin() {
    local d="$1" v="$2" name body
    mkdir -p "$d/hooks" "$d/rules" "$d/.claude-plugin"
    cp "$HOOK" "$d/hooks/sync-rules.sh"
    printf '{\n  "name": "shared-rules",\n  "version": "%s"\n}\n' "$v" > "$d/.claude-plugin/plugin.json"
    while IFS='|' read -r name body; do mkdir -p "$d/rules/$(dirname "$name")"; printf '%b' "$body" > "$d/rules/$name"; done
    { for p in ${HIST_FROM:-} "$d"; do (cd "$p/rules" && find . -type f | while read -r f; do sha "$f"; done); done; } | sort -u > "$d/rules-history.txt"
}
# run PLUGIN HOME [args...]: one session start (or one command) of that plugin version.
run() { local p="$1" h="$2"; shift 2
    printf '{"session_id":"s%s"}' "$RANDOM$RANDOM" | env -i HOME="$h" PATH="$PATH" CLAUDE_PLUGIN_DATA="$h/data" bash "$p/hooks/sync-rules.sh" "$@"; }
start() { run "$1" "$2" part 1 1; }
T() { echo "$1/.claude/rules/shared-rules"; }
same_tree() { diff -r -x .shared-rules.manifest "$1" "$2" >/dev/null 2>&1 && echo 1 || echo 0; }

echo "Testing sync-rules.sh"
echo "====================="

V1="$TMP_DIR/v1"; make_plugin "$V1" 0.1.0 <<'EOF'
keep.md|# Keep\nKEEP_V1\n
change.md|# Change\nCHANGE_V1\n
drop.md|# Drop\nDROP_V1\n
EOF
HIST_FROM="$V1" make_plugin "$TMP_DIR/v2" 0.2.0 <<'EOF'
keep.md|# Keep\nKEEP_V1\n
change.md|# Change\nCHANGE_V2\n
new.md|# New\nNEW_V2\n
EOF
V2="$TMP_DIR/v2"

# --- First install ---
A="$TMP_DIR/a"; mkdir -p "$A"
o=$(start "$V1" "$A"); rc=$?
check "first install: exits 0" "$([ $rc -eq 0 ] && echo 1 || echo 0)"
check "first install: prints the rules for this session" "$([ "$(has "$o" KEEP_V1)" = 1 ] && [ "$(has "$o" DROP_V1)" = 1 ] && echo 1 || echo 0)"
check "first install: says they load natively from the next session" "$(has "$o" 'from the next session')"
check "first install: folder holds exactly the bundled rules" "$(same_tree "$(T "$A")" "$V1/rules")"
check "first install: folder carries the plugin's manifest" "$([ -f "$(T "$A")/.shared-rules.manifest" ] && echo 1 || echo 0)"
check "same version, next session: prints nothing (Claude Code loads the folder itself)" "$([ -z "$(start "$V1" "$A")" ] && echo 1 || echo 0)"

# --- Update, folder untouched by the user: applied silently ---
o=$(start "$V2" "$A")
check "untouched update: folder now matches the new version exactly" "$(same_tree "$(T "$A")" "$V2/rules")"
check "untouched update: prints the changed and new rules" "$([ "$(has "$o" CHANGE_V2)" = 1 ] && [ "$(has "$o" NEW_V2)" = 1 ] && echo 1 || echo 0)"
check "untouched update: does not reprint unchanged rules" "$([ "$(has "$o" KEEP_V1)" = 0 ] && echo 1 || echo 0)"
check "untouched update: names the removed rule as no longer in force" "$([ "$(has "$o" 'No longer in force')" = 1 ] && [ "$(has "$o" drop.md)" = 1 ] && echo 1 || echo 0)"
check "untouched update: asks nothing" "$([ "$(has "$o" "user's decision")" = 0 ] && echo 1 || echo 0)"
check "after the update: next session prints nothing" "$([ -z "$(start "$V2" "$A")" ] && echo 1 || echo 0)"

# --- A file restored to an older shipped version still counts as the plugin's own ---
B="$TMP_DIR/b"; mkdir -p "$B"; start "$V1" "$B" >/dev/null
HIST_FROM="$V1 $V2" make_plugin "$TMP_DIR/v1b" 0.1.1 < <(printf 'keep.md|# Keep\\nKEEP_V1\\n\nchange.md|# Change\\nCHANGE_V1\\n\ndrop.md|# Drop\\nDROP_V1\\n\n')
cp "$V2/rules/change.md" "$(T "$B")/change.md"     # the user pasted in the v2 text
o=$(start "$TMP_DIR/v1b" "$B")
check "content matching any shipped version: treated as untouched, update applies" "$([ "$(has "$o" "user's decision")" = 0 ] && [ "$(same_tree "$(T "$B")" "$TMP_DIR/v1b/rules")" = 1 ] && echo 1 || echo 0)"

# --- Update, user changed the folder: nothing replaced, Claude asks ---
HIST_FROM="$V1 $V2" make_plugin "$TMP_DIR/v3" 0.3.0 <<'EOF'
keep.md|# Keep\nKEEP_V3\n
change.md|# Change\nCHANGE_V3\n
EOF
V3="$TMP_DIR/v3"
printf '# Change\nMY_EDIT\n' > "$(T "$A")/change.md"
printf '# Mine\nMY_RULE\n' > "$(T "$A")/mine.md"
rm "$(T "$A")/new.md"
snap="$TMP_DIR/snap"; cp -r "$(T "$A")" "$snap"
o=$(start "$V3" "$A")
check "user changes: folder left exactly as it was" "$(diff -r "$snap" "$(T "$A")" >/dev/null && echo 1 || echo 0)"
check "user changes: asks for the user's decision" "$(has "$o" "rule update waiting for the user's decision")"
check "user changes: lists the edited file" "$(has "$o" 'edited change.md')"
check "user changes: lists the added file" "$(has "$o" 'added mine.md')"
check "user changes: lists the deleted file" "$(has "$o" 'deleted new.md')"
check "user changes: offers apply for this exact version" "$(has "$o" 'apply 0.3.0')"
check "user changes: offers keep, and says it declines the rule changes entirely" "$([ "$(has "$o" 'keep 0.3.0')" = 1 ] && [ "$(has "$o" 'declines version 0.3.0')" = 1 ] && [ "$(has "$o" 'rest of the plugin update still applies')" = 1 ] && echo 1 || echo 0)"
check "user changes: asks again next session until decided" "$(has "$(start "$V3" "$A")" "user's decision")"
# The printed commands work exactly as printed.
keep_cmd=$(printf '%s\n' "$o" | grep -E '^ +CLAUDE_PLUGIN_DATA=.* keep 0\.3\.0$' | sed 's/^ *//')
apply_cmd=$(printf '%s\n' "$o" | grep -E '^ +CLAUDE_PLUGIN_DATA=.* apply 0\.3\.0' | sed 's/^ *//; s/ \[backup-folder\]$//')
check "user changes: notice prints both commands" "$([ -n "$keep_cmd" ] && [ -n "$apply_cmd" ] && echo 1 || echo 0)"

# keep: folder untouched, silent for this version, asked again at the next one
env -i HOME="$A" PATH="$PATH" bash -c "$keep_cmd" >/dev/null 2>&1; rc=$?
check "keep: the printed command works" "$([ $rc -eq 0 ] && echo 1 || echo 0)"
check "keep: folder still untouched" "$(diff -r "$snap" "$(T "$A")" >/dev/null && echo 1 || echo 0)"
check "keep: this version stops asking" "$([ -z "$(start "$V3" "$A")" ] && echo 1 || echo 0)"
HIST_FROM="$V1 $V2 $V3" make_plugin "$TMP_DIR/v4" 0.4.0 <<'EOF'
keep.md|# Keep\nKEEP_V4\n
EOF
V4="$TMP_DIR/v4"
o=$(start "$V4" "$A")
check "keep: the next version asks again" "$(has "$o" "user's decision")"
check "apply: refuses a version that isn't the installed one" "$(run "$V4" "$A" apply 0.3.0 >/dev/null 2>&1; [ $? -ne 0 ] && echo 1 || echo 0)"

# apply: the user's edits and additions move to the backup, the version installs exactly
BK="$TMP_DIR/my backup"
run "$V4" "$A" apply 0.4.0 "$BK" >/dev/null 2>&1; rc=$?
check "apply: exits 0" "$([ $rc -eq 0 ] && echo 1 || echo 0)"
check "apply: folder now matches the version exactly" "$(same_tree "$(T "$A")" "$V4/rules")"
check "apply: the edited file is in the backup" "$(has "$(cat "$BK/change.md" 2>/dev/null)" MY_EDIT)"
check "apply: the added file is in the backup" "$(has "$(cat "$BK/mine.md" 2>/dev/null)" MY_RULE)"
check "apply: the plugin's own untouched files are not backed up" "$([ ! -e "$BK/keep.md" ] && echo 1 || echo 0)"
check "apply: next session prints nothing" "$([ -z "$(start "$V4" "$A")" ] && echo 1 || echo 0)"

# Default backup: outside ~/.claude/rules (so it never loads) and not in /tmp.
C="$TMP_DIR/c"; mkdir -p "$C"; start "$V1" "$C" >/dev/null
printf 'x\n' >> "$(T "$C")/keep.md"
o=$(start "$V2" "$C"); cmd=$(printf '%s\n' "$o" | grep -E '^ +CLAUDE_PLUGIN_DATA=.* apply 0\.2\.0' | sed 's/^ *//; s/ \[backup-folder\]$//')
env -i HOME="$C" PATH="$PATH" bash -c "$cmd" >/dev/null 2>&1
bk=$(find "$C/.claude/shared-rules-backups" -name keep.md 2>/dev/null | head -1)
check "apply, default backup: lands under ~/.claude/shared-rules-backups/" "$([ -n "$bk" ] && echo 1 || echo 0)"
check "apply, default backup: nothing backed up under ~/.claude/rules" "$([ -z "$(find "$C/.claude/rules" -path '*backup*' 2>/dev/null)" ] && echo 1 || echo 0)"

# --- First install finds a folder of that name it didn't make ---
D="$TMP_DIR/d"; mkdir -p "$D/.claude/rules/shared-rules"; printf '# Theirs\nTHEIRS\n' > "$D/.claude/rules/shared-rules/theirs.md"
o=$(start "$V1" "$D")
check "foreign folder: left untouched" "$([ "$(ls "$(T "$D")")" = theirs.md ] && echo 1 || echo 0)"
check "foreign folder: asks where to install" "$([ "$(has "$o" 'choose here')" = 1 ] && [ "$(has "$o" 'choose elsewhere')" = 1 ] && echo 1 || echo 0)"
check "foreign folder: this session still gets the rules" "$(has "$o" KEEP_V1)"
E="$TMP_DIR/e"; cp -r "$D" "$E"
run "$V1" "$D" choose here "$D/bk" >/dev/null 2>&1
check "choose here: the existing content moves to the backup" "$(has "$(cat "$D/bk/theirs.md" 2>/dev/null)" THEIRS)"
check "choose here: the plugin installs there" "$(same_tree "$(T "$D")" "$V1/rules")"
check "choose here: next session prints nothing" "$([ -z "$(start "$V1" "$D")" ] && echo 1 || echo 0)"
run "$V1" "$E" choose elsewhere >/dev/null 2>&1
check "choose elsewhere: installs into shared-rules-plugin" "$(same_tree "$E/.claude/rules/shared-rules-plugin" "$V1/rules")"
check "choose elsewhere: the user's folder is untouched" "$([ "$(ls "$(T "$E")")" = theirs.md ] && echo 1 || echo 0)"
check "choose elsewhere: remembered, next session prints nothing" "$([ -z "$(start "$V1" "$E")" ] && echo 1 || echo 0)"
o=$(start "$V2" "$E")
check "choose elsewhere: later updates go there" "$(same_tree "$E/.claude/rules/shared-rules-plugin" "$V2/rules")"
F="$TMP_DIR/f"; mkdir -p "$F/.claude/rules/shared-rules" "$F/.claude/rules/shared-rules-plugin"; touch "$F/.claude/rules/shared-rules-plugin/x.md"
check "choose elsewhere: refuses when that folder is someone else's too" "$(run "$V1" "$F" choose elsewhere >/dev/null 2>&1; [ $? -ne 0 ] && echo 1 || echo 0)"

# --- Replaced by the user's own rule set (the custom-repo add-on's choice) ---
G="$TMP_DIR/g"; mkdir -p "$G/.claude/rules"; touch "$G/.claude/rules/.shared-rules-replaced"
check "replaced: prints nothing" "$([ -z "$(start "$V1" "$G")" ] && echo 1 || echo 0)"
check "replaced: installs nothing" "$([ ! -e "$(T "$G")" ] && echo 1 || echo 0)"

# --- A later start of the installing session (/compact, resume) prints the rules again ---
K="$TMP_DIR/k"; mkdir -p "$K"
ks() { printf '{"session_id":"%s"}' "$2" | env -i HOME="$K" PATH="$PATH" CLAUDE_PLUGIN_DATA="$K/data" bash "$1/hooks/sync-rules.sh" part 1 1; }
ks "$V1" sessK >/dev/null
check "compact/resume of the installing session: rules printed again" "$(has "$(ks "$V1" sessK)" KEEP_V1)"
check "a new session after it: prints nothing" "$([ -z "$(ks "$V1" sessL)" ] && echo 1 || echo 0)"
ks "$V2" sessM >/dev/null
o=$(ks "$V2" sessM)
check "compact/resume of an updating session: only the changed rules printed again" "$([ "$(has "$o" CHANGE_V2)" = 1 ] && [ "$(has "$o" KEEP_V1)" = 0 ] && echo 1 || echo 0)"

# --- Rule formats ---
make_plugin "$TMP_DIR/fmt" 0.1.0 <<'EOF'
always.md|# Always\nALWAYS_BODY\n
scoped.md|---\npaths:\n  - "src/**"\n---\n# Scoped\nSCOPED_BODY\n
crlf.md|---\r\npaths:\r\n  - "x/**"\r\n---\r\n# Crlf\r\nCRLF_BODY\r\n
unclosed.md|---\n# Dashes, no frontmatter\npaths: in prose\nUNCLOSED_BODY\n
sub/nested.md|# Nested\nNESTED_BODY\n
EOF
H="$TMP_DIR/h"; mkdir -p "$H"; o=$(start "$TMP_DIR/fmt" "$H")
check "always-on rule printed" "$(has "$o" ALWAYS_BODY)"
check "path-scoped rule listed, body not printed" "$([ "$(has "$o" scoped.md)" = 1 ] && [ "$(has "$o" SCOPED_BODY)" = 0 ] && echo 1 || echo 0)"
check "CRLF frontmatter still recognised as path-scoped" "$([ "$(has "$o" CRLF_BODY)" = 0 ] && echo 1 || echo 0)"
check "unclosed frontmatter: rule printed in full" "$(has "$o" UNCLOSED_BODY)"
check "rules in subfolders installed and printed" "$([ -f "$(T "$H")/sub/nested.md" ] && [ "$(has "$o" NESTED_BODY)" = 1 ] && echo 1 || echo 0)"

# --- Slicing: output over the 10,000-character hook limit is split across hooks ---
BIG="$TMP_DIR/big"; make_plugin "$BIG" 0.1.0 < <(for i in 1 2 3 4 5 6 7 8; do printf 'big%s.md|# Big rule %s\\nBIGMARK_%s\\n%s\\n\n' "$i" "$i" "$i" "$(head -c 3000 /dev/zero | tr '\0' 'x')"; done)
part() { printf '{"session_id":"%s"}' "$2" | env -i HOME="$1" PATH="$PATH" CLAUDE_PLUGIN_DATA="$1/data" bash "$BIG/hooks/sync-rules.sh" part "$3" "$4"; }
H11="$TMP_DIR/h11"; mkdir -p "$H11"; all=""; maxlen=0
for k in 1 2 3 4 5 6; do o=$(part "$H11" sessA "$k" 6); all="$all$o"; [ ${#o} -gt $maxlen ] && maxlen=${#o}; done
check "slicing: every slice under 10,000 characters (max ${maxlen})" "$([ $maxlen -le 10000 ] && echo 1 || echo 0)"
ok=1; for i in 1 2 3 4 5 6 7 8; do [ "$(printf '%s' "$all" | grep -c "BIGMARK_$i\$")" = 1 ] || ok=0; done
check "slicing: all slices together carry every rule exactly once" "$ok"
check "slicing: unused slices print nothing" "$([ -z "$(part "$H11" sessA 6 6)" ] && echo 1 || echo 0)"
H12="$TMP_DIR/h12"; mkdir -p "$H12"
for k in 1 2 3 4 5 6; do part "$H12" sessB "$k" 6 > "$TMP_DIR/par$k.out" & done; wait
ok=1; for i in 1 2 3 4 5 6 7 8; do [ "$(cat "$TMP_DIR"/par*.out | grep -c "BIGMARK_$i\$")" = 1 ] || ok=0; done
check "slicing: six parallel slices still carry every rule exactly once" "$ok"
# A silent session must not keep the other slices waiting out their timeout.
t0=$(date +%s); part "$H12" sessQ 1 6 >/dev/null; part "$H12" sessQ 2 6 >/dev/null
check "silent session: other slices return at once" "$([ $(( $(date +%s) - t0 )) -lt 5 ] && echo 1 || echo 0)"
H13="$TMP_DIR/h13"; mkdir -p "$H13"; o1=$(part "$H13" sessO 1 2); o=$(part "$H13" sessO 2 2)
check "overflow: last hook says more rules did not fit, and where to read" "$([ "$(has "$o" 'did not fit')" = 1 ] && [ "$(has "$o" "$H13/data/render-sessO.txt")" = 1 ] && echo 1 || echo 0)"
ln=$(printf '%s' "$o" | sed -n 's/.* from line \([0-9]*\) to the end.*/\1/p')
two="$o1$o"
first_left=$(sed -n "${ln:-0}p" "$H13/data/render-sessO.txt" 2>/dev/null)
last_in=$(head -n "$(( ${ln:-1} - 1 ))" "$H13/data/render-sessO.txt" | grep '^=== ' | tail -1)
check "overflow: that line is where the first left-out rule begins" "$([ -n "$ln" ] && [ -n "$last_in" ] && case "$first_left" in "=== "*) true ;; *) false ;; esac && [ "$(has "$two" "$first_left")" = 0 ] && [ "$(has "$two" "$last_in")" = 1 ] && echo 1 || echo 0)"
UTF="$TMP_DIR/utf"; make_plugin "$UTF" 0.1.0 < <(printf 'dashes.md|# Dashes\\nx%s\\n\n' "$(for _ in $(seq 1 8000); do printf '\342\200\224'; done)")
H14="$TMP_DIR/h14"; mkdir -p "$H14"
upart() { printf '{"session_id":"u"}' | env -i HOME="$H14" PATH="$PATH" LANG=C.UTF-8 CLAUDE_PLUGIN_DATA="$H14/data" bash "$UTF/hooks/sync-rules.sh" part "$1" 6; }
ok=1; dashes=0
for k in 1 2 3 4 5 6; do o=$(upart $k); printf '%s' "$o" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1 || ok=0; dashes=$((dashes + $(printf '%s' "$o" | grep -o $'\xe2\x80\x94' | wc -l))); done
check "a long line of multi-byte characters: every slice is valid UTF-8" "$ok"
check "a long line of multi-byte characters: all of it delivered ($dashes of 8000)" "$([ $dashes -eq 8000 ] && echo 1 || echo 0)"

# --- Release guard: every bundled rule is in the history the next version will check ---
ok=1; for f in "$PLUGIN"/rules/*.md; do grep -qx "$(sha "$f")" "$PLUGIN/rules-history.txt" || ok=0; done
check "release: every bundled rule's hash is in rules-history.txt" "$ok"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
