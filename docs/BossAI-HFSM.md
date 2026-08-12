# Boss NPC HFSM — Concept, Wants, and Implementation Reasoning
### Companion to `Architecture-Reference.md` and `Gameplay-Design.md`

> **This document is not a source of truth. Nothing in it is hardwritten.**
> It holds reasoning, not commitments — the *why* behind a design choice and
> the alternatives rejected, so a future revision doesn't re-derive them from
> scratch or mistake "we thought about this once" for "this is settled."
>
> Everything here is **conceptual, unbuilt, and unverified against real
> code.** Treat every concrete shape below (field names, table layouts,
> function signatures) as illustrative of the *reasoning*, not as an
> interface to code against.
>
> **Read Part 7 first if you are about to build something.** It names the
> small subset of this document the first boss actually needs. The rest is
> for boss number six.
>
> **Status tags, same convention as the Architecture Reference:**
> - **CONCEPT** — an idea, not yet a design.
> - **WANT** — a gameplay requirement, stated as "the system must be able to
>   express X." Not a mechanism, and not a checklist.
> - **REASONED, UNBUILT** — a design with real justification behind it,
>   including alternatives rejected, but zero code exists.
> - **SETTLED (CONCEPTUALLY)** — pressure-tested enough that it should not be
>   re-litigated without a new argument. Still unbuilt.
> - **OPEN QUESTION** — flagged, not decided. Do not infer an answer from how
>   confidently a nearby paragraph is written.

---

## Revision History — What Changed and Why

Kept because the *pattern* in these changes is more valuable than any one of
them: three separate times, a formally correct abstraction failed to survive
contact with the specific mechanics of this game. Recognising that shape
again later is worth more than the individual conclusions.

| Change | Why |
|---|---|
| **Interrupt stack — removed** | Nothing in this design resumes. Asking "what would a resumed mid-swing look like on screen" collapsed the premise |
| **Perception queue — removed** | Every mechanic here is an accumulator, and accumulators commute. Nothing needs ordering or buffering |
| **Observation/Interrupt event kinds — removed** | Collapsed into transition priority plus ordinary guards, which already do the same job |
| **Stagger — moved to a Resource** | It is a number that fills, has a ceiling, and fires at the ceiling. That is `ShieldHits` exactly |
| **Telegraph framing — corrected** | It exists for combat readability. Latency compensation is a consequence, not the purpose |

---

## Table of Contents

1. Concept — What Kind of Machine Is This
2. Wants — What the Gameplay Design Asks For
3. Data Structures — What Survived, and What Didn't
4. Implementation Reasoning
5. Combat Reaction States — Stagger, Flinch, Channel-Interrupt, Recovery, Feint
6. Integration — Where This Actually Plugs In
7. **What the First Boss Actually Needs**
8. Open Questions
9. Quick Reference

---

## Part 1 — Concept: What Kind of Machine Is This

> **Status: SETTLED (CONCEPTUALLY).** Terminology matters here the same way
> it mattered for "Event" in `Architecture-Reference.md` Part 4 — getting the
> model wrong early produces designs that fight the wrong abstraction later.

### It is not a DFA

A classical Deterministic Finite Automaton is a **language acceptor**: it
consumes a finite string of symbols and only at the *end* asks "did we land
in an accept state?" Acceptance is a property of the whole string, checked
once, at termination.

A boss has no string and doesn't terminate mid-fight — it's a long-running
process producing continuous behaviour until it dies. There's no end-of-input
moment to check against. So "accept state = trigger the attack" is the wrong
shape, even though it's the intuitive first guess.

### It is a statechart

The right formal model is an FSM with **no accept states**, where output
attaches either to:

- **Moore-style** — the *state*. "While in `ATTACKING`, deal damage this
  frame." Output = f(state).
- **Mealy-style** — the *transition*. "The instant `TELEGRAPHING` →
  `ATTACKING`, fire the hit." Output = f(state, input).

This system uses both. `onEnter`/`onUpdate`/`onExit` is Moore-style; "do a
thing on this specific transition" is Mealy-style. No state is terminal;
"the attack happens" isn't a distinguished endpoint, it's simply what
`ATTACKING` *does* while active.

Once continuous live-sampled input (distance, HP%, cooldowns, stagger,
per-player memory), **hierarchy** (phase FSM containing a move FSM), and
**concurrency** (an Action machine and a Spatial machine running
independently) enter the picture, the accurate name is a **statechart**
(Harel) — the standard term for hierarchical, concurrent, guard-driven
reactive state machines. Worth knowing, because it means none of this is
being invented: it's a well-studied model with known vocabulary and known
failure modes.

### Two kinds of composition — both needed, not interchangeable

The single most important conceptual distinction here, and easy to collapse
by accident:

| | OR-composition (hierarchical) | AND-composition (orthogonal) |
|---|---|---|
| Meaning | exactly **one** substate active | **multiple** machines active **simultaneously** |
| Example | Phase 2 *contains* one of {Telegraphing, Attacking, Recovery} | Action (Telegraphing) **and** Spatial (Circling) at once |
| Failure if confused | — | state explosion: `TELEGRAPHING_WHILE_CIRCLING`, `TELEGRAPHING_WHILE_RETREATING`… |

State explosion is the real reason flat FSMs get a bad reputation. It isn't
inherent to FSMs — it happens specifically when independent concerns get
flattened into one state list instead of factored into separate machines
reading a shared data source.

### What this buys over the naive version

