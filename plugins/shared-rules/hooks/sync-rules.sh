#!/bin/bash
# SessionStart hook of the shared-rules plugin. Keeps a copy of the rules bundled with
# this plugin version in ~/.claude/rules/shared-rules/, where Claude Code loads them
# natively and the user can edit them. A new plugin version replaces that copy only
# if the user hasn't changed it; otherwise Claude asks first. Local files only: no
# network. Must never block or fail a session: every failure falls through to exit 0.

NAME=shared-rules
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SELF="$ROOT/hooks/$(basename "$0")"
BUNDLED="$ROOT/rules"
HISTORY="$ROOT/rules-history.txt"   # "<sha256>  <path>" of every rule file any release shipped
DATA="${CLAUDE_PLUGIN_DATA:-$HOME/.cache/$NAME}"
RULES_HOME="$HOME/.claude/rules"
DEFAULT_TARGET="$RULES_HOME/shared-rules"
ALTERNATE_TARGET="$RULES_HOME/shared-rules-plugin"
MANIFEST=.shared-rules.manifest      # not .md, so Claude Code never loads it as a rule
REPLACED="$RULES_HOME/.shared-rules-replaced"   # the user switched this plugin's rules off
VERSION=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$ROOT/.claude-plugin/plugin.json" | head -1)
SOURCE_LABEL="shared-rules $VERSION"

# Where the rules live: the user's recorded choice, else the alternate folder if it is
# ours and the default isn't (a reset data folder must not lose the choice), else the default.
target() {
    local t; t=$(cat "$DATA/target" 2>/dev/null)
    if [ -z "$t" ] && [ -f "$ALTERNATE_TARGET/$MANIFEST" ] && [ ! -f "$DEFAULT_TARGET/$MANIFEST" ]; then t="$ALTERNATE_TARGET"; fi
    printf '%s\n' "${t:-$DEFAULT_TARGET}"
}
manifest_version() { sed -n 's/^version //p' "$1/$MANIFEST" 2>/dev/null | head -1; }
manifest_files() { awk '$1 != "version" {print substr($0, 67)}' "$1/$MANIFEST" 2>/dev/null; }
manifest_hash() { awk -v f="$2" '$1 != "version" && substr($0, 67) == f {print $1; exit}' "$1/$MANIFEST" 2>/dev/null; }

# What the user changed in a folder this plugin wrote: lines "edited <f>", "added <f>",
# "deleted <f>". A file matching what the plugin wrote, or what any release shipped
# under that same name, is the plugin's own and safe to replace.
changes() {
    local dir="$1" f h m
    while IFS= read -r f; do
        h=$(sha "$dir/$f"); m=$(manifest_hash "$dir" "$f")
        [ -n "$m" ] && [ "$h" = "$m" ] && continue
        grep -qxF "$h  $f" "$HISTORY" 2>/dev/null && continue
        if [ -n "$m" ]; then echo "edited $f"; else echo "added $f"; fi
    done < <(files_in "$dir")
    manifest_files "$dir" | while IFS= read -r f; do [ -e "$dir/$f" ] || echo "deleted $f"; done
}

# Install the bundled rules into $1 exactly. Files the user changed or added move to
# $2 first (keeping their paths); everything else in the folder is the plugin's own.
# Prints the paths that are new or different, for this session to read.
install_into() {
    local dir="${1:?}" backup="$2" f kind before
    mkdir -p "$dir" || return 1
    if [ -n "$backup" ]; then
        changes "$dir" | while read -r kind f; do
            [ "$kind" = deleted ] && continue
            mkdir -p "$backup/$(dirname "$f")" && mv "$dir/$f" "$backup/$f" || exit 1
        done || return 1
    fi
    before=$(mktemp) || return 1
    while IFS= read -r f; do printf '%s  %s\n' "$(sha "$dir/$f")" "$f"; done < <(files_in "$dir") > "$before"
    while IFS= read -r f; do rm -f "${dir:?}/${f:?}"; done < <(files_in "$dir")
    find "$dir" -mindepth 1 -type d -empty -delete 2>/dev/null
    local ok=1
    while IFS= read -r f; do
        mkdir -p "$dir/$(dirname "$f")" && cp "$BUNDLED/$f" "$dir/$f" || ok=""
    done < <(cd "$BUNDLED" && find . -type f | sed 's#^\./##')
    { echo "version $VERSION"; while IFS= read -r f; do printf '%s  %s\n' "$(sha "$dir/$f")" "$f"; done < <(files_in "$dir"); } > "$dir/$MANIFEST" || ok=""
    while IFS= read -r f; do grep -qxF "$(sha "$dir/$f")  $f" "$before" || echo "$f"; done < <(files_in "$dir")
    rm -f "${before:?}"
    [ -n "$ok" ]
}

