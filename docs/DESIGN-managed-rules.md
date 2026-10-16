# Design: a rules folder the user owns, updated with consent

Status: decisions settled 2026-10-16 (see "Decisions"); being built on branch `claude/split-plugins-wip`.

## Why the design changes

People edit rules, and people turn on plugin auto-update. If a plugin update rewrote
the rules with no consent gate, it would silently overwrite or delete the user's edits.

The earlier design dodged this by never letting users edit anything: rules lived in the
plugin cache and were printed into context. That removes the risk by removing the
ability to edit. The operator wants both: editable rules, and updates that can't
destroy edits.

A custom repo add-on is the same problem in a stronger form. Its rule set shares
nothing with the bundled one, so it is a "replace every rule" update.

## Facts the design rests on (observed live, Claude Code 2.1.300, `claude -p`)

- Claude Code loads `.md` files from subfolders of `~/.claude/rules/`. A rule at
  `~/.claude/rules/sub/x.md` was seen.
- `~/.claude/rules` is read **before** SessionStart hooks run. A rule the hook wrote
  was invisible in that session and visible in the next.

Both facts come from one run each, and both runs reached the same conclusion. They are
not yet checked on macOS or in the desktop app.

## Base plugin `shared-rules` (submitted to the directory)

1. **Home.** The plugin keeps its rules in `~/.claude/rules/shared-rules/`, where Claude
   Code loads them natively and the user can edit them.
   - **First install, folder already exists and isn't ours.** Claude asks the user to
     either use it, which backs up what is there and then installs (handled like an
     update), or install into `~/.claude/rules/shared-rules-plugin/` instead.
   - **Ownership marker.** The folder carries `.shared-rules.json`. It records the
     installed plugin version and the sha256 of every file the plugin wrote, which is
     how later runs know the folder is ours.
2. **Session start.**
   - If the folder is current, the hook prints nothing, because Claude Code has already
     loaded the rules natively.
   - If the hook writes or changes files this session (first install, or an approved
     update), it prints exactly those files once. They are not loaded yet this session.
   - Cloud sessions start with an empty HOME every time, so they hit the first-install
     path on each start: the hook installs and prints every session, which is the
     behaviour they have today.
3. **A new plugin version arrives** (a manual update or an auto-update).
   - The hook compares the folder with the record in the marker:
     - **pristine:** every file matches what the plugin wrote;
     - **modified:** some file's hash differs;
     - **added:** some file is not in the record;
     - **deleted:** the user removed a file the plugin wrote.
   - **Nice-to-have, included:** a file whose hash matches any version the plugin ever
     shipped counts as pristine, not modified. The plugin ships `rules-history.txt`,
     listing the sha256 of every rule file across all releases.
   - **Consent gate.** Claude tells the user about the update and offers two choices:
     - **Keep yours:** nothing changes. The plugin keeps running the old rules and asks
       again at the next plugin version.
     - **Back up and update:** every modified or added file moves to a backup folder,
       then the new version is installed exactly. The default backup folder is
       `~/.claude/shared-rules-backups/<date-time>/`. It sits outside `~/.claude/rules`,
       so backed-up rules don't load, and not in `/tmp`, so it survives. The user can
       name another folder.
   - Approval runs one command, pinned to the exact plugin version, the same way the
     current approve command is.
4. **No network, ever.** Everything comes from inside the plugin, so this stays clear of
   directory policy 2F.

## Add-on `shared-rules-custom-repo` (self-hosted marketplace only)

- It declares `dependencies: ["shared-rules"]`, so installing it installs the base
  plugin. This is the documented behaviour for a dependency in the same marketplace.
- It clones the user's repo into `~/.claude/rules/shared-rules-custom-repo/`. Rules load
  natively; the hook prints them only on the session that wrote them.
- `ask` / `auto` keep their current meaning for changes upstream. The ask-mode approval
  command stays pinned to a sha.
- **First session, one question:** keep both sets, or replace the bundled set.
  - **Replace** means: back up the base folder (same backup rule as above), then write
    `~/.claude/rules/.shared-rules-replaced`. The base hook honours that marker and stops
    installing.
  - The marker is the only thing the base plugin knows about the add-on: a plain
    "the user switched me off" flag, with no fetch logic.
- Pointing the add-on at this repo itself makes it say so and stop. The base plugin
  already has those rules.

## What this retires

- **The separate local install** (`git clone` into `~/.claude/rules/shared` plus
  `local-update.sh`). The base plugin now places the rules in the same kind of folder,
  and the add-on covers "my own repo".
- **Slicing the output across six hooks.** Printing happens only when files are written,
  and on a local machine that is once per update. Cloud sessions still print the whole
  set every session, so the size limit still matters there. Slicing stays, but only for
  that path.

## Decisions (operator, 2026-10-16)

- **Pristine folder + new version:** apply silently; Claude mentions once what changed.
- **"Keep yours":** declines this version's rule changes entirely - the folder stays exactly
  as it is. The notice must say plainly that this is a refusal to update the rules at all,
  and that everything else in the plugin's update (fixes to its own scripts) still applies.
  Asked again at the next plugin version.
- **User changes count as:** modified files, added files, and deleted plugin files.
  Added files are moved out too: the folder holds only the plugin's own rules.
- **Separate local install:** retired.

## Verification plan (pre-registered before building)

- **Unit tests** for each state: fresh install, pristine update, modified, added,
  deleted, matches an older version, keep yours, back up and update, existing folder at
  first install, replace marker.
- **Live CLI** (`tests/live/`):
  - the install, update and approve loop across two real sessions;
  - user scope, and project or local scope;
  - Sonnet and Opus for the consent scenarios.
