# shared-rules

A shared set of rules for Claude Code, installed into your own rules folder so they
apply in every project and every session. The rules cover working habits that hold
across projects: state the reason behind each decision, pre-register what would count
as success before you test, check each hand-off against its source, verify a delegated
agent's work against what it changed, reuse what exists before writing new code, build
only what was asked, and make no drive-by edits. Each rule says why it exists.

You can edit the rules. A later version of the plugin never overwrites your edits
without asking you first.

## What it does

At the start of each session, a hook runs that does three things:

1. **First install.** It copies the rules bundled with this version into
   `~/.claude/rules/shared-rules/`. Claude Code loads that folder natively from the next
   session on, so for this first session the hook also prints the rules into context.
2. **Same version, nothing to do.** It prints nothing. Claude Code has already loaded
   the folder.
3. **A new plugin version.**
   - If you haven't changed the folder, the hook replaces its rules with the new
     version's, then tells Claude what changed and which rules no longer apply.
   - If you have edited, added or deleted files in the folder, it changes nothing and
     Claude asks you to choose. Claude Code never speaks first, so the question comes
     with Claude's reply to your first message in that session, whatever it is:
     - **Back up and update.** Your edited and added files move to a backup folder
       (by default `~/.claude/shared-rules-backups/<date-time>/`, or one you name),
       then the new version's rules are installed exactly.
     - **Keep yours.** This declines the new version's rule changes entirely: your
       folder stays exactly as it is. The rest of the plugin update still applies.
       You're asked again at the next version.

A file you restored to the text of an older release still counts as the plugin's own,
not as your edit.

Rules with `paths:` frontmatter apply only to matching files. Claude Code handles them
natively. When the hook prints rules, it lists these with their paths instead of
printing them in full.

## Install

```
/plugin marketplace add bogheorghiu/shared-rules
/plugin install shared-rules@claude-rules
```

**If `~/.claude/rules/shared-rules/` already exists and wasn't made by this plugin,**
nothing is touched. Claude asks whether to back up that folder and install there, or
to install into `~/.claude/rules/shared-rules-plugin/` instead.

## Examples

- **Start a session after installing.** Ask "what shared rules are you following?" and
  Claude lists them, the first time from the hook's output and afterwards from the
  folder.
- **Edit a rule.** Change `~/.claude/rules/shared-rules/no-drive-by-edits.md` to fit how
  you work. It applies from your next session. When a plugin update arrives, Claude
  tells you before anything is replaced.
- **Decide on an update.** When Claude reports a pending update, say "back it up and
  update" or "keep mine". Claude runs the matching command that the hook printed.

## What it runs, reads and writes

It runs one bash script, `hooks/sync-rules.sh`, at session start, using the standard
tools `find`, `awk`, `sed`, `cp`, `mv` and `sha256sum` or `shasum`.

**Network:** none.

**It writes:**
- `~/.claude/rules/shared-rules/`: the rules, plus a `.shared-rules.manifest` that
  records the installed version and each file's hash. If you chose the alternative
  location, the same files go to `~/.claude/rules/shared-rules-plugin/` instead.
- `~/.claude/shared-rules-backups/<date-time>/`: only when you choose to back up and
  update.
- The plugin's data folder (`~/.claude/plugins/data/...`): the session's rendered output,
  your choices, and a lock. Session files are deleted after two days.

**It deletes:** only files it installed itself and you haven't changed. It deletes
nothing of yours: your edits and additions are moved, never removed.

**It never:** changes settings, sends data anywhere, or runs code from outside the
plugin.

**Context cost:** about 14 KB on the first session and in fresh containers, then
nothing. A `/compact` of the first session prints its rules again, because they never
loaded natively in that session.

**Where it works:** Claude Code, CLI and IDE. Cloud sessions get the rules each time,
because each one starts with an empty home folder. Plugins don't run in claude.ai chat,
so it has no effect there.

## Troubleshooting

- **No rules in a new session after installing.** The first session gets them from the
  hook's output. Check that `~/.claude/rules/shared-rules/` exists. Run `/memory`; the
  rule files should be listed.
- **An update was installed but Claude said nothing.** Send any message; the question
  comes with the reply. Claude Code never speaks before your first message.
- **An update keeps asking.** It asks until you choose. "Keep yours" stops the questions
  until the next version.
- **Start over.** Delete `~/.claude/rules/shared-rules/`. The next session installs
  fresh.
- **Uninstalling.** Uninstalling leaves your rules folder in place, since it's yours.
  Delete it by hand if you no longer want the rules.

## If the add-on switched these rules off

When you chose "only my own rules" with `shared-rules-custom-repo`, this plugin stands
down. If the add-on is later uninstalled, the next session tells Claude how to switch
the bundled rules back on, using the command `restore`.

## Your own rules repo

The add-on `shared-rules-custom-repo`, from the same marketplace, loads rules from a git
repo you choose, next to this set or instead of it. It isn't part of this plugin.

## Support

Issues: <https://github.com/bogheorghiu/shared-rules/issues>. License: MIT.