The Roblox-tutorial version is one conditional —
`if distance > range then moveTo(player) else attack() end`. It ships, it
"works," and it's why a large fraction of Roblox NPCs walk straight at you
and spam one attack: nothing in that loop can express telegraphing,
interruption, memory, or independent concerns.

Every piece of structure below exists because a specific gameplay want
(Part 2) can't be expressed cleanly without it. Where that stopped being
true, the structure was removed — see Part 3.

---

## Part 2 — Wants

> **Status: WANT.** Pulled from `Gameplay-Design.md` and design discussion.
>
> **These are numbered for reference, not as a checklist.** They are things
> worth being able to express eventually, not a definition of done. Part 7
> names the four that actually gate a first boss. Building against this whole
> list before anything moves would be the exact failure
> `Architecture-Reference.md` Part 2 warns about.

### Combat and mitigation

- **W-1 — Attack category gating.** Attacks are tagged by category
  (physical-light, physical-heavy, magical, void), and category determines
  which player classes can mitigate them.
- **W-2 — Boss-side reactive mitigation.** The boss can redirect an incoming
  magical attack and parry an incoming physical one. Triggered by the
  *player's* action, not the boss's decision cycle.
- **W-3 — Stagger as a shared meter.** All damage feeds one meter, with
  mitigation successes contributing more. Crossing its threshold is a
  legitimate phase-transition trigger alongside HP thresholds and part-breaks.
- **W-4 — Differentiated stagger reactions.** Selected by which limb/weapon
  attacked and which angular sector the parrier stood in.
- **W-18 — Stagger is a hard reset, never a resume.** A staggered boss is
  fully downed for a real duration; afterwards it decides fresh. Whatever it
  was mid-performing is gone, not paused.

### Phases and sequences

- **W-5 — Multiple trigger sources for one transition type.** HP threshold,
  stagger fill, or part-break can all fire the same non-failable cinematic.
- **W-6 — A way to suspend normal AI.** Cutscenes and cinematics take over,
  then hand control back. *Resolved: this is a supervisor mode, not a state
  inside each machine — see 4.3.*
- **W-7 — Failable vs. non-failable variants of one mechanism.**
- **W-8 — Per-part health**, not just aggregate HP.

### Memory and adaptation

- **W-9 — Per-player, per-fight memory.** Parry frequency, dodge bias,
  damage types — tracked per player independently.
- **W-10 — Threshold-gated reveals**, with a global cooldown and a per-type
  cooldown layered on top.
- **W-11 — Target selection among eligible players**, reusing the same
  scoring mechanism as attack selection.
- **W-12 — Exploit-resistant awareness.** LoS "forgetting" needs a
  monotonic, fight-long abuse counter distinct from the resettable
  currently-searching timer.
- **W-13 — Ratio-based, reversible mode switching**, with two thresholds so
  it isn't a one-way ratchet.

### Multi-entity

- **W-14 — Cross-entity influence by shared fact only.** A pet's ability or
  another boss's state can influence decisions by writing a fact — never by
  forcing a transition.
- **W-15 — Entity-agnostic.** The same harness works whether the target is a
  player or another AI entity.

### Content scoping

- **W-16 — Tiered adoption.** Dungeon bosses use a subset, event bosses the
  full stack. Difference in **profile content**, never in engine code.
- **W-17 — Mutation-safe.** Gauntlet mutations touch stats/element/visuals
  only, never states or transitions.

### Pacing and feel

- **W-19 — A recovery window after attacking**, authored per profile.
- **W-20 — Recovery can grow with a combo streak**, not just a static number.
- **W-21 — Physical scale correlates with pacing.** Small bosses lean fast,
  low-damage, chainable; large bosses slow, high-damage, high-recovery. An
  authored correlation via shared profile fields, not two systems.
- **W-22 — Flinch**: a brief forced reaction distinct from full stagger,
  scoped to certain profiles, gated so it can't fire from committal states,
  and protected against spam by an escalating counter that redirects abuse
  into a punish.
- **W-23 — Channeled casts** where player action degrades progress without
  the boss leaving the casting state.
- **W-24 — Feints.** Telegraph one thing, switch to another. See 5.5 — this
  is one extra edge in the graph, but it carries two real design constraints.

---

## Part 3 — Data Structures: What Survived, and What Didn't

> **Status: REASONED, UNBUILT.**

### 3.1 — The interrupt stack: removed

The first draft proposed a stack of suspended execution contexts so a boss
interrupted mid-action could resume exactly where it left off. A review
correctly noted that if resume is wanted, a stack of *names* is insufficient
— you'd need full execution frames (state + elapsed + target + in-progress
attack), or the resume has nowhere to read progress from.

**That critique was correct, conditional on the premise. The premise was
false.** Walking through the actual mechanics (Part 5) — stagger, flinch,
channeled casts — surfaced that **none of them resume**, once "what would
resuming mid-swing look like on screen" was asked directly. Every real
interrupt here is one of two shapes:

- **A hard reset** (stagger, flinch): the action is abandoned, a forced
  reaction plays, and the boss decides **fresh** afterwards — which might
  coincidentally look similar, but is not a resume.
- **An in-place progress meter** (channeled cast): the boss never leaves the
  state; an external write pushes a value the state already tracks.

Neither needs a stack, a suspend operation, or frames. **Removed, not
deferred.** If a genuinely resumable mechanic is designed later, with a
concrete example driving the shape, the frames version is the right starting
point *then*.

