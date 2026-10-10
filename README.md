# claude-rules

One source of Claude rules, shared by every project and every session. A rule is a
Markdown file in `rules/`; whoever installs this repo gets every rule in that folder.

The rules here are the portable cores: the general discipline and the reasons for it.
A project that needs a sharper version keeps its own copy in its own
`.claude/rules/` and adds the reasons specific to that project. The copy here stays
general on purpose.

## Adding a rule

Drop one file into `rules/`. No index, manifest or registration step exists, because
every delivery path below reads the folder itself, and a list kept by hand would drift
out of step with it.

- A rule with no frontmatter loads in full in every session.
- A rule whose frontmatter has `paths:` is path-scoped. Locally, Claude Code loads it
  only when you work on matching files. In cloud sessions the plugin lists it with
  its path patterns and says where to read it (see below).
- This repo is public, so a rule must hold nothing personal and no secrets.

## Delivery

### 1. Local machines (Claude Code CLI / IDE)

Claude Code loads every `.md` file under `~/.claude/rules/` in every session. A plain
clone would also load this README as a rule. So clone just the `rules/` folder, using
a sparse checkout:

```bash
git clone --filter=blob:none --no-checkout https://github.com/bogheorghiu/claude-rules ~/.claude/rules/shared
git -C ~/.claude/rules/shared sparse-checkout set --no-cone '/rules/'
git -C ~/.claude/rules/shared checkout
```

Then add a SessionStart hook to `~/.claude/settings.json` that pulls updates. It runs
detached, so it never blocks a session and never fails one when you're offline. A pull
that fails just leaves the last good copy in place:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "(git -C \"$HOME/.claude/rules/shared\" pull --ff-only -q >/dev/null 2>&1 &) ; exit 0"
          }
        ]
      }
    ]
  }
}
```

A pulled update takes effect from the next session. Claude Code reads rules when a
session starts, and the docs don't say whether that happens before or after
SessionStart hooks run.

**Check it worked:** run `/memory` in a new session and confirm the files from
`rules/` are listed. The Claude Code docs say subfolders are scanned for *project*
`.claude/rules/`. They don't say the same for `~/.claude/rules/`, so check rather
than assume.

If the rules aren't listed, Claude Code isn't reading subfolders of
`~/.claude/rules/`. Clone the repo somewhere else and copy (or symlink) the files from
`rules/` directly into `~/.claude/rules/`.

### 2. Cloud sessions and other sessions with no `~/.claude`

Install the `shared-rules` plugin from the `ex-cog-dev` marketplace. Its SessionStart
hook fetches this repo into the plugin's data folder (or updates it there), then
prints the rules into the session's context:

- **A rule without `paths:`** is printed in full.
- **A path-scoped rule** is listed with its `paths:` block and the file location, and
  Claude is told to read it before working on matching files. A hook can't load a
  rule conditionally the way Claude Code does locally. Printing the whole rule would
  spend context on rules that may never apply. Dropping it would hide it. Listing it
  keeps it findable at the cost of one read.
- **Offline, nothing cached yet:** the hook prints one line saying no shared rules
  were loaded. Without that line, a failed fetch would look the same as having no
  rules.
- **Machines that already have the local install** (`~/.claude/rules/shared` exists):
  the hook prints nothing, because Claude Code already loads those rules and they
  would otherwise appear twice.

### 3. Claude desktop / claude.ai app

There is no hook here. Paste the rules you want into the app's personal-preferences
field in Settings. Re-paste them whenever a rule changes. The app can't pull updates, so
this copy goes stale until you refresh it by hand.
