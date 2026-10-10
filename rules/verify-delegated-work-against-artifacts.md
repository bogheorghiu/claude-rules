# Verify a delegated agent's work against artifacts, not its self-report

When you delegate to a subagent, a headless run, or an orchestrator, judge what it did
by the **artifacts it changed** (file contents, mtimes) and its **timestamped
transcript** — never by its own account of what it did.

**Why.** An agent's self-narration is generated text, not a log. It can be
confidently, specifically wrong about its own history, and it arrives already shaped
as a conclusion — so it propagates unchallenged. Observed case: a delegated agent sent
an unprompted "correction" claiming it had finished its work *before* the resume that
un-stuck it; the transcript timestamps showed every edit ran *after* the resume. The
confident self-report was wrong; the artifact record was right. Nothing compiles an
agent's prose, so nothing catches this except looking.

**How to apply.**
- Check the **files:** do the claimed changes exist, exactly once (not duplicated by a
  redundant re-run), with mtimes consistent with the claimed sequence?
- Check the **transcript:** tool-use entries and their timestamps are the
  authoritative record of what ran and when. Edit/Write calls are ground truth for
  "did it actually change anything."
- **A transcript can lag its work** — reading it mid-run may show a stale snapshot
  ("no edits yet" can mean "not yet flushed"). Re-check the artifacts before
  concluding either way.
- Verify the **model** actually used (the model field per turn), not the spawn
  parameter — a subagent can silently run on a different model than requested.
- Applies to relaying too: if you already told someone something from an agent's
  self-report and the artifacts contradict it, correct it explicitly.

**Siblings.** `falsification-station-per-handoff.md` is the general seam discipline
this instantiates for the case where the producer reports on itself.
