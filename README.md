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
- Plugin users get the new rule with their next plugin update. The plugin carries no
  version number on purpose: Claude Code then versions it by commit, so every commit
  counts as an update and adding a rule stays one file. Claude Code doesn't
  auto-update third-party marketplaces by default; run `/plugin update`, or turn on
  auto-update for this marketplace.

## Delivery

### 1. Local machines (Claude Code CLI / IDE)

Claude Code loads every `.md` file under `~/.claude/rules/` in every session. A plain
clone would also load this README as a rule. So clone just the `rules/` folder, plus
the small update script (not a `.md` file, so never loaded as a rule), using a sparse
checkout:

```bash
git clone --filter=blob:none --no-checkout https://github.com/bogheorghiu/claude-rules ~/.claude/rules/shared
git -C ~/.claude/rules/shared sparse-checkout set --no-cone '/rules/' '/hooks/local-update.sh'
git -C ~/.claude/rules/shared checkout
```

Then add a SessionStart hook to `~/.claude/settings.json` that checks for updates.
Choose the mode at the end of the command:

- `ask` (recommended): new or changed rules, and changes to the update script itself,
  wait for your approval. Claude tells you
  what changed at the start of a session and applies the update only if you say yes.
- `auto`: they're applied as soon as they're published.

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$HOME/.claude/rules/shared/hooks/local-update.sh\" ask",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
```

The script never blocks or fails a session: offline, it does nothing and the last copy
stays in place. An approved or automatic update takes effect from the next session,
because Claude Code reads rules when a session starts, and the docs don't say whether
that happens before or after SessionStart hooks run.

**Installed before the update script existed?** Add it to your checkout once:
`git -C ~/.claude/rules/shared sparse-checkout add '/hooks/local-update.sh'`, then
`git -C ~/.claude/rules/shared pull`.

**Check it worked:** run `/memory` in a new session and confirm the files from
`rules/` are listed. The Claude Code docs say subfolders are scanned for *project*
`.claude/rules/`. They don't say the same for `~/.claude/rules/`, so check rather
than assume.

If the rules aren't listed, Claude Code isn't reading subfolders of
`~/.claude/rules/`. Clone the repo somewhere else and copy (or symlink) the files from
`rules/` directly into `~/.claude/rules/`.

### 2. The plugin: cloud sessions, and anywhere without the local install

This repo is also a Claude Code plugin marketplace with one plugin, `shared-rules`:

```
/plugin marketplace add bogheorghiu/claude-rules
/plugin install shared-rules@claude-rules
```

Its SessionStart hook prints the rules into the session's context:

- **A rule without `paths:`** is printed in full.
- **A path-scoped rule** is listed with its `paths:` block and file location, and
  Claude is told to read it before working on matching files. A hook can't load a
  rule conditionally the way Claude Code does locally; printing it would spend
  context on rules that may never apply, and dropping it would hide it.
- **Machines with the local install of the same repo** get nothing from the plugin,
  because Claude Code already loads those rules and they would otherwise appear twice.

**Settings** (Claude Code asks when you enable the plugin):

- **Rules repository.** Empty by default: the plugin loads the rules shipped inside
  it, so they change only when the plugin updates. Set a git URL to load your own
  repo's `rules/` folder instead.
- **Rule updates** (for your own repo): `ask` (default) or `auto`. With `ask`, rules
  added or changed after you installed wait for your approval: Claude tells you what
  changed at the start of a session and applies the update only if you say yes. With
  `auto`, they load as soon as they're published. One limit: approvals are remembered
  in the plugin's data folder, so a container that starts empty every time has no
  record of them and loads whatever the repo holds at that moment.

**What it runs and fetches.** With no repository set, nothing: it reads the rule files
shipped with it. With your own repository set, each session start runs `git` to clone
it (or update the saved copy) into the plugin's data folder. It sends nothing anywhere
else, and the rule files are read as text, never executed. The approve command it
offers runs `git reset` in that saved copy, and only when you approve.

### 3. Claude desktop / claude.ai app

There is no hook here. Paste the rules you want into the app's personal-preferences
field in Settings. Re-paste them whenever a rule changes. The app can't pull updates, so
this copy goes stale until you refresh it by hand.
