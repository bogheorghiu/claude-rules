#!/bin/bash
# SessionStart hook: print the shared Claude rules into context, for sessions that
# have no ~/.claude/rules of their own (cloud sessions, fresh containers).
#
# Must never block or fail the session: every failure falls through to exit 0.

# Settings come from the plugin's userConfig (plugin.json), which Claude Code exports
# to hooks as CLAUDE_PLUGIN_OPTION_<KEY>.
REPO_URL="${CLAUDE_PLUGIN_OPTION_RULES_REPO:-}"
# Anything but "auto" means ask: an unrecognised value must fail toward consent.
MODE=ask; [ "${CLAUDE_PLUGIN_OPTION_UPDATE_MODE:-}" = auto ] && MODE=auto
CACHE="${CLAUDE_PLUGIN_DATA:-$HOME/.cache/shared-rules}/claude-rules"
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# `load-rules.sh approve <sha>`: the user said yes to a pending update. Takes the sha
# the notice showed, not "latest", so a push landing after the notice can't ride
# along on an approval given for something else.
if [ "${1:-}" = approve ]; then
    # A full sha only: names like FETCH_HEAD move, and would let a later push ride along.
    if [[ "${2:-}" =~ ^[0-9a-f]{40}$ ]] && git -C "$CACHE" reset -q --hard "$2" 2>/dev/null; then
        echo "[shared-rules] Approved $2; these rules load from the next session on."
        exit 0
    fi
    echo "[shared-rules] Could not approve '${2:-}': not a version fetched into $CACHE." >&2
    exit 1
fi

