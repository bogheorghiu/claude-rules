# Reuse before writing — climb the ladder before adding code

**The failure mode.** New code for a job the codebase, the standard library or an
installed dependency already does. A session writes a helper because, for it, writing
is cheaper than searching. The duplicate then drifts from the original, grows its own
bugs, and doubles what the next reader has to understand.

**The test, before writing anything new:** take the first rung that fully works.

1. **The codebase already does it?** Use that helper or pattern, the way the
   surrounding code uses it.
2. **The standard library or the platform does it?** Use it, unless the project has its
   own house version, which wins.
3. **A dependency already installed does it?** Use it. A *new* dependency added for a
   few lines fails this test.
4. **Only then:** the least new code that works.

Whether the thing should exist at all comes before rung 1 and is
`no-speculative-structure.md`'s job, so it is not repeated here.

**Boundary — lazy about the solution, never about the change.** A small solution still
has to reach everywhere the change must reach: callers, tests, fixtures, config. Before
changing a shared function, find its callers and fix the root cause once in the shared
code, not once per caller. A short diff that leaves a caller broken is not small; it is
incomplete. This is the failure a short-diff habit actually produces. In a
pre-registered 60-run test of rulesets like this one, the only failed check was a change
that worked where it was made and missed a second place it had to reach: code elsewhere
that copied the files the new behaviour depended on. Findings:
[ex-cog-dev `docs/integration/ponytail-ab-findings-2026-10-15.md`](https://github.com/bogheorghiu/ex-cog-dev/blob/main/docs/integration/ponytail-ab-findings-2026-10-15.md).

**Lineage.** The ladder is adapted, in these words, from the `ponytail` plugin's
ruleset ([DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail), MIT). The
anti-pattern it targets has an established name: *Not Invented Here*. The plugin's other
rules are either covered by this repo's siblings, or, in the test above, happened
without any rule (adding tests, naming what was skipped), so they are left out.

**Siblings:** `no-speculative-structure.md` decides whether to build at all;
`no-drive-by-edits.md` keeps the diff to what was asked; this rule decides what to build
it *from*.
