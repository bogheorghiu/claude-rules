# shared-rules-custom-repo

An add-on to `shared-rules` that loads rules from a git repo you choose. Your repo's
`rules/` folder is mirrored into `~/.claude/rules/shared-rules-custom-repo/`, and Claude
Code loads it natively. Installing this add-on also installs `shared-rules`, which it
depends on.

## Install

```
/plugin marketplace add bogheorghiu/claude-rules
/plugin install shared-rules-custom-repo@claude-rules
```

Claude Code asks for two settings when you enable the add-on. Change them later with
`/plugin configure shared-rules-custom-repo@claude-rules`.

- **Rules repository** (required): a git URL. The repo's `rules/` folder is loaded, and
  rules can sit in subfolders.
  - Use a public repo, or a private one your git credentials can already read.
  - Don't put a token in the URL. It would be stored in your settings file in plain
    text. Notices never show it.
- **Rule updates:**
  - `ask` (default): a new or changed rule in your repo waits until you approve that
    exact version in a session.
  - `auto`: changes apply as soon as they are published.
  - Changes outside `rules/` never ask.

## Both sets, or only yours

In its first session the add-on asks whether you want the bundled `shared-rules` set
**and** your repo's rules, or **only yours**.

- **Only yours:** the bundled set's folder moves to
  `~/.claude/shared-rules-backups/<date-time>/` (or a folder you name), and
  `shared-rules` stops installing it.
- **Changing your mind:** ask Claude to keep both. The bundled set comes back from the
  next session.

## Editing

The folder is a mirror of your repo, so edit the repo, not the folder. A change made in
the folder is overwritten by the next update from the repo.

## What it runs, reads and writes

It runs one bash script, `hooks/sync-repo.sh`, at session start.

**Network:** `git clone` / `git fetch` of the repository you set. Nothing else, and no
data is sent anywhere. Each network step is limited to 15 seconds.

**It writes:**
- `~/.claude/rules/shared-rules-custom-repo/`: the mirrored rules, and
  `.custom-repo.manifest` with the mirrored commit.
- The plugin's data folder: a shallow clone of your repo, the session's rendered output,
  your choice of both or only yours, and a lock.
- Only if you choose "only yours": `~/.claude/shared-rules-backups/<date-time>/` and the
  marker `~/.claude/rules/.shared-rules-replaced`.

**Where it works:** Claude Code. Plugins don't run in claude.ai chat.

## Troubleshooting

- **"could not fetch … and nothing is cached":** check the URL. A private repo needs git
  credentials that can read it without a prompt.
- **A pending update keeps showing:** it shows until you approve it. Approving pins the
  exact version shown, so a push made after the notice is never included.

## Support

Issues: <https://github.com/bogheorghiu/claude-rules/issues>. License: MIT.
