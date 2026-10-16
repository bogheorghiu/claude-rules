#!/bin/bash
# SessionStart hook of the shared-rules-custom-repo add-on. Fetches the rules repo the
# user configured and mirrors its rules/ folder into ~/.claude/rules/shared-rules-custom-repo/,
# where Claude Code loads them natively. Changes upstream apply at once (auto) or only
# after the user approves the exact version (ask). The folder is a mirror: edit the repo.
# Must never block or fail the session: every failure falls through to exit 0.

NAME=shared-rules-custom-repo
# Settings come from the plugin's userConfig (plugin.json), exported as CLAUDE_PLUGIN_OPTION_<KEY>.
REPO_URL="${CLAUDE_PLUGIN_OPTION_RULES_REPO:-}"
# Anything but "auto" means ask: an unrecognised value must fail toward consent.
MODE=ask; [ "$(printf '%s' "${CLAUDE_PLUGIN_OPTION_UPDATE_MODE:-}" | tr '[:upper:]' '[:lower:]')" = auto ] && MODE=auto
DATA="${CLAUDE_PLUGIN_DATA:-$HOME/.cache/$NAME}"
CACHE="$DATA/repo"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SELF="$ROOT/hooks/$(basename "$0")"
RULES_HOME="$HOME/.claude/rules"
TARGET="$RULES_HOME/shared-rules-custom-repo"
MANIFEST=.custom-repo.manifest       # the commit mirrored; not .md, so never loaded as a rule
REPLACED="$RULES_HOME/.shared-rules-replaced"   # tells shared-rules to stand down
BASE_MANIFEST=.shared-rules.manifest
CANONICAL=https://github.com/bogheorghiu/claude-rules

# URLs compare after normalising the spellings of one repo: .git, a trailing /, SSH.
norm() {
    local u="${1%/}"; u="${u%.git}"
    case "$u" in git@*:*) u="${u#git@}"; u="${u/://}" ;; esac
    u="${u#*://}"; u="${u#*@}"           # scheme and user: https, http, ssh, git@
    printf '%s\n' "$u" | tr '[:upper:]' '[:lower:]'   # GitHub ignores case
}
# Shown to the model and in notices: drop any user:token@ part, which belongs in no transcript.
SHOWN_URL=$(printf '%s' "$REPO_URL" | sed -E 's#^([A-Za-z][A-Za-z0-9+.-]*://)[^/@]*@#\1#')
SOURCE_LABEL="${SHOWN_URL:-no repository set}"

