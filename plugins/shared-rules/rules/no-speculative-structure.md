# No speculative structure — build the least that fully solves the request

**The failure mode.** Output beyond what was asked: configurability nobody requested,
abstractions for single-use logic, error handling for impossible scenarios, "while
I'm here" features. An LLM session produces this readily because elaboration is cheap
to generate — but the costs land downstream, twice: the reviewer must
reverse-engineer which parts actually answer the request, and the unneeded machinery
then gets maintained forever by people who can't tell it was never needed.

**The test, applied per addition:** does this structure trace to the request — would
the request be *unsolved* without it? If a senior engineer would call it
overcomplicated, simplify before showing it.

**Boundary — scope discipline, not minimalism worship.** When the asked-for change
genuinely needs an abstraction or broader structure, build it — and state why. A
stated reason is exactly what converts "speculative" into "justified"; a bare "keep it
simple" command would wrongly forbid the justified case, which is why this rule
carries its reasons instead.

**Lineage.** The established name is **YAGNI** ("you aren't gonna need it", from
Extreme Programming) — named so the principle is checkable against prior art rather
than reinvented.

**Sibling:** `no-drive-by-edits.md` — the same per-line traceability test applied to
*modifications* instead of *additions*. They fail independently (a session can
over-build without drive-by editing), hence two rules.
