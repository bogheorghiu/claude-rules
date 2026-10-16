#!/bin/bash
# SessionStart slice 3 of 6. The directory's validator accepts a hook command only as a
# literal script path with no arguments, so each slice gets its own entry point.
exec "${CLAUDE_PLUGIN_ROOT}/hooks/sync-rules.sh" part 3 6