### 3.2 — The perception queue: also removed

The first draft specified a FIFO queue of discrete perception events, and
spent most of its length on *how* to build one — head/tail indices versus
`table.remove(t, 1)`, and whether to adopt a resizable ring buffer.

**All of that was optimising a structure that doesn't need to exist.** The
stated justification was that one-tick-wide events could be missed by a 10Hz
poll. But every candidate event turns out to write to persistent state that
outlives the gap between ticks:

| Event | What it actually does |
|---|---|
| took damage | adds to the stagger meter |
| was parried | increments a counter |
| part broke | sets a flag |
| player dodged left | increments a memory counter |
| target entered range | nothing — distance is sampled fresh each tick |

Every one is an accumulator or a flag. Nothing can be lost, because nothing
is waiting to be consumed — the meter **is** the accumulated result. Two
parries between ticks increment a counter twice.

**And accumulators commute.** `+30` then `+20` lands where `+20` then `+30`
does, so "process in order" is a question that never arises. Ordering matters
only when writes conflict or one depends on another's result, and none here do.

**Replaced with:** plain scalar writes, applied where the triggering thing
resolves. Stagger goes through `ResourceService` (3.4); AI-local counters are
written through a method on `AIService` rather than an outside system poking
a table.

**The named condition that would bring a queue back**, recorded so this is a
decision with a trigger rather than a vague maybe: **a mechanic that needs a
rolling window of individual occurrences rather than a running total.** "Did
three hits land within the last second" genuinely cannot be a counter — you
need each timestamp so old ones can expire off the front as time passes.
That is a sliding window, and a window is a queue.

Note the boundary precisely, because it's finer than it first looks:

| Question | Structure |
|---|---|
| "How long since the last one?" | one timestamp, a subtraction |
| "How many in the last N seconds?" | an actual window |

Nothing in Part 2 asks the second question today.

**Why the queue was proposed at all**, worth recording because the bias
recurs: it's the textbook answer, and for a *general-purpose* AI framework
it's the right one — if you don't know what events will exist, a queue is
correct, because some future case will need ordering and you can't retrofit
it. It's only wrong once the specific mechanics are enumerated. A queue also
*looks* like rigor, and cutting it looks like cutting corners, which is the
same pull that produced the interrupt stack.

Real systems do use them — for crossing thread boundaries, agent-to-agent
messaging, action plans ("move here, *then* attack"), and per-tick budgeting.
None applies: Luau is single-threaded and cooperatively scheduled, bosses
influence each other through shared facts rather than messages, and the
volumes aren't close to needing a budget. Behaviour trees, GOAP and utility
AI — the three dominant shipped approaches — all poll.

**An action queue is a different object, and is not what was cut.** If an
entity ever needs to commit to a chain — strike, reposition, strike again —
that is a *plan*, and a plan genuinely cannot collapse into a number.

| | Perception queue (removed) | Action queue |
|---|---|---|
| Holds | stimuli that arrived | steps you intend to take |
| Filled by | the world | the agent itself |
| Why order matters | it doesn't — accumulators commute | the plan **is** the order |

`Architecture-Reference.md` Part 7 already gives `AIState` a `queued next
move` field, which is an action queue of depth one. If a boss needs a
three-step chain, that field grows into a small list on the acting entity.
Nothing to do with this section.

**Commands between entities are facts, not messages.** A boss directing
minions writes `facts.commandedTarget`; each minion reads it on its own tick.
Nothing queues, nothing is missed, and a minion that spawns *later* picks up
the current order — which a mailbox would get wrong, since a message sent
before you existed isn't in it. When a fast commander outpaces a slow
minion's tick, the minion sees only the latest order, and that is correct:
losing a stale order is the wanted behaviour, where a queue would faithfully
send a minion diving at something the commander already changed its mind
about.

### 3.3 — The transition graph

**What it's for:** per state, which states it can legally transition to and
under what condition.

**Formally:** nodes are states, edges are transitions. **Directed** (an edge
one way implies nothing about the reverse), **deliberately cyclic**
(`IDLE → TELEGRAPHING → ATTACKING → RECOVERY → IDLE` is a necessary cycle,
which is what distinguishes this from a DAG), and **sparse** (2–4 outgoing
edges per state, not any-to-any).

**Adjacency list, not matrix:** a matrix is `numStates × numStates`
regardless of how many edges exist — mostly waste on a sparse graph.

```lua
local transitions = {
    TELEGRAPHING = {
        { to = "ATTACKING", priority = 0, guard = function(bb) return bb.telegraphTimer >= bb.telegraphDuration end },
    },
}
```

`transitions["TELEGRAPHING"]` **is** the adjacency list for that node. No
Graph class needed for storage; a module earns its keep once there's real
behaviour beyond storage — transition priority (4.4), and boot-time
validation that every `to` resolves to a declared state, matching the
discipline `EventRoutingRegistry.resolveRoutes` and `SignalService.validate`
already establish.

**Rejected — adjacency matrix:** sparsity. **Rejected — a flat decision tree
re-evaluated from scratch every tick, with no persistent current state:**
discards the thing that makes an FSM cheap and legible, namely that the
current state narrows what's even under consideration.

### 3.4 — The blackboard: Facts and Runtime

The first draft used one undifferentiated map holding HP, stagger, per-part
health, per-player memory, cooldowns, awareness, external influences, *and*
execution data like timers.

