# State the why — a decision without its reason is incomplete

**The failure mode.** A choice, instruction or change delivered without its reasoning:
"use X", a constant with no origin, a rule that only commands. The cost lands on whoever
meets it next, who cannot evaluate it, reproduce it or safely revise it — so they obey
blindly, or guess a reason and then defend the guess. The rationale is part of the
deliverable, not decoration.

**The discipline.** Every decision or instruction states its why, beside the thing it
justifies. Lead with the reason: a command read first gets skimmed; a reason read first
gets applied. A directive that carries its reason is a *reasoned* instruction, and
reasons generalize where commands break: the reader, human or model, applies one to the
edge case the author never foresaw. And a reason set beside its claim exposes a mismatch
— a hedge next to confident reasoning, a claim outrunning its evidence — before it
ships; nothing else compiles prose.

**Where the why lives.** In the artifact first — a name, a guard, a test named for its
invariant — then a comment, then a separate document; never nowhere. Each step away
from the thing explained is a step toward drifting from it.

**Boundaries, so the rule doesn't over-fire.**

- **A why is owed at a fork.** Wherever a reader could reasonably ask "why not the
  other way?": live alternatives, a departure from convention, a constraint invisible
  from the artifact. No fork, nothing to state — rationale on every line buries the
  rationale that matters.
- **Don't restate what the artifact already shows.** If a competent reader who did not
  write it can say the why from the code or context alone, a written one is a second
  copy that will drift. Cut it, or push it into the structure.

**Lineage.** Architecture Decision Records: a decision kept with its context so it can
be revisited. Chesterton's fence names the cost of the missing why: nobody dares remove
what nobody can explain. "Comments explain why, not what" is the same rule at line
scope.

**Siblings.** `no-speculative-structure.md` and `preregister-ship-decision.md` both lean
on this: a stated reason is what makes an abstraction justified and a rescope
legitimate.
