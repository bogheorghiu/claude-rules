# Privacy policy: shared-rules

`shared-rules` is a Claude Code plugin that copies a bundled set of rule files into your own
Claude Code rules folder. Everything it does happens on your computer.

## Data it collects

None. The plugin has no telemetry and no analytics, and it makes no network requests.

## What it reads and stores, all on your computer

- **Your rules folder**, `~/.claude/rules/shared-rules/` (or `shared-rules-plugin/` if you
  chose that). It holds the plugin's rule files and a manifest of their hashes, which is how
  the plugin tells your edits from its own text. The folder stays until you delete it,
  including after you uninstall the plugin, because it is yours.
- **Backups**, `~/.claude/shared-rules-backups/<date-time>/`, only when you choose "back up
  and update". They stay until you delete them.
- **The plugin's data folder**, which Claude Code assigns it (`~/.claude/plugins/data/...`).
  It holds the text printed into the current session, your choices (for example "keep
  yours" for a version), and a lock file. Session files are deleted after about two days.
- **Session information from Claude Code**: the session id and how the session started,
  which Claude Code passes to the hook. They are used only to name the session files above
  and to tell a `/compact` apart from a new session.

## Sharing

The plugin sends nothing anywhere. The rules it prints become part of your Claude Code
session, like any other rules file.

## Contact

Questions or concerns: <https://github.com/bogheorghiu/shared-rules/issues>.
