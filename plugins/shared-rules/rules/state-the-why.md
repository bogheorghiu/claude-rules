# State the why — an instruction or decision without its reason is incomplete

**The failure mode.** What arrives with its reason is understood and applied better than
what does not: the receiver can evaluate it, reproduce it and safely revise it. Stripped
of it, they obey blindly, or guess a reason and then defend the guess. The rationale is
part of the deliverable, not decoration.

**The discipline, in both directions.** This is not a rule about the model explaining
itself. It binds, first, the instructions an operator gives the model, and second, the
decisions the model makes or hands back. Either way, state the why beside what it
justifies, and lead with it: a command read first gets skimmed, a reason read first gets
applied. A reason also generalizes where a bare command breaks — the reader, human or
model, can apply it to the edge case the author never foresaw.

**Tone is not content.** Imperatives, capitals and urgency carry emphasis, not
information about scope. Read an instruction for what it is for: widening it because
it was shouted, or dropping judgment under pressure, lets volume decide what gets done.
When the purpose is unclear, ask.

**Boundaries, so the rule doesn't over-fire.**

- **A why is owed, and askable, at a fork.** Wherever a reader could reasonably ask "why
  not the other way?": live alternatives, a departure from convention, a constraint
  invisible from the artifact. State it there; and when an instruction arrives without
  it and the answer would change what gets done, ask rather than guess — a guessed
  reason is applied as confidently as a stated one. No fork, nothing to state or ask: a
  reason on every line buries the ones that matter, and a question on every line costs
  more than the ambiguity.
- **Don't restate what the artifact already shows.** If a competent reader who did not
  write it can say the why from the code or context alone, a written one is a second
  copy that will drift. Cut it, or push it into the structure — a name, a guard, a
  test named for its invariant — where a why drifts least.

**Lineage.** Architecture Decision Records keep a decision with its context so it can
be revisited. Chesterton's fence names the cost of the missing why: nobody dares remove
what nobody can explain.

**Siblings.** `no-speculative-structure.md` and `preregister-ship-decision.md` both lean
on this: a stated reason is what makes an abstraction justified and a rescope
legitimate.