Once many systems read and write one shared table with no ownership
discipline, it becomes a message bus by accident — the hidden coupling
`Architecture-Reference.md` Part 11's Fact model exists to prevent,
reappearing by a different route.

```
AI Facts (what the boss knows about the world)
├── Perception          -- distance, LoS, target position
├── Combat facts        -- HP%, per-part health
├── Memory              -- per-player behavioural counters (W-9)
└── External influence  -- pet marks, ally-boss state (W-14), written only

AI Runtime (what the machine is doing)
├── Current state per orthogonal region
├── Timers              -- telegraph elapsed, recovery duration, cast progress
├── Cooldowns           -- last flinch, last reveal
└── Streak counters     -- combo streak (W-20), flinch-abuse count (W-22)
```

**Facts are true about the world regardless of what the FSM is doing.
Runtime is the FSM's own bookkeeping.** A guard reads both; only the machine
owning a Runtime value writes it.

**Cross-entity writes are scoped to Facts, specifically External Influence —
never Runtime.** That's a structural enforcement of W-14 rather than a
convention: an outside system has no reason to touch Runtime, because nothing
in Runtime means anything to anyone but the owning machine.

**Runtime largely already exists.** `Architecture-Reference.md` Part 7
declares an `AIState` component holding FSM state, queued next move, aggro
target, and last-move timestamp. That is this half of the blackboard, already
specified — reconcile with it rather than building a parallel store.

**Perception has an owner now too.** Distance and position come from
`SpatialService` (`HitDetection.md`), which did not exist when this document
was first drafted.

### 3.5 — Stagger is a Resource, not a blackboard field

The meter is a number that accumulates, has a ceiling, and triggers something
at the ceiling. `Architecture-Reference.md` Part 8 already made this exact
call once: "there is deliberately no separate shield component — the
Attack-Based Shield's remaining hit count lives in `resources["ShieldHits"]`."

Stagger is the same shape, so it lives in `resources["Stagger"]` and goes
through `ResourceService`. That buys the single-door discipline, the existing
add/drain API, ceiling handling and the dirty set — instead of `CombatService`
reaching into a boss's AI internals to poke a number.

**The test for which store something belongs in: does anything outside the AI
read or write it?**

| Value | Outside readers/writers | Home |
|---|---|---|
| Stagger meter | CombatService writes, phases read, HUD displays | `Resources` |
| Per-part health (W-8) | CombatService writes, phases read | `Resources` |
| Combo streak (W-20) | none | Runtime blackboard |
| Flinch count (W-22) | written via an AIService method, read by nothing else | Runtime blackboard |

---

## Part 4 — Implementation Reasoning

> **Status: REASONED, UNBUILT.**

### 4.1 — Transition priority (W-3, W-18, W-22 depend on this)

With stagger and flinch designed as forced transitions that preempt whatever
the Action machine is doing, array position can't be an implicit priority
system. Every edge carries an explicit priority, evaluated in priority order,
not declaration order:

```lua
transitions.TELEGRAPHING = {
    { to = "DOWNED",    priority = TIER_FORCED, guard = staggerThresholdCrossed },
    { to = "FLINCH",    priority = TIER_FORCED, guard = flinchThresholdCrossed },
    { to = "ATTACKING", priority = TIER_NORMAL, guard = telegraphComplete },
}
```

A small number of **named tiers** reads better than an open integer range —
forced reactions outrank normal decision flow, and that's most of what's
needed.

### 4.2 — Tick pipeline and snapshot-per-tick (settled)

Multiplayer combat produces genuinely asynchronous damage events. Letting
different guards within one tick see different underlying reality (one reads
HP at 30%, a hit lands mid-tick, the next reads 20%) would undermine the
determinism discipline the rest of combat commits to.

```
1. Refresh this tick's Facts snapshot — one coherent view, frozen for the tick
2. Evaluate each orthogonal machine's transitions against the snapshot,
   in priority order
3. Apply state changes (onExit / onEnter)
4. Execute this tick's outputs (movement, damage, telegraphs)
```

The non-negotiable property is that **the decision phase operates against one
frozen snapshot**, never a live mutating view.

**Note what's absent:** the first draft had a queue-drain step and a separate
interrupt-application step ahead of normal evaluation. Both are gone. Forced
transitions fire through priority (4.1) against guards reading the snapshot,
which produces identical latency — an interrupt is still only processed *at*
a tick, so it never beat polling by more than ordering within one pass, and
priority already orders within a pass.

Edge-versus-level detection, the one thing the event classification genuinely
bought, is a boolean: `staggerAlreadyFired`.

### 4.3 — Sequence suspension: supervisor mode, not a per-machine state (W-6)

The first draft put a `SUSPENDED` state inside Action, Spatial and Awareness
individually — precisely the OR/AND-composition mistake Part 1 warns about,
committed at the meta level. "Am I ticking at all" is not a behavioural state
any one machine should hold; it's a fact about whether the machine runs,
owned by something above all three.

```
Boss Controller
      │
 ┌────┴────┐
NORMAL   SEQUENCE
 │         │
 ├─Action  │
 ├─Spatial └── Sequence Engine (Gameplay-Design.md, interactive sequences)
 └─Awareness
```

In `NORMAL` the supervisor ticks the three machines. In `SEQUENCE` it simply
doesn't call them — no transitions anywhere, they're just not ticked — while
the sequence engine drives the boss. On completion, whichever states they
were in are still current, so "resume" is nothing more than "start ticking
again," which is a far more honest description than a shared `SUSPENDED` node.