# ==== shared helpers: kept identical in both plugins (tests/shared-tail.test.sh checks) ====
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }
# Files and symlinks, never directories: a symlink is moved or replaced, never written through.
files_in() { [ -d "$1" ] && (cd "$1" && find . ! -type d ! -name "$MANIFEST" | sed 's#^\./##' | LC_ALL=C sort); }
cmd_prefix() { printf 'CLAUDE_PLUGIN_DATA=%q bash %q' "${CLAUDE_PLUGIN_DATA:-}" "$SELF"; }
new_backup() { printf '%s\n' "$HOME/.claude/shared-rules-backups/$(date +%Y%m%d-%H%M%S)"; }
remember() { [ -n "${sid:-}" ] && [ $# -gt 0 ] && printf '%s\n' "$@" > "$DATA/printed-$sid"; }
# One fetch, install or decision at a time. A lock older than 2 minutes was left by a
# killed run, so it never blocks the user's decision for long.
lock() {
    mkdir -p "$DATA"
    find "$DATA/cache.lock" -maxdepth 0 -mmin +2 -exec rmdir {} \; 2>/dev/null
    for _ in $(seq 1 100); do mkdir "$DATA/cache.lock" 2>/dev/null && return 0; sleep 0.2; done; return 1
}
unlock() { rmdir "$DATA/cache.lock" 2>/dev/null; }
# ==== end shared helpers ====

# --- Commands Claude runs once the user decides (the session-start notice names them) ---
case "${1:-}" in
apply)   # apply <version> [backup-folder]: back up the user's changes, install the version
    [ "${2:-}" = "$VERSION" ] || { echo "[$NAME] Version ${2:-?} is not the installed plugin version $VERSION; nothing changed." >&2; exit 1; }
    lock || { echo "[$NAME] A session start is updating the rules; try again in a minute." >&2; exit 1; }
    t=$(target); b="${3:-$(new_backup)}"
    if install_into "$t" "$b" >/dev/null; then
        rm -f "${DATA:?}/declined"; unlock
        [ -d "$b" ] && echo "[$NAME] The user's changed and added rules are in $b."
        echo "[$NAME] Installed version $VERSION into $t. It loads from the next session on."
        exit 0
    fi
    unlock; echo "[$NAME] Could not finish installing into $t (disk full or not writable?). Any changed files already moved are in $b. Fix the cause and run the same command again." >&2; exit 1 ;;
keep)    # keep <version>: decline this version's rule changes entirely
    [ "${2:-}" = "$VERSION" ] || { echo "[$NAME] Version ${2:-?} is not the installed plugin version $VERSION." >&2; exit 1; }
    mkdir -p "$DATA" && echo "$VERSION" > "$DATA/declined"
    echo "[$NAME] Kept the rules folder exactly as it is. Version $VERSION's rule changes are declined; the user is asked again at the next version."
    exit 0 ;;
choose)  # choose here|elsewhere [backup-folder]: first install found a folder of that name already there
    lock || { echo "[$NAME] A session start is updating the rules; try again in a minute." >&2; exit 1; }
    case "${2:-}" in
    here)
        b="${3:-$(new_backup)}"
        install_into "$DEFAULT_TARGET" "$b" >/dev/null || { unlock; echo "[$NAME] Could not install into $DEFAULT_TARGET." >&2; exit 1; }
        echo "$DEFAULT_TARGET" > "$DATA/target"; unlock
        [ -d "$b" ] && echo "[$NAME] What was in $DEFAULT_TARGET is now in $b."
        echo "[$NAME] Installed into $DEFAULT_TARGET. The rules load from the next session on." ;;
    elsewhere)
        if [ -e "$ALTERNATE_TARGET" ] && [ ! -f "$ALTERNATE_TARGET/$MANIFEST" ]; then
            unlock; echo "[$NAME] $ALTERNATE_TARGET exists too and isn't this plugin's. Rename one of them, then start a new session." >&2; exit 1
        fi
        b="${3:-$(new_backup)}"   # the folder may already be ours, with the user's edits in it
        install_into "$ALTERNATE_TARGET" "$b" >/dev/null || { unlock; echo "[$NAME] Could not install into $ALTERNATE_TARGET." >&2; exit 1; }
        [ -d "$b" ] && echo "[$NAME] Changed files from $ALTERNATE_TARGET are in $b."
        echo "$ALTERNATE_TARGET" > "$DATA/target"; unlock
        echo "[$NAME] Installed into $ALTERNATE_TARGET. The rules load from the next session on." ;;
    *) unlock; echo "usage: choose here|elsewhere [backup-folder]" >&2; exit 1 ;;
    esac
    exit 0 ;;
