# Pre-register the ship decision before the test that gates it

When a change will be **gated on an empirical test** — a probe battery, an A/B
comparison, a firing check, a benchmark — write the **ship/no-ship criterion down
before running the test**, not after reading the results: a short note stating
"ships iff <observable> clears <bar>", saved somewhere durable ahead of any data.

## Why

Without a criterion fixed in advance, "we shipped it because it felt right after
glancing at the runs" is always available, and a disappointing result gets quietly
reinterpreted into a success. Fixing the criterion *before* the data is what makes a
**null result reportable as a null** — the same p-hacking drift that careful prose
claims guard against, applied to the ship button. Once the goalpost is on disk, no
goalpost motion is available.

## How to apply

- **Before running the gating test**, record: the arms, the endpoint(s) and how each
  is measured (from artifacts and logs, not a model's self-report), the conditions
  that void a run, and the **explicit ship rule**.
- **Any deviation decided after launch is recorded with its reason**, before scoring
  — a mid-flight rescope is legitimate only if it is on record ahead of the data it
  affects.
- **Null on the ship criterion ⇒ it does not ship on that evidence.** Record the
  null and route the change back to design. Do not re-derive a new "success" from the
  same runs.
- Scale the ceremony to the blast radius: a behavior change that reaches other people
  earns a pre-registration; a typo fix does not.

**Lineage.** Standard scientific pre-registration, applied to the decision to ship.