This also houses death, despawn and forced-encounter-start without polluting
the behavioural graphs with states that aren't about behaviour.

### 4.4 — Cross-machine coupling via derived facts

If Action, Spatial and Awareness read each other's raw current-state values,
the three stop being independently reasonable — understanding one requires
understanding all three, and renaming an Action state silently breaks
Spatial's guards.

```
Action, entering an uninterruptible windup:   facts.isMovementLocked = true
Spatial's RETREAT guard reads:                facts.isMovementLocked
```

Action decides what it wants to communicate and publishes exactly that;
Spatial depends on a small stable contract rather than Action's internals.

### 4.5 — Candidate generation → hard filter → scoring → selection

Blending legality and preference into one number (a cooldown-blocked attack
getting a large negative weight alongside genuine preference weights) is a
path to unreadable weight tables. Four explicit stages:

```
1. Candidates  — every attack or target this decision could consider
2. Hard filter — remove what is illegal outright (on cooldown, wrong category
                 for this phase, target dead). Binary, never scored
3. Scoring     — only survivors get weighed, purely on preference
                 (W-1 category fit, W-9/W-10 memory bonuses, W-11 priority)
4. Selection   — max, or weighted sample among the top few
```

Identical whether candidates are attacks (W-1) or players (W-11). Legality is
now structurally incapable of being a large negative weight, which is what
keeps the weight table meaningful.

**Start with stages 1, 2 and "pick randomly."** Selection is a swap-in, and
no weight table needs authoring before anything moves.

### 4.6 — Is Awareness actually a machine?

**OPEN.** Action × Spatial genuinely needs AND-composition —
`TELEGRAPHING_WHILE_CIRCLING` is a real explosion. Awareness is less clear.
Its states are roughly aware / searching / lost, and if nothing reads it
except as a boolean and it has no `onUpdate` behaviour of its own, it is a
variable wearing a costume — a `facts.lastSeenAt` timestamp plus a derived
boolean would express the same thing without a third machine.

The test: **does Awareness do something each tick that a timestamp doesn't?**
W-12's monotonic abuse counter is a Facts field either way. Decide when the
first boss with LoS behaviour is authored.

### 4.7 — Watch item: the FSM as a thin shell

A standing concern with no proposed fix: the graph could gradually become
`DECIDING` plus a pile of guards, with all real behaviour living in
configuration rather than in states. No clear test yet for when this has
actually happened. Kept as a watch item rather than a design change.

---

## Part 5 — Combat Reaction States

> **Status: REASONED, UNBUILT.** These were designed by working through
> concrete boss behaviour until the mechanism matched what was wanted, rather
> than starting from an abstract "interrupt" and specialising it. Naming them
> distinctly matters — per `Architecture-Reference.md` Part 4's warning about
> terminology collisions, these are not several names for one thing.

### 5.1 — Stagger (`DOWNED`)

Satisfies W-3, W-18. A boss-wide meter in `resources["Stagger"]` (3.5), filled
by all damage, with mitigation successes contributing more. Crossing the
threshold fires a forced, top-priority transition (4.1) into `DOWNED` from
**any** active state — that's the point of stagger.

`DOWNED` is a real standalone state, not a suspension:

- Duration authored per profile.
- Party-wide vulnerability window, expressed as a `StateService` flag,
  consistent with how `INVULNERABLE` and `DYING` already work.
- Boss's own reactive mitigation (W-2) suppressed for the duration —
  otherwise the free damage window isn't free.
- **On exit: `DECIDING`, never back to what was interrupted.** The attack in
  progress is gone. What happens next is a fresh decision (4.5) that might
  coincidentally choose the same attack.
- Cannot re-trigger while already `DOWNED` — excluded from stagger's legal
  source states.

### 5.2 — Flinch

Satisfies W-22. A second, smaller meter, scoped to a profile flag (not every
boss has one), fed specifically by **unmitigated heavy hits** — hits that got
past the boss's own parry/redirect, which ties it to W-2 resolving first.

- **State-gated.** Only a legal edge from a declared subset of states — not
  `ATTACKING`, not `DOWNED`, probably not `CASTING`. This is what avoids the
  "snaps back mid-swing" problem: by firing only from non-committal states,
  there's never a mid-animation pose to resume from.
- **Cooldown-gated**, a `lastFlinchAt` timestamp, same shape as W-10's reveal
  cooldown.
- **Abuse-escalation guard**, same shape as W-12's LoS guard: a monotonic
  flinch counter. Crossing a higher threshold redirects the transition to
  `COUNTER_PUNISH` instead — the boss parries or grabs, punishing the spam
  rather than granting free value. **This is the second time this exact guard
  shape has been needed (W-12, now W-22)**, which is decent evidence it's a
  reusable pattern rather than a patch. Worth naming if a third appears.
- Exit: `DECIDING`, same as stagger. Shorter, and possibly without a
  vulnerability window at all (Part 8).

### 5.3 — Channel-interrupt (casting)

Satisfies W-23. Structurally the simplest, and deliberately **not** a
transition mechanism — the boss stays in `CASTING` throughout. One progress
value, two writers:

```
CASTING.onEnter:  castProgress = 0

CASTING.onUpdate(dt):
    castProgress += dt * castRate
    if castProgress >= castThreshold then → SMITE        -- completes
    if timeInState   >= hardCap        then → CAST_FAILED -- times out

CASTING.onQualifyingMitigation:
    castRate *= interruptPenalty     -- or castProgress -= flatAmount
```

