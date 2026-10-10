# A falsification station at every hand-off

When work passes from one producer to the next — a design doc distilling raw
material, an asset transcribing a design, a rubric restating ground truth, a report
summarizing runs, a comment summarizing a report, a briefing feeding a fresh session
— put an explicit check **against the original source at that hand-off**, not only
against the immediately preceding step. Every transform in a chain gets its own
station that re-reads the source it claims to represent.

## Why

Drift hides at the hand-off with no reviewer. Each link in a chain is normally checked
only against its neighbor, so an error introduced two links back rides through every
later check and reads as clean — and nothing compiles prose, so nothing catches it
except looking at the source.

Observed cases, each invisible one link up:

- A rubric credited a figure to "the claim-by-claim verification" when the figure
  actually lived in a different document three hand-offs upstream; every intermediate
  doc matched its predecessor.
- A briefing merged two distinct decisions into one name; checking against both
  source docs recovered both.
- A design doc said "use the **five** prompts"; the raw log had five, but only **four**
  pre-dated the moment being replayed — following the digest would have leaked
  held-out material.

## How to apply

- At each hand-off, name the **source of truth** for that step and check the output
  against *it*, not just against the previous summary. "Read it in full" beats "trust
  the digest" whenever the digest is load-bearing.
- The cheapest station is a **fresh reader with no stake in the prior conclusion** —
  typically a fresh-context subagent told to verify against the original and report
  contradictions, not to re-derive the conclusion.
- A station reports **per claim**: confirmed-verbatim / confirmed-paraphrase (with the
  actual text) / not-found. "Roughly checks out" is not a station result.
- Scale ceremony to the cost of being wrong: anything that ships or gates a decision
  always earns a station; a scratch note does not.

## Siblings

`verify-delegated-work-against-artifacts.md` covers a delegated agent's
**self-report**. This rule is the general seam discipline: **any** producer-to-producer
transfer, including doc-to-doc summarization where no agent is reporting on itself.
