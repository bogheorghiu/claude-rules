#!/bin/bash
# SessionStart hook for the local install (~/.claude/rules/shared, see README): keeps
# its rules current. `local-update.sh auto` applies new and changed rules at once;
# `local-update.sh ask` (the default) only tells Claude what changed and how the user
# can approve it. Must never block or fail a session: every failure exits 0, leaving
# the rules Claude Code already loaded in place.

MODE=ask; [ "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" = auto ] && MODE=auto
DIR="$HOME/.claude/rules/shared"
[ -e "$DIR/.git" ] || exit 0

export GIT_TERMINAL_PROMPT=0
t=(); command -v timeout >/dev/null 2>&1 && t=(timeout 15)
# The install is a blob:none partial clone, so a reset downloads the new rule files:
# it needs the same stall guard as the fetch.
git_net() { "${t[@]}" git -C "$DIR" -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=10 "$@" >/dev/null 2>&1; }
git_net fetch -q origin HEAD || exit 0

new=$(git -C "$DIR" rev-parse FETCH_HEAD 2>/dev/null) || exit 0
[ "$new" = "$(git -C "$DIR" rev-parse HEAD 2>/dev/null)" ] && exit 0
# A failed diff must not read as "no rule changed": ask mode fails toward consent.
# This script counts too: it runs every session, so a silent update to it could drop
# the ask check itself.
changed=$(git -C "$DIR" diff --name-status HEAD "$new" -- 'rules/*.md' 'hooks/local-update.sh' 2>/dev/null) || exit 0

if [ "$MODE" = auto ] || [ -z "$changed" ]; then
    git_net reset -q --hard "$new"
    exit 0
fi

echo "[shared-rules] Rule updates are waiting for the user's approval (local install, update mode 'ask')."
echo "The rules loaded this session are the approved version $(git -C "$DIR" rev-parse --short HEAD). The source has a newer version $new changing:"
printf '%s\n' "$changed" | sed 's/^/    /'
echo "Tell the user about this pending update before other work. To show them the changes:"
echo "    git -C $(printf %q "$DIR") diff HEAD $new -- 'rules/*.md' 'hooks/local-update.sh'"
echo "Only if the user explicitly approves, run (the rules then load from the next session):"
echo "    git -C $(printf %q "$DIR") reset -q --hard $new"
exit 0