No stack, no forced transition — only two ordinary guarded exits. `CAST_FAILED`
is likely its own small state with a brief, lesser vulnerability window: a
smaller reward for denying the cast, distinct from stagger's full punish.

Precedent worth naming: this is the MMO interrupt-bar pattern, which is strong
evidence the shape lands **when the meter is visible to the player.** An
invisible version reads as "my damage sometimes randomly cancels boss casts,"
which loses most of the value.

**Worked example:** the seraph's prayer/smite cast — `PRAYER_CAST` as an
ordinary Action state, entered through the normal scorer like any other move.

### 5.4 — Recovery

Satisfies W-19, W-20, W-21. A state between `ATTACKING` and the next decision:

```
IDLE → TELEGRAPHING → ATTACKING → RECOVERY → DECIDING → (loop)
```

**Two per-profile dials, correlated by archetype but independently authored
(W-21):** `baseRecovery` and `damage`. Small/humanoid bosses lean low on both
(fast, chainable, low-stakes hits); large bosses lean high on both. Authored
correlation via shared fields, not two systems.

**A third, derived dial (W-20):** a combo-streak counter (Runtime side)
increments across consecutive landed hits, and recovery duration is a function
of it:

```
RECOVERY.onEnter:  duration = baseRecovery + comboStreak * recoveryGrowthPerHit
                              -- capped at an authored maximum
RECOVERY.onExit:   comboStreak = 0
```

So the breathing room is *earned by weathering the combo* rather than granted
on a fixed clock.

### 5.5 — Feint (W-24)

Telegraph one attack, switch to another. **Architecturally free** — a feint is
`TELEGRAPHING → SOME_OTHER_STATE` instead of `TELEGRAPHING → ATTACKING`. One
more edge in a graph that already exists, which is decent evidence the shape
is right.

Two constraints that are not free:

**A feint must be legible as a feint.** If telegraphs can lie without a tell,
players stop trusting telegraphs, and the read-the-windup loop the combat is
built on dies. The windup should visibly *abort*, or feints should be rare
enough to read as a surprise rather than noise. A silently unreliable
telegraph is worse than no telegraph.

**The feint window must exceed round-trip latency.** The player sees the
telegraph late, commits, then sees the switch late too. If the gap between
"boss switches" and "new attack lands" is shorter than their ping plus human
reaction time, it isn't a mind game — it's an unavoidable hit that reads as
the game cheating. Budget roughly 250ms plus worst-case RTT. This is one of
the few places where latency constrains a *gameplay* number rather than being
handled underneath it.

### 5.6 — Summon intercept (and why it needs no AI at all)

The player's summon ultimate (`Gameplay-Design.md`) manifests, intercepts the
boss, beats its parry, and knocks it down. It is listed here because it
*produces* a stagger, not because it is a boss reaction.

**It requires no AI whatsoever.** No `AIState`, no graph, no perception, no
target selection — it is a scripted beat with a fixed outcome. Mechanically:
the supervisor (4.3) drops into `SEQUENCE`, the three machines stop ticking,
the sequence engine drives, and on completion the boss is placed in `DOWNED`.

The boss's own mitigation is not consulted, because its AI is not running.
That is what lets the summon come through a parry: there is no parry decision
to make.

**This resolves an open question from the first draft.** `SEQUENCE` mode was
listed as unsure whether machines always resume the state they were in, or
whether a sequence can declare where the boss lands. This case settles it:
**a sequence must be able to declare a post-sequence state.** Summon intercept
ends in `DOWNED`, and a transformation cinematic ends somewhere else entirely.
Default is resume-as-before; an explicit override is available per sequence.

---

## Part 6 — Integration: Where This Actually Plugs In

> **Status: REASONED, UNBUILT.** Absent from the first draft entirely, which
> is why the design floated free of the codebase it's for.

### The tick comes from the Scheduler, through AIService

`AIService` already exists as a stub with a Scheduler row at 10Hz.
`Architecture-Reference.md` Part 14 is explicit that per-creature pacing
(bosses ~10Hz, pets ~4Hz) is a **field on the AI profile**, skipped inside
`AIService:tick` for entities not yet due — not a second Scheduler row.

So 4.2's pipeline runs **per entity, per tick, for entities that are due**.
The Scheduler knows nothing about bosses; `AIService:tick` iterates entities
with an `AIState` component and skips the rest.

### `ATTACKING` is where hit detection runs

The state doesn't just play an animation. At the moment of impact it asks
*who did this swing hit*, which is `TargetResolution` (`HitDetection.md`):

```
volume = the attack's declared hit volume        -- an ARC, from profile data
at     = workspace:GetServerTimeNow()            -- NOT rewound
hits   = TargetResolution.resolve(TargetQuery.new({ attacker = boss, volume, at }))
```

**`at` is the whole point.** A player's swing rewinds, because their click
reached the server late and they're owed what they saw. A boss's swing does
not, because rewinding would retroactively hit a player who visibly dodged.

What makes no-rewind fair is that the player got advance warning — and that
warning is `TELEGRAPHING`. Which means this document independently arrived at
the mechanism that licenses the rule, describing it as a behaviour state
without noting it's also the defender's latency compensation.

