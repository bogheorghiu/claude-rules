#!/bin/bash
# Tests for local-update.sh against a fixture repo cloned the way the README's local
# install does it (sparse: rules/ plus this script), served over file://.

set -u

HOOK="$(cd "$(dirname "$0")" && pwd)/local-update.sh"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

pass=0; fail=0
check() { if [ "$2" = "1" ]; then echo "  ok   - $1"; pass=$((pass + 1)); else echo "  FAIL - $1"; fail=$((fail + 1)); fi; }
has() { case "$1" in *"$2"*) echo 1 ;; *) echo 0 ;; esac; }

SRC="$TMP_DIR/src"; mkdir -p "$SRC/rules" "$SRC/hooks"
printf '# One\nONE\n' > "$SRC/rules/one.md"
printf 'readme\n' > "$SRC/README.md"
cp "$HOOK" "$SRC/hooks/local-update.sh"
git -C "$SRC" init -q && git -C "$SRC" add -A && git -C "$SRC" commit -qm init

install() { # $1 = HOME: the README's sparse local install
    git clone -q --filter=blob:none --no-checkout "file://$SRC" "$1/.claude/rules/shared" 2>/dev/null
    git -C "$1/.claude/rules/shared" sparse-checkout set --no-cone '/rules/' '/hooks/local-update.sh'
    git -C "$1/.claude/rules/shared" checkout -q
}
run() { env -i HOME="$1" PATH="$PATH" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
    bash "$1/.claude/rules/shared/hooks/local-update.sh" ${2:+"$2"} </dev/null; }
commit() { git -C "$SRC" add -A && git -C "$SRC" commit -qm "$1"; }

echo "Testing local-update.sh"
echo "======================="

A="$TMP_DIR/a"; mkdir -p "$A"; install "$A"
check "sparse install has the rules and the script only" "$([ -f "$A/.claude/rules/shared/rules/one.md" ] && [ -f "$A/.claude/rules/shared/hooks/local-update.sh" ] && [ ! -e "$A/.claude/rules/shared/README.md" ] && echo 1 || echo 0)"
out=$(run "$A"); rc=$?
check "nothing new: silent, exit 0" "$([ -z "$out" ] && [ $rc -eq 0 ] && echo 1 || echo 0)"

printf '# Two\nTWO\n' > "$SRC/rules/two.md"; commit two; want=$(git -C "$SRC" rev-parse HEAD)
out=$(run "$A")
check "ask (default): new rule not applied" "$([ ! -e "$A/.claude/rules/shared/rules/two.md" ] && echo 1 || echo 0)"
check "ask: notice names the new version" "$(has "$out" "newer version $want")"
check "ask: notice lists the changed file" "$(has "$out" 'rules/two.md')"
approve=$(printf '%s\n' "$out" | grep -E '^ +git -C .* reset -q --hard ' | sed 's/^ *//')
env -i HOME="$A" PATH="$PATH" GIT_CONFIG_GLOBAL=/dev/null bash -c "$approve" >/dev/null 2>&1
check "ask: the printed approve command applies it" "$([ -f "$A/.claude/rules/shared/rules/two.md" ] && echo 1 || echo 0)"
check "ask: the install stays sparse after approval" "$([ ! -e "$A/.claude/rules/shared/README.md" ] && echo 1 || echo 0)"

printf 'readme 2\n' > "$SRC/README.md"; commit readme
out=$(run "$A")
check "a change outside rules/ applies silently" "$([ -z "$out" ] && [ "$(git -C "$A/.claude/rules/shared" rev-parse HEAD)" = "$(git -C "$SRC" rev-parse HEAD)" ] && echo 1 || echo 0)"

printf '# Three\nTHREE\n' > "$SRC/rules/three.md"; commit three
out=$(run "$A" Auto)
check "auto: new rule applied at once" "$([ -f "$A/.claude/rules/shared/rules/three.md" ] && echo 1 || echo 0)"
check "auto: silent" "$([ -z "$out" ] && echo 1 || echo 0)"

mv "$SRC" "$SRC.gone"; out=$(run "$A"); rc=$?; mv "$SRC.gone" "$SRC"
check "offline: silent, exit 0, rules kept" "$([ -z "$out" ] && [ $rc -eq 0 ] && [ -f "$A/.claude/rules/shared/rules/three.md" ] && echo 1 || echo 0)"

B="$TMP_DIR/b"; mkdir -p "$B"
out=$(env -i HOME="$B" PATH="$PATH" bash "$HOOK" </dev/null); rc=$?
check "no local install: silent, exit 0" "$([ -z "$out" ] && [ $rc -eq 0 ] && echo 1 || echo 0)"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
