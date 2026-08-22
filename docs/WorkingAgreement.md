# Working Agreement

### How decisions get justified in this project, and the specific ways that goes wrong

> **This document exists because the same correction was issued five separate
> times across one week, in increasingly blunt terms.** It is short on purpose.
> If nothing else here survives, the first sentence is the one that matters.

---

## The rule

**A thing existing is not an argument for it.**

Code exists because someone typed it. A document says something because someone
wrote it. Neither fact carries any weight about whether the thing is *right*.
**The only thing that justifies a decision is the reasoning behind it** — and
that reasoning has to be reproducible on demand, stated fresh, without pointing
at where it is written down.

Two statements of it, verbatim:

> "Nothing in the docs or the code is an established commandment from god. If
> we see something worth improving, or the justification doesn't hold up, we
> should always look to make it better."

> "You need to seriously stop treating the code — especially the code — and the
> docs as living commandments from god. If it's not justifiable, then it's not
> justifiable from a systems design standpoint."

---

## Why this keeps happening, and the reason is specific

**Most of these documents were written by the assistant.** `HitDetection.md`,
`Hurtboxes.md`, `Timeline.md`, `AssetPipeline.md`, most of `Animation.md`.

So quoting one back as justification is **quoting yourself from a few hours ago
and presenting it as an independent check.** It is circular, it is not an
argument, and it has been caught repeatedly:

> "Are you just quoting the source code again? That's not really a defensible
> position. We should be tailoring the code and documentation after strong,
> well-argued ideas."

**The clearest single instance.** Deriving hurtbox capsules from `part.Size`
was defended by citing the rule in `HitDetection.md`. A grep then showed the
function had **zero callers, including in tests**. The same author had written
both the paragraph and the function, and cited one to defend the other.

---

## The four shapes it takes

### 1. Citing a document as an external authority

Cite a document to help someone **find** something. Never to **settle**
something. If you catch yourself writing *"as HitDetection Part 9
establishes,"* stop and make the argument instead.

### 2. Describing what the code does as though it were designed

> "Hurtboxes are spheres." "Bosses are server-animated." "Split by entity kind."

Each stated flatly. None of them actually decided by anyone — they were what
the code happened to do.

**Before saying "X is always Y," check whether that was *reasoned* or merely
*built*, and say which.**

### 3. Repeating a document's argument without checking it covers the case

The hurtbox section rejected boxes on a separating-axis cost argument, and then
also said "never a capsule" — but that argument does not apply to capsules at
all. Half of it was asserted rather than argued, and it got repeated because it
was written down.

### 4. Claims that were true under conditions nobody recorded

Three reversals in a single day shared this shape:

| Claim | True when | Stopped being true when |
|---|---|---|
| "Hitboxes never need position history" | the hitbox comes from a formula | it comes from an animation |
| "`BAKED` is a motion kind" | — | it was always an *authoring route*, not a runtime behaviour |
| "Hurtbox zones offset from the root" | limb visibility was an open question | the question was answered and nobody revisited |

> **Record what a claim depends on, alongside the claim.** A statement with no
> stated conditions is a statement that will go stale silently.

---

## What to do instead

- **Make the argument from the merits, every time.** Good reasoning survives
  being restated. If it cannot be restated, that is the finding.
- **Read the passage anyway** — but to test whether it still holds, not to win
  with it. Reading is how the parts that *don't* hold up get found.
- **Grep before claiming what the code does.** "Does the code do X" is
  answerable, and is wrong surprisingly often.
- **When a new idea beats what is written, that is a real outcome.** Edit the
  document or log it in `DocDebt.md`. Do not agree in chat and leave the
  document contradicting the decision.
- **Absence from a document is never evidence against a feature.** The game is
  barely built and mechanics get invented mid-conversation. Noting that
  something is undesigned is fine; treating that as a verdict is not.
- **Draw it before trusting it.** The root-anchored hurtbox design survived an
  hour of argument and died the instant it was rendered — it was a mannequin
  riding the player. Where a thing can be *looked at*, looking beats arguing.
  This is why `HitDetection.md` 0.5 makes the coloured overlay a requirement.

---

## The corollary: keep the road not taken

**When a design is replaced, keep the old one with the trigger that would bring
it back.**

> "If we choose one over the other, remember to record our old design, because
> this is a separate path, and if this one fails we have a fall back."

Not a changelog entry — **a live alternative with the condition that revives
it.** The worked example is `HitDetection.md` 9.6: `LIVE` hitboxes are rejected
for client-owned rigs, kept in full with the measurement that decided it, and
carry an explicit trigger — *"an attack whose contact point must adapt at
runtime."*

---

## Two smaller standing rules

**Cite systems by name, not by section number**, in conversation. "The rewind
arithmetic" rather than "Part 6". Section numbers are for finding things in a
file, not for talking.

**Everything written must be readable back.** Code gets delegated, but nothing
should land that cannot be explained line by line on request. A file that works
and cannot be reasoned about is a liability, not progress.

---

## Related

| Document | |
|---|---|
| `NextSteps.md` | what to build next, and the reasoning behind each item |
| `Implementation-Status.md` | what is actually built and what is actually proven |
| `DocDebt.md` | stale spots, code traps, and resolved-do-not-re-derive |