restore)   # switch the bundled set back on after shared-rules-custom-repo replaced it
    rm -f "${REPLACED:?}"
    echo "[$NAME] The bundled rules are switched back on; they install at the next session start."
    exit 0 ;;
esac

# --- Session start: decide what this session needs printed ---
render() {
    if [ -e "$REPLACED" ]; then   # the user replaced these rules with their own set
        # The add-on that set the marker keeps a data folder beside ours; without it the
        # marker is orphaned and would silence this plugin with no way back in sight.
        if ! compgen -G "${DATA%/*}/shared-rules-custom-repo*" >/dev/null; then
            echo "[$NAME] The bundled rules are switched off: shared-rules-custom-repo replaced them, but it no longer seems installed. To switch them back on, run:"
            echo "    $(cmd_prefix) restore"
        fi
        return
    fi
    local t old ch gone new=() all=()
    t=$(target)
    # A /compact of a session that had rules printed rather than loaded needs them
    # printed again: its native load happened before they existed. (A resume starts a new
    # process, which loads the folder natively, so it needs nothing.)
    if [ "$src" = compact ] && [ -n "$sid" ] && [ -s "$DATA/printed-$sid" ] && [ -f "$t/$MANIFEST" ]; then
        while IFS= read -r f; do [ -e "$t/$f" ] && new+=("$f"); done < "$DATA/printed-$sid"
        echo "[$NAME] Rules installed earlier in this session, printed again because they load natively only from the next session:"
        print_rules "$t" "${new[@]}"
        new=()
    fi
    if [ ! -e "$t" ]; then
        # First install, or a fresh container: nothing is loaded natively yet.
        while IFS= read -r f; do new+=("$f"); done < <(install_into "$t" "")
        echo "[$NAME] Installed rules version $VERSION into $t; Claude Code loads them natively from the next session on. This session's copy follows."
        remember "${new[@]}"
        print_rules "$t" "${new[@]}"
    elif [ ! -f "$t/$MANIFEST" ]; then
        # A folder of that name exists and isn't ours: never touch it unasked.
        echo "=== shared-rules: install location needs the user's decision ==="
        echo "The shared-rules plugin installs its rules into $t, but a folder of that name already exists and was not made by this plugin. Nothing was changed."
        echo "Tell the user before other work and let them choose:"
        echo "1. Use $t anyway: what is in it now moves to a backup folder (default ~/.claude/shared-rules-backups/<date-time>, or one they name), then the plugin installs there. Run:"
        echo "    $(cmd_prefix) choose here [backup-folder]"
        echo "2. Install into $ALTERNATE_TARGET instead, leaving $t alone. Run:"
        echo "    $(cmd_prefix) choose elsewhere"
        echo "Until then, this session's copy of the plugin's rules follows."
        while IFS= read -r f; do all+=("$f"); done < <(files_in "$BUNDLED")
        print_rules "$BUNDLED" "${all[@]}"
    elif [ "$t/$MANIFEST" -nt "$STAMP" ]; then
        # Another session started at the same moment wrote the folder while this one
        # waited for the lock: this session's native load came too early to see it.
        while IFS= read -r f; do all+=("$f"); done < <(files_in "$t")
        echo "[$NAME] Rules were installed or updated in $t while this session was starting; this session's copy follows."
        print_rules "$t" "${all[@]}"
    elif [ "$(manifest_version "$t")" != "$VERSION" ]; then
        old=$(manifest_version "$t"); ch=$(changes "$t")
        if [ -z "$ch" ]; then
            # Untouched by the user: the plugin update is the consent.
            gone=$(manifest_files "$t" | while IFS= read -r f; do [ -e "$BUNDLED/$f" ] || echo "$f"; done)
            while IFS= read -r f; do new+=("$f"); done < <(install_into "$t" "")
            echo "[$NAME] Updated the rules in $t from version $old to $VERSION (the user had not changed them)."
            if [ -n "$gone" ]; then
                echo "No longer in force (removed by this version; disregard them if loaded earlier in this session):"
                printf '%s\n' "$gone" | sed 's/^/    /'
            fi
            [ ${#new[@]} -gt 0 ] && echo "New or changed rules follow; they load natively from the next session on."
            remember "${new[@]}"
            print_rules "$t" "${new[@]}"
        elif [ "$(cat "$DATA/declined" 2>/dev/null)" = "$VERSION" ]; then
            :   # the user kept their own folder for this version; asked again at the next one
        else
            echo "=== shared-rules: rule update waiting for the user's decision ==="
            echo "The shared-rules plugin was updated from version $old to $VERSION, and the new version changes its rules. The rules folder $t has changes of the user's own, so nothing was replaced:"
            printf '%s\n' "$ch" | sed 's/^/    /'
            echo "Tell the user before other work and let them choose; do not choose for them."
            echo "1. Back up and update: their edited and added files move to a backup folder (default ~/.claude/shared-rules-backups/<date-time>, or one they name), then version $VERSION's rules are installed exactly. Run:"
            echo "    $(cmd_prefix) apply $VERSION [backup-folder]"
            echo "2. Keep theirs: this declines version $VERSION's rule changes entirely. The rules folder stays exactly as it is, and none of the version's rule additions, edits or removals apply. The rest of the plugin update still applies. They are asked again at the next version. Run:"
            echo "    $(cmd_prefix) keep $VERSION"
            echo "To show them what the new version would change:"
            echo "    diff -ru $(printf %q "$t") $(printf %q "$BUNDLED")"
        fi
    fi
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
# rules folder at once. A render counts only if it began within this start: all slices
# are launched together, and a later start can reuse the session id.
mkdir -p "$DATA" 2>/dev/null
started=$(date +%s)
input=$(cat 2>/dev/null)
field() { printf '%s' "$input" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\\1/p" | head -1 | tr -cd 'A-Za-z0-9_-'; }
sid=$(field session_id)
# startup, resume, clear or compact. Only resume and compact continue a conversation
# whose earlier context may hold printed rules; a session id alone can repeat (a
# `claude -p` run inside another session inherits its parent's id).
src=$(field source)
# The render is per Claude process too: every hook of one start shares it as their
# grandparent (each hook runs under its own shell), and parallel `claude -p` runs that
# inherited one session id don't share it.
claude_pid=$( (cat "/proc/$PPID/stat" 2>/dev/null | awk '{print $4}') || true)
[ -n "$claude_pid" ] || claude_pid=$(ps -o ppid= -p "$PPID" 2>/dev/null | tr -d ' ')
RENDER="$DATA/render-${sid:-x}-${claude_pid:-$$}.txt"
if [ "$PART" = 1 ]; then
    find "$DATA" -maxdepth 1 \( -name 'render-*' -o -name 'printed-*' -o -name 'start-*' \) -mtime +1 -exec rm -f {} + 2>/dev/null
    # Marks when this start began, before waiting: a folder written after it was written
    # while this session waited, too late for its native load.
    STAMP="$DATA/start-$$"; : > "$STAMP"
    # ~20 s: with a 15 s network step after it, slice 1 stays inside the 45 s hook timeout.
    # Rendering after a timed-out wait goes ahead, but the lock is another run's to release.
    locked=""; lock && locked=1
    ( render ) > "$RENDER.tmp.$$" 2>/dev/null
    [ -n "$locked" ] && unlock
    rm -f "${STAMP:?}"
    echo "$started" > "$RENDER.ts.tmp.$$"
    mv "$RENDER.tmp.$$" "$RENDER" && mv "$RENDER.ts.tmp.$$" "$RENDER.ts"
else
    [ -n "$sid" ] || exit 0
    for _ in $(seq 1 210); do   # ~42 s, inside the 45 s hook timeout
        ts=$(cat "$RENDER.ts" 2>/dev/null)
        [ -n "$ts" ] && [ "$ts" -ge $((started - 5)) ] && [ -e "$RENDER" ] && break
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