# A private or mistyped URL must fail, not wait at a credential prompt; a stalled
# transfer must end even where `timeout` is absent (stock macOS).
export GIT_TERMINAL_PROMPT=0
git_net() {
    local t=()
    command -v timeout >/dev/null 2>&1 && t=(timeout 15)
    "${t[@]}" git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=10 "$@" >/dev/null 2>&1
}
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }
files_in() { [ -d "$1" ] && (cd "$1" && find . -type f ! -name "$MANIFEST" | sed 's#^\./##' | LC_ALL=C sort); }
cmd_prefix() { printf 'CLAUDE_PLUGIN_DATA=%q bash %q' "${CLAUDE_PLUGIN_DATA:-}" "$SELF"; }
new_backup() { printf '%s\n' "$HOME/.claude/shared-rules-backups/$(date +%Y%m%d-%H%M%S)"; }
remember() { [ -n "${sid:-}" ] && [ $# -gt 0 ] && printf '%s\n' "$@" > "$DATA/printed-$sid"; }
lock() {
    mkdir -p "$DATA"
    for _ in $(seq 1 100); do mkdir "$DATA/cache.lock" 2>/dev/null && return 0; sleep 0.2; done; return 1
}
unlock() { rmdir "$DATA/cache.lock" 2>/dev/null; }

# Make $TARGET an exact copy of the cache's rules/ folder at its checked-out commit.
# Prints the paths that are new or different, for this session to read.
mirror() {
    local f before
    mkdir -p "$TARGET" || return 1
    before=$(mktemp) || return 1
    while IFS= read -r f; do printf '%s  %s\n' "$(sha "$TARGET/$f")" "$f"; done < <(files_in "$TARGET") > "$before"
    while IFS= read -r f; do rm -f "${TARGET:?}/${f:?}"; done < <(files_in "$TARGET")
    find "$TARGET" -mindepth 1 -type d -empty -delete 2>/dev/null
    while IFS= read -r f; do
        mkdir -p "$TARGET/$(dirname "$f")" && cp "$CACHE/rules/$f" "$TARGET/$f"
    done < <(files_in "$CACHE/rules")
    git -C "$CACHE" rev-parse HEAD > "$TARGET/$MANIFEST" 2>/dev/null
    while IFS= read -r f; do grep -qxF "$(sha "$TARGET/$f")  $f" "$before" || echo "$f"; done < <(files_in "$TARGET")
    rm -f "${before:?}"
}
mirrored() { cat "$TARGET/$MANIFEST" 2>/dev/null; }

# --- Commands Claude runs once the user decides (the session-start notice names them) ---
case "${1:-}" in
approve)   # approve <sha>: the user said yes to a pending update
    # A full sha only: names like FETCH_HEAD move, and would let a later push ride along.
    # 40 or 64 hex digits: a SHA-256 repo's ids are longer, and must stay approvable.
    lock || { echo "[$NAME] Could not approve: a session start is still updating the rules. Try again in a minute." >&2; exit 1; }
    if [[ "${2:-}" =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]] && git -C "$CACHE" reset -q --hard "$2" 2>/dev/null && mirror >/dev/null; then
        unlock; echo "[$NAME] Approved $2; these rules load from the next session on."; exit 0
    fi
    unlock; echo "[$NAME] Could not approve '${2:-}': not a version fetched into $CACHE." >&2; exit 1 ;;
combine)   # combine both|replace [backup-folder]: alongside the bundled shared-rules set, or instead of it
    mkdir -p "$DATA"
    case "${2:-}" in
    both)
        rm -f "${REPLACED:?}"; echo both > "$DATA/combine"
        echo "[$NAME] Both rule sets stay: the bundled shared-rules set and the rules from $SHOWN_URL. The bundled set comes back from the next session on if it was replaced." ;;
    replace)
        b="${3:-$(new_backup)}"
        for d in "$RULES_HOME/shared-rules" "$RULES_HOME/shared-rules-plugin"; do
            if [ -f "$d/$BASE_MANIFEST" ]; then
                mkdir -p "$b" && mv "$d" "$b/" || { echo "[$NAME] Could not move $d to $b; nothing replaced." >&2; exit 1; }
                echo "[$NAME] Moved the bundled set from $d to $b/$(basename "$d")."
            fi
        done
        mkdir -p "$RULES_HOME" && touch "$REPLACED" && echo replace > "$DATA/combine"
        echo "[$NAME] From the next session on, only the rules from $SHOWN_URL load. To bring the bundled set back: $(cmd_prefix) combine both" ;;
    *) echo "usage: combine both|replace [backup-folder]" >&2; exit 1 ;;
    esac
    exit 0 ;;
esac