**But the telegraph exists for gameplay first.** It's what makes an attack
readable — see the windup, recognise the attack, choose dodge or parry. That
loop works identically in single-player games with zero latency; Dark Souls
and Monster Hunter didn't invent windups for netcode reasons. The latency
benefit is a consequence, not the purpose. (`Architecture-Reference.md`
Part 5 currently over-corrects in the other direction, calling telegraphs
"not decoration, latency compensation." Both are true; the ordering there is
backwards.)

### Profiles are Content Layer, and server-only

`baseRecovery`, `recoveryGrowthPerHit`, `damage`, attack categories, telegraph
durations, hit volumes, decision Hz — all profile data, and it belongs in
`src/serverShared/definitions/`, never `src/shared/`.

Per `Architecture-Reference.md` Part 13, `ReplicatedStorage` is a broadcast:
putting profiles there publishes every boss's exact timings, reach and arcs to
any client that cares to read them. The client needs none of it — it plays an
animation and consumes an outbound diff.

### Entity lookup

Boss entities are found the same way every other entity is. Detection returns
entity tables directly; ids only matter where something crosses the wire.

### Fifty mobs in a room — what is shared and what is per-entity

A dungeon room holding 10–50 mobs needs **no new instances of anything.**
It's the same shared-versus-per-entity split the codebase already uses three
times over:

| Thing | How many | Why |
|---|---|---|
| `AIService` | **one** | it is the engine that ticks; nothing about it is per-entity |
| The transition graph | **one per profile** | Content Layer data, read and never written. Fifty goblins share one |
| `AIState` component | **one per entity** | only this mob's current state name, its timers, its target |

Fifty goblins is one service, one graph table, and fifty small components
holding roughly `{ state = "CHASE", enteredAt = 12.4, target = <entity> }`.

That is `Overlap` (one shared function table) versus `Spatial` (one per
entity), and `EnemyTemplates` (one definition) versus `EnemyEntity` (one per
mob) — the same pattern a third time.

**Trash mobs are the tiered-adoption want (W-16) cashing out.** A goblin
profile declares three states — `IDLE → CHASE → ATTACK` — with no telegraph,
no stagger, no memory, no orthogonal machines. The difference between it and
the seraph is how much profile was written, not which code runs.

**Scope the graph per profile rather than giving every mob the full boss
graph.** Guards would technically no-op on their own — `Resources:get`
returns 0 for an id an entity doesn't have, so a stagger guard reading
`resources:get("Stagger") >= threshold` is simply false forever on a mob with
no Stagger. That mechanism is real and free.

The reason to scope anyway is `Architecture-Reference.md` Part 13's argument
pointed at bugs instead of exploiters: **a goblin that structurally cannot
enter `CASTING` is safer than one that merely shouldn't.** With the full
graph, a bad guard drops a trash mob into a casting state with nothing
configured, and you get a frozen goblin and no error. It also keeps things
readable — debugging a mob whose graph lists twelve states, nine unreachable,
is worse than one with five.

Adding a capability to a mid-tier mob is still a profile edit and no engine
change, which is the property worth protecting. When the same five entries
have been copy-pasted across eight profiles, that is the moment capability
composition (`capabilities = { "MELEE", "STAGGERABLE" }`, each contributing a
known set of states and edges, assembled at boot) earns its keep — not
before, or you are designing a capability system for three profiles.

**A note on which lever expresses "this mob can't do that."** Absence of a
capability is *legality* — it belongs in the hard filter (4.5), or in the
graph simply not containing the edge. It is never a utility score of zero.
Scoring an unavailable ability at 0 makes a weight of 0 mean two different
things ("cannot" and "strongly prefer not to"), which is precisely what the
four-stage split exists to prevent.

### The bottleneck is bodies, not decisions

Worth stating because the intuition usually runs the other way. Fifty mobs
deciding at 4Hz with ~10 guard evaluations each is roughly 2,000 calls per
second — nothing. `SpatialService` sampling 55 entities at 30Hz is nothing.
Fifty simultaneous swings is fifty broadphase scans over ~55 candidates,
which is microseconds.

**The cost is the Roblox instances.** Fifty `Humanoid`s pathfinding is
genuinely heavy, and that is what will cost frames. Same lesson as the
pooling discussion: the Lua side is cheap, the Instance side is where the
expense lives. Trash mobs may not want `Humanoid`s at all — a part with
simple steering toward a target is dramatically cheaper and, for mobs that
mostly walk at you and die, indistinguishable to the player. Worth trying
before assuming fifty is out of reach.

---

## Part 7 — What the First Boss Actually Needs

> **Status: WANT, deliberately minimal.** Read this before building anything
> from the rest of the document.

A numbered list of wants has gravity. Sitting down to write `AIService` with
W-1 through W-24 in view invites building per-player adaptive memory and
channel-interrupt meters before a single boss has walked toward anyone.

**A first boss needs four things:**

1. The loop — `IDLE → TELEGRAPHING → ATTACKING → RECOVERY → DECIDING`.
2. One attack, with a hit volume, resolved through `TargetResolution` at
   `at = GetServerTimeNow()` (Part 6).
3. A way to pick a target — nearest player is enough. Stages 1 and 2 of 4.5,
   then pick.
4. Something that makes it move toward that target.

That's `W-19` plus the skeleton. Everything else — stagger, flinch, casting,
feints, memory, orthogonal machines, the supervisor, priority tiers — waits
until a boss exists that is boring without it.

**The order to add things, when it's time:** stagger before flinch (flinch is
defined by contrast with it), recovery-streak before scale correlation, and
the Spatial machine only when positioning becomes a real behaviour rather than
"walk at the player."

