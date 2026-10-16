# shared-rules

A shared set of Claude rules, plus the plugins that install them into your own
`~/.claude/rules/` folder. Claude Code then loads the rules natively in every project
and every session.

The rules are portable cores: each states a general discipline and the reasons for it.
A project that needs a sharper version keeps its own copy in its own
`.claude/rules/` and adds the reasons that are specific to it.

## Install

```
/plugin marketplace add bogheorghiu/shared-rules
/plugin install shared-rules@claude-rules
```

| Plugin | What it does |
|---|---|
| [`shared-rules`](plugins/shared-rules/) | Installs this repo's rule set into `~/.claude/rules/shared-rules/`. You can edit the rules there; a plugin update never overwrites your edits without asking. |
| [`shared-rules-custom-repo`](plugins/shared-rules-custom-repo/) | Add-on that loads rules from a git repo you choose, alongside the bundled set or instead of it. Installing it also installs `shared-rules`. |

Each plugin's README lists exactly what it runs, reads and writes.

**If you used the older local install** (a clone in `~/.claude/rules/shared` with a
`local-update.sh` SessionStart hook): it no longer works, because the rules moved. Delete
`~/.claude/rules/shared`, remove that hook from `~/.claude/settings.json`, and install
the plugin. Otherwise the rules load twice, or the hook fails at every start.

**Claude desktop and claude.ai** don't run plugin hooks. Paste the rules you want into
the app's personal-preferences field in Settings, and paste them again whenever a rule
changes.

## Adding or changing a rule (maintainers)

1. Add or edit a file in `plugins/shared-rules/rules/`.
   - A rule with no frontmatter loads in every session.
   - A rule whose frontmatter has `paths:` loads only when Claude works on matching
     files.
   - This repo is public, so a rule must hold nothing personal and no secrets.
2. Record the new text in the release history:
   `bash tools/update-rules-history.sh`. Users' copies of any text a release has
   shipped count as the plugin's own, so an update can replace them without asking.
   The test suite fails if a bundled rule is missing from the history.
3. Raise `version` in `plugins/shared-rules/.claude-plugin/plugin.json`. Users receive
   rules only with a new version.

## Tests

- `bash plugins/shared-rules/hooks/sync-rules.test.sh`
- `bash plugins/shared-rules-custom-repo/hooks/sync-repo.test.sh`
- `bash tests/shared-tail.test.sh`

CI runs all three. `tests/live/live.py` is the end-to-end test through the real
`claude` CLI. It spends tokens, so it runs by hand. Its design, release rule and
results are in `tests/live/PREREG-0.5.md`.

Design and decisions: `docs/DESIGN-managed-rules.md`.