# --- Session start ---
render() {
    local pending="" changed new=() f
    if [ -z "$REPO_URL" ]; then
        echo "[$NAME] No rules repository is set, so no custom rules were loaded. Set one with /plugin configure shared-rules-custom-repo@claude-rules (rules_repo)."
        return
    fi
    if [ "$(norm "$REPO_URL")" = "$(norm "$CANONICAL")" ]; then
        echo "[$NAME] rules_repo points at the shared-rules repo itself, whose rules the shared-rules plugin already installs. Nothing extra was loaded; set rules_repo to your own repo."
        return
    fi
    # Later start of a session whose rules were printed rather than loaded (/compact, resume).
    if [ -n "$sid" ] && [ -s "$DATA/printed-$sid" ]; then
        while IFS= read -r f; do [ -e "$TARGET/$f" ] && new+=("$f"); done < "$DATA/printed-$sid"
        echo "[$NAME] Rules installed earlier in this session, printed again because they load natively only from the next session:"
        print_rules "$TARGET" "${new[@]}"
        return
    fi
    # A cache cloned from a different URL (the rules_repo setting changed) is not this repo.
    if [ -d "$CACHE/.git" ] && [ "$(norm "$(git -C "$CACHE" remote get-url origin 2>/dev/null)")" != "$(norm "$REPO_URL")" ]; then
        rm -rf "${CACHE:?}"
    fi
    if [ -d "$CACHE/.git" ]; then
        # fetch + reset rather than pull: a force-pushed upstream would make
        # `pull --ff-only` fail on every session and freeze the cache for good.
        # The cache's checkout is the approved version; in ask mode a newer fetch waits.
        if ! git_net -C "$CACHE" fetch --depth 1 -q origin HEAD; then
            :   # offline: the mirrored version stays in force
        elif ! git -C "$CACHE" rev-parse -q --verify HEAD >/dev/null; then
            # Cloned while the repo was still empty: no approved version exists to
            # diff against, so its first content loads as a first clone would.
            git -C "$CACHE" reset -q --hard FETCH_HEAD >/dev/null 2>&1
        elif [ "$(git -C "$CACHE" rev-parse FETCH_HEAD)" != "$(git -C "$CACHE" rev-parse HEAD)" ]; then
            # Nothing to ask about when no loaded rule changed (a README edit, say). A
            # failed diff must not read as "no change": ask mode fails toward consent.
            if ! changed=$(git -C "$CACHE" diff --name-only HEAD FETCH_HEAD -- 'rules/*.md' 2>/dev/null); then
                :   # unreadable diff: change nothing (ask mode fails toward consent)
            elif [ "$MODE" = auto ] || [ -z "$changed" ]; then
                git -C "$CACHE" reset -q --hard FETCH_HEAD >/dev/null 2>&1
            else
                pending=$(git -C "$CACHE" rev-parse FETCH_HEAD)
            fi
        fi
    else
        # A first clone is loaded in either mode: installing the add-on is consent to
        # the rules it points at today; ask mode governs what changes after that.
        # Clone beside the cache and move it in only when complete, so a clone killed
        # mid-way can never leave a half-made .git that every later session trips on.
        mkdir -p "$DATA" 2>/dev/null
        local tmp="$CACHE.tmp.$$"
        if git_net clone --depth 1 -q "$REPO_URL" "$tmp"; then
            rm -rf "${CACHE:?}"   # a leftover without .git would swallow the clone
            mv "$tmp" "$CACHE"
        fi
        rm -rf "${tmp:?}"
    fi

    if [ ! -d "$CACHE/.git" ]; then
        echo "[$NAME] No custom rules loaded this session: could not fetch $SHOWN_URL and nothing is cached."
        return
    fi
    if [ "$(mirrored)" != "$(git -C "$CACHE" rev-parse HEAD 2>/dev/null)" ]; then
        while IFS= read -r f; do new+=("$f"); done < <(mirror)
        if [ ${#new[@]} -eq 0 ] && [ -z "$(files_in "$TARGET")" ]; then
            echo "[$NAME] $SHOWN_URL has no files under rules/, so no custom rules were loaded."
        elif [ ${#new[@]} -gt 0 ]; then
            echo "[$NAME] Rules from $SHOWN_URL updated in $TARGET; Claude Code loads them natively from the next session on. This session's copy of the new or changed ones follows."
            remember "${new[@]}"
        fi
    fi
    if [ ! -s "$DATA/combine" ]; then
        echo
        echo "=== shared-rules-custom-repo: one question for the user ==="
        echo "This add-on loads rules from $SHOWN_URL. The shared-rules plugin, which it depends on, also installs its own bundled rule set. Ask the user, before other work, whether they want:"
        echo "1. Both sets (the default until they answer). Run:"
        echo "    $(cmd_prefix) combine both"
        echo "2. Only their own repo's rules: the bundled set moves to a backup folder (default ~/.claude/shared-rules-backups/<date-time>, or one they name) and stops being installed. Run:"
        echo "    $(cmd_prefix) combine replace [backup-folder]"
    fi
    if [ -n "$pending" ]; then
        echo
        echo "=== rule updates awaiting the user's approval ==="
        echo "Update mode is 'ask'. The custom rules in force are the approved version $(git -C "$CACHE" rev-parse --short HEAD)."
        echo "$SHOWN_URL has a newer version $pending changing:"
        git -C "$CACHE" diff --name-status HEAD "$pending" -- 'rules/*.md' | sed 's/^/    /'
        echo "Tell the user about this pending update before other work. To show them the changes:"
        echo "    git -C $(printf %q "$CACHE") diff HEAD $pending -- 'rules/*.md'"
        echo "Only if the user explicitly approves, run (the rules then load from the next session):"
        echo "    $(cmd_prefix) approve $pending"
    fi
    [ ${#new[@]} -gt 0 ] && print_rules "$TARGET" "${new[@]}"
}

# ==== shared tail: kept identical in both plugins (tests/shared-tail.test.sh checks) ====

# Print rule files from $1, given as paths relative to it. A rule with `paths:`
# frontmatter is listed, not printed: Claude Code loads it natively only when matching
# files are touched, and the session reads it on demand the same way.
print_rules() {
    local dir="$1" f scoped=(); shift
    # The \r strip matters: a rule committed from Windows has CRLF endings, its
    # '---\r' would never match the delimiter, and a path-scoped rule would load in full.
    # Unclosed frontmatter is no frontmatter: the file loads in full, never as a listing.
    frontmatter() {
        awk '{sub(/\r$/, "")} NR==1 && $0!="---" {exit} NR>1 && $0=="---" {closed=1; exit} NR>1 {buf = buf $0 "\n"} END {if (closed) printf "%s", buf}' "$1"
    }
    for f in "$@"; do
        case "$f" in *.md) ;; *) continue ;; esac
        if frontmatter "$dir/$f" | grep -q '^paths:'; then scoped+=("$f"); continue; fi
        echo
        echo "=== rule: $f ==="
        cat "$dir/$f"
    done
    if [ ${#scoped[@]} -gt 0 ]; then
        echo
        echo "=== path-scoped rules ==="
        echo "Not loaded here. Before working on files matching a rule's paths, read that rule's file."
        for f in "${scoped[@]}"; do
            echo
            echo "- $dir/$f"
            frontmatter "$dir/$f" | sed 's/^/    /'
        done
    fi
}

# Claude Code passes a hook at most 10,000 characters of output; beyond that the model
# sees only a 2,000-character preview. The limit is per hook, so hooks.json registers
# several and each prints one slice: `<script> part K N`.
PART="${2:-1}"; PARTS="${3:-1}"
[ "${1:-}" = part ] || { PART=1; PARTS=1; }
LIMIT=9000   # under 10,000, leaving room for the wrapper lines

# Render once per session start, so every slice comes from the same version. Only
# slice 1 renders; the others wait for its render, so no two slices ever touch the
# rules folder at once. A render counts only if it began within this start (a later
# /compact or resume fires SessionStart again with the same session id).
mkdir -p "$DATA" 2>/dev/null
started=$(date +%s)
sid=$(sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' 2>/dev/null | head -1 | tr -cd 'A-Za-z0-9_-')
RENDER="$DATA/render-${sid:-$$}.txt"
find "$DATA" -maxdepth 1 \( -name 'render-*' -o -name 'printed-*' \) -mtime +1 -exec rm -f {} + 2>/dev/null
if [ "$PART" = 1 ]; then
    # Sessions starting together share one rules folder: one render at a time.
    LOCK="$DATA/cache.lock"
    find "$LOCK" -maxdepth 0 -mmin +2 -exec rmdir {} \; 2>/dev/null   # left by a killed run
    locked=""
    # ~20 s: with a 15 s network step after it, slice 1 stays inside the 45 s hook timeout.
    for _ in $(seq 1 100); do mkdir "$LOCK" 2>/dev/null && { locked=1; break; }; sleep 0.2; done
    ( render ) > "$RENDER.tmp.$$" 2>/dev/null
    # Rendering after a timed-out wait goes ahead, but the lock is another run's to release.
    [ -n "$locked" ] && rmdir "$LOCK" 2>/dev/null
    echo "$started" > "$RENDER.ts.tmp.$$"
    mv "$RENDER.tmp.$$" "$RENDER" && mv "$RENDER.ts.tmp.$$" "$RENDER.ts"
else
    [ -n "$sid" ] || exit 0
    for _ in $(seq 1 210); do   # ~42 s, inside the 45 s hook timeout
        ts=$(cat "$RENDER.ts" 2>/dev/null)
        [ -n "$ts" ] && [ "$ts" -ge $((started - 30)) ] && [ -e "$RENDER" ] && break
        ts=""; sleep 0.2
    done
    if [ -z "$ts" ]; then
        [ -s "$RENDER" ] || exit 0   # nothing rendered yet this session: slice 1 reports
        echo "[$NAME] Slice $PART could not load in time; some rules may be missing. The full text is in $RENDER."
        exit 0
    fi
fi

# Pack whole blocks (each starts at a "=== " line) into slices under LIMIT. A block
# longer than LIMIT is split between lines, and a line longer than LIMIT is cut. Bytes,
# not characters (LC_ALL=C): every awk then counts alike, and a cut is moved back off
# UTF-8 continuation bytes so no character is split.
LC_ALL=C awk -v k="$PART" -v n="$PARTS" -v lim="$LIMIT" -v src="$SOURCE_LABEL" -v file="$RENDER" -v tag="$NAME" '
    function flush() { if (cur != "") { chunk[++c] = cur; from[c] = curfrom; cur = "" } }
    function add(t, at) { if (cur != "" && length(cur) + length(t) > lim) flush(); if (cur == "") curfrom = at; cur = cur t }
    function addline(l) {
        if (length(blk) + length(l) > lim) { add(blk, blkfrom); flush(); blk = "" }
        if (blk == "") blkfrom = NR
        blk = blk l
    }
    /^=== / { if (blk != "") add(blk, blkfrom); blk = "" }
    { line = $0 "\n"
      while (length(line) > lim) {
          cut = lim; while (cut > 1 && substr(line, cut + 1, 1) ~ /^[\200-\277]/) cut--
          addline(substr(line, 1, cut) "\n"); line = substr(line, cut + 1)
      }
      addline(line) }
    END {
        if (blk != "") add(blk, blkfrom); flush()
        if (k > c) exit
        printf "<%s source=\"%s\" part=\"%d of %d\">\n", tag, src, k, (c < n ? c : n)
        printf "%s", chunk[k]
        if (c > n && k == n) {
            printf "\n=== more rules ===\nThe rest did not fit in this session'"'"'s hooks. Before other work, read %s from line %d to the end.\n", file, from[n + 1]
        }
        printf "</%s>\n", tag
    }' "$RENDER"
exit 0