---

## Part 8 — Open Questions

- **Does `FLINCH` open a vulnerability window at all**, or is the interruption
  its entire value, with `DOWNED` the only state granting free damage?
- **Combo-streak counting (5.4):** landed hits only, or also
  attempted-but-mitigated? Landed-only was reasoned as likely right — a
  successful dodge quietly shortens the eventual recovery too — not committed.
- **Channel-interrupt trigger (5.3):** any successful mitigation, or parry
  specifically? Leaning parry-only, to tie it to class identity rather than
  being a generic damage response.
- **`RECOVERY` passivity (5.4):** fully inert, or still reactive to boss-side
  mitigation? Leaning still-reactive — a fully inert state is a dead zone.
- **Is Awareness a machine or a fact (4.6)?**
- **`DECIDING` as a state vs. scoring in `onEnter`** — near-equivalent, not
  committed.
- ~~What `SEQUENCE` mode preserves on exit~~ — **resolved (5.6).** Default is
  resume-as-before; a sequence may declare an explicit post-sequence state.
  Summon intercept ends in `DOWNED`, which is the concrete case that settled it.
- **Do minion deaths feed the boss's stagger meter?** Raised while discussing
  a boss with adds, not answered. If yes, clearing adds is progress toward the
  punish window and the fight has two valid strategies. If no, adds are a pure
  tax and players will resent them. This decides whether the archetype feels
  good, and it is independent of any mechanism above.
- **Guard evaluation cadence** — poll every guard every tick, or only
  re-evaluate when a relevant Fact changed? Likely "poll first, optimise if
  profiling says so."
- **Multi-boss shared-fact coupling beyond the pet case (4.4, W-14).**

---

## Part 9 — Quick Reference

### Wants → mechanism

| Want | Addressed by |
|---|---|
| W-1 Attack category gating | Hard filter stage (4.5), category as legality |
| W-2 Boss-side reactive mitigation | Event-driven state, checked in 5.3, suppressed during `DOWNED` |
| W-3 Stagger as shared trigger | `resources["Stagger"]` (3.5), forced top-priority transition (5.1) |
| W-4 Differentiated stagger reactions | (limb × sector) lookup, generic fallback — see `Gameplay-Design.md` |
| W-5 Multiple triggers, one transition | Phase guards OR across HP / stagger / part-break |
| W-6 Suspending normal AI | Supervisor mode (4.3), not a per-machine state |
| W-7 Failable vs non-failable | `failable` flag on sequence config, same executor |
| W-8 Per-part health | `Resources`, keyed per part (3.5) |
| W-9 Per-player memory | Facts blackboard, keyed per player id |
| W-10 Reveal spam control | Global + per-type cooldown timestamps, Runtime side |
| W-11 Multi-player target selection | Same 4-stage pipeline (4.5), players as candidates |
| W-12 LoS exploit resistance | Resettable instance timer + monotonic fight-long counter |
| W-13 Reversible kite-ratio switching | Ratio on Facts, dual asymmetric thresholds |
| W-14 Cross-entity influence | Facts "External Influence" only, never Runtime (4.4) |
| W-15 Entity-agnostic | No player-specific assumptions in Facts or scorer |
| W-16 Tiered adoption | Profile omits fields; executor unchanged |
| W-17 Mutation-safe | Mutations touch scalar profile fields, never the graph |
| W-18 Stagger is hard reset | `DOWNED` exits to `DECIDING` (5.1) |
| W-19 Tunable recovery | `RECOVERY`, `baseRecovery` per profile (5.4) |
| W-20 Streak-modulated recovery | Combo streak, Runtime side, feeds duration (5.4) |
| W-21 Scale-correlated pacing | Correlated but independent profile dials (5.4) |
| W-22 Flinch | State-gated forced transition, cooldown + escalation (5.2) |
| W-23 Channel-interrupt | In-place progress meter, no state change (5.3) |
| W-24 Feint | One extra edge; legibility and latency constraints (5.5) |

### Structures → why

| Structure | Why | Rejected |
|---|---|---|
| ~~Interrupt stack~~ | **Removed** — nothing resumes (3.1) | Execution frames — correct if resume were needed; it isn't |
| ~~Perception queue~~ | **Removed** — every mechanic is an accumulator, and accumulators commute (3.2) | Head/tail, ring buffer — both optimised a structure that shouldn't exist |
| Transition graph | Sparse, directed, cyclic — adjacency list fits; explicit priority | Matrix (wasteful when sparse); flat re-evaluated tree (no state narrowing) |
| Blackboard | Facts vs Runtime; Runtime reconciles with `AIState` | Single undifferentiated map |
| `resources["Stagger"]` | Same shape as `ShieldHits` — fills, ceiling, fires at ceiling | Ad-hoc blackboard scalar |

### Terminology — do not conflate

| Term | Shape | Resumable? |
|---|---|---|
| **Stagger** (`DOWNED`) | Boss-wide meter, forced transition from any state | No — hard reset to `DECIDING` |
| **Flinch** | Profile-scoped, state-gated, forced from non-committal states only | No — hard reset, shorter |
| **Channel-interrupt** | In-place progress meter inside `CASTING` | N/A — never leaves the state |
| **Recovery** | Ordinary post-attack state, duration modulated by streak | N/A — not an interrupt |
| **Feint** | An alternate edge out of `TELEGRAPHING` | N/A — nothing was interrupted |