# A local install of the same repo already makes Claude Code load these rules
# natively; printing them again would put every rule in context twice. (-e, not -d:
# a submodule or worktree checkout has a .git *file*.) Bundled rules are this repo's.
# URLs compare after normalising the spellings of one repo: .git, a trailing /, SSH.
norm() { local u="${1%/}"; u="${u%.git}"; case "$u" in git@*:*) u="${u#git@}"; u="https://${u/://}" ;; esac; echo "$u"; }
LOCAL="$HOME/.claude/rules/shared"
if [ -e "$LOCAL/.git" ] && [ "$(norm "$(git -C "$LOCAL" remote get-url origin 2>/dev/null)")" = \
     "$(norm "${REPO_URL:-https://github.com/bogheorghiu/claude-rules}")" ]; then
    exit 0
fi

# A private or mistyped URL must fail, not wait at a credential prompt; a stalled
# transfer must end even where `timeout` is absent (stock macOS).
export GIT_TERMINAL_PROMPT=0
git_net() {
    local t=()
    command -v timeout >/dev/null 2>&1 && t=(timeout 15)
    "${t[@]}" git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=10 "$@" >/dev/null 2>&1
}

SOURCE_LABEL="${REPO_URL:-rules bundled with this plugin}"
render() {
    stale=""
    pending=""
    if [ -z "$REPO_URL" ]; then
        # No repo configured: load the rules shipped inside this plugin version, so the
        # default set only ever changes through a plugin release. No network.
        RULES_DIR="$ROOT/rules"
    else
        RULES_DIR="$CACHE/rules"
        # A cache cloned from a different URL (the rules_repo setting changed) is not this repo.
        if [ -d "$CACHE/.git" ] && [ "$(git -C "$CACHE" remote get-url origin 2>/dev/null)" != "$REPO_URL" ]; then
            rm -rf "$CACHE"
        fi

        if [ -d "$CACHE/.git" ]; then
            # fetch + reset rather than pull: a force-pushed upstream would make
            # `pull --ff-only` fail on every session and freeze the cache for good.
            # The cache's checkout is the approved version; in ask mode a newer fetch waits.
            if ! git_net -C "$CACHE" fetch --depth 1 -q origin HEAD; then
                stale=1
            elif [ "$(git -C "$CACHE" rev-parse FETCH_HEAD)" != "$(git -C "$CACHE" rev-parse HEAD)" ]; then
                # Nothing to ask about when no loaded rule changed (a README edit, say). A
                # failed diff must not read as "no change": ask mode fails toward consent.
                if ! changed=$(git -C "$CACHE" diff --name-only HEAD FETCH_HEAD -- 'rules/*.md' 2>/dev/null); then
                    stale=1
                elif [ "$MODE" = auto ] || [ -z "$changed" ]; then
                    git -C "$CACHE" reset -q --hard FETCH_HEAD >/dev/null 2>&1 || stale=1
                else
                    pending=$(git -C "$CACHE" rev-parse FETCH_HEAD)
                fi
            fi
        else
            # A first clone is loaded in either mode: installing the plugin is consent to
            # the rules it points at today; ask mode governs what changes after that.
            # Clone beside the cache and move it in only when complete, so a clone killed
            # mid-way can never leave a half-made .git that every later session trips on.
            mkdir -p "$(dirname "$CACHE")" 2>/dev/null
            tmp="$CACHE.tmp.$$"
            if git_net clone --depth 1 -q "$REPO_URL" "$tmp"; then
                rm -rf "$CACHE"   # a leftover without .git would swallow the clone
                mv "$tmp" "$CACHE"
            fi
            rm -rf "$tmp"
        fi
    fi

    # Rules may sit in subfolders of rules/, as Claude Code allows locally. `find`, not
    # globstar: macOS ships bash 3.2, where ** silently means * and top-level rules vanish.
    files=()
    while IFS= read -r f; do files+=("$f"); done < <(find "$RULES_DIR" -type f -name '*.md' 2>/dev/null | LC_ALL=C sort)
    if [ ${#files[@]} -eq 0 ]; then
        # Silence would read the same as "there are no rules"; say which it is.
        if [ -z "$REPO_URL" ]; then
            echo "[shared-rules] No shared rules loaded this session: this plugin version ships no rules."
        elif [ -d "$CACHE/.git" ]; then
            echo "[shared-rules] No shared rules loaded this session: $REPO_URL was fetched but has no .md files under rules/."
        else
            echo "[shared-rules] No shared rules loaded this session: could not fetch $REPO_URL and nothing is cached."
        fi
        exit 0
    fi

    # The \r strip matters: a rule committed from Windows has CRLF endings, its
    # '---\r' would never match the delimiter, and a path-scoped rule would load in full.
    frontmatter() {
        awk '{sub(/\r$/, "")} NR==1 && $0!="---" {exit} NR>1 && $0=="---" {exit} NR>1 {print}' "$1"
    }

    scoped=()
    [ -n "$stale" ] && echo "Could not refresh from the source this session; these are the last cached copies and may be out of date."
    if [ -n "$pending" ]; then
        echo
        echo "=== rule updates awaiting the user's approval ==="
        echo "Update mode is 'ask'. The rules below are the approved version $(git -C "$CACHE" rev-parse --short HEAD)."
        echo "The source has a newer version $pending changing:"
        git -C "$CACHE" diff --name-status HEAD "$pending" -- 'rules/*.md' | sed 's/^/    /'
        echo "Tell the user about this pending update before other work. To show them the changes:"
        echo "    git -C $(printf %q "$CACHE") diff HEAD $pending -- 'rules/*.md'"
        echo "Only if the user explicitly approves, run:"
        echo "    CLAUDE_PLUGIN_DATA=$(printf %q "${CLAUDE_PLUGIN_DATA:-}") bash $(printf %q "$SELF") approve $pending"
    fi
    for f in "${files[@]}"; do
        if frontmatter "$f" | grep -q '^paths:'; then
            scoped+=("$f")
            continue
        fi
        echo
        echo "=== rule: ${f#"$RULES_DIR/"} ==="
        cat "$f"
    done

    if [ ${#scoped[@]} -gt 0 ]; then
        echo
        echo "=== path-scoped rules ==="
        echo "Not loaded here. Before working on files matching a rule's paths, read that rule's file."
        for f in "${scoped[@]}"; do
            echo
            echo "- $f"
            frontmatter "$f" | sed 's/^/    /'
        done
    fi
}

# Claude Code passes a hook at most 10,000 characters of output; beyond that the model
# sees only a 2,000-character preview. The limit is per hook, so hooks.json registers
# several and each prints one slice: `load-rules.sh part K N`.
PART="${2:-1}"; PARTS="${3:-1}"
[ "${1:-}" = part ] || { PART=1; PARTS=1; }
LIMIT=9000   # under 10,000, leaving room for the wrapper lines

# Render once per session start, so every slice comes from the same version. Only
# slice 1 fetches and renders; the others wait for its render, so no two slices ever
# touch the cache at once. A render counts only if it began within this start (a
# later /compact or resume fires SessionStart again with the same session id).
OUT="${CLAUDE_PLUGIN_DATA:-$HOME/.cache/shared-rules}"
mkdir -p "$OUT" 2>/dev/null
started=$(date +%s)
sid=$(sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([A-Za-z0-9_-]*\)".*/\1/p' 2>/dev/null | head -1)
RENDER="$OUT/render-${sid:-$$}.txt"
find "$OUT" -maxdepth 1 -name 'render-*' -mtime +1 -exec rm -f {} + 2>/dev/null
if [ "$PART" = 1 ]; then
    ( render ) > "$RENDER.tmp.$$" 2>/dev/null
    echo "$started" > "$RENDER.ts.tmp.$$"
    mv "$RENDER.tmp.$$" "$RENDER" && mv "$RENDER.ts.tmp.$$" "$RENDER.ts"
else
    [ -n "$sid" ] || exit 0
    for _ in $(seq 1 200); do
        ts=$(cat "$RENDER.ts" 2>/dev/null)
        [ -n "$ts" ] && [ "$ts" -ge $((started - 5)) ] && [ -s "$RENDER" ] && break
        ts=""; sleep 0.2
    done
    [ -n "$ts" ] || exit 0
fi

# Pack whole blocks (each starts at a "=== " line) into slices under LIMIT. A block
# longer than LIMIT is split between lines, and a line longer than LIMIT is cut.
awk -v k="$PART" -v n="$PARTS" -v lim="$LIMIT" -v src="$SOURCE_LABEL" -v file="$RENDER" '
    function flush() { if (cur != "") { chunk[++c] = cur; cur = "" } }
    function add(t) { if (cur != "" && length(cur) + length(t) > lim) flush(); cur = cur t }
    function addline(l) {
        if (length(blk) + length(l) > lim) { add(blk); flush(); blk = "" }
        blk = blk l
    }
    /^=== / { if (blk != "") add(blk); blk = "" }
    { line = $0 "\n"
      while (length(line) > lim) { addline(substr(line, 1, lim) "\n"); line = substr(line, lim + 1) }
      addline(line) }
    END {
        if (blk != "") add(blk); flush()
        if (k > c) exit
        printf "<shared-rules source=\"%s\" part=\"%d of %d\">\n", src, k, (c < n ? c : n)
        printf "%s", chunk[k]
        if (c > n && k == n) {
            split(chunk[n + 1], first, "\n")
            printf "\n=== more rules ===\nThe rest (%d more slice(s)) did not fit in this session'"'"'s hooks. Before other work, read %s from the line that starts:\n    %s\n", c - n, file, substr(first[1], 1, 200)
        }
        print "</shared-rules>"
    }' "$RENDER"
exit 0
