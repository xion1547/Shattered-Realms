# Shattered Realms — Hit Detection

### The Spatial Layer, and the One Question It Answers

> **This document is self-contained on purpose.** `EventTape.md` could defer
> every *why* to Architecture-Reference Part 12, because that Part argued
> EventTape out in full. There is no equivalent Part for hit detection — the
> reference spends four paragraphs promising latency-tolerant hit registration
> and never says how, and nothing else in it touches space at all. So this file
> owns the reasoning **and** the implementation map.
>
> What it does **not** own is the frames it plugs into: the four-phase
> resolution boundary, the client trust model, the Component contract, and the
> Scheduler. Where those apply, this file links. It never restates them — two
> documents holding the same rule drift, and each stays internally consistent
> while disagreeing with the other.
>
> It also does not own **hurtbox authoring**. `Hurtboxes.md` is the working
> manual: studs, `Vector3`, `CFrame`, and the steps to place one by hand. This
> document keeps the *decisions* and the rejected alternatives. That split is
> new, and the previous revision of this file was roughly nine hundred lines
> longer because it tried to do both.

> **REFRAMED 2026-08-21, and this is the third major revision of the hitbox
> half.** The previous revisions were not wrong on their own terms — they were
> answering a question nobody had asked yet. Every version until this one
> assumed **a hitbox is a shape described by typed numbers.** That assumption
> was never attacked because no requirement had tested it.
>
> The requirement that tested it: *the hitbox should come from the animation,
> so that what you see is what hits.* Under that requirement the old model
> buckles in a specific, repeatable place — and it had buckled in the same
> place across several conversations, which is what finally made it visible.
>
> **Part 9 is the new centre of this document.** Everything else is either
> unchanged, compressed, or now downstream of it. Part 16 records what was
> reversed and why, including two rejections in the previous revision that this
> one overturns.

> **Status tags.**
>
> - **BUILT** — exists, has tests, has been run.
> - **DESIGNED** — the shape is decided and the reasoning is recorded.
> - **MEASURED** — an empirical question answered, with the figure and how it
>   was obtained.
> - **OPEN** — a real decision deliberately left unmade, with the trigger for
>   making it.
> - **GAP** — a known hole, named so it is not mistaken for an oversight.

---

## Boundary

| Architecture-Reference owns | This document owns |
|---|---|
| Why validation precedes resolution | Where DETECT sits between them |
| Why the client reports intent only | The one field that amendment adds |
| Why rewind input is server-measured | The rewind arithmetic itself |
| Why Components hold state and Services hold rules | What `Spatial` holds and `SpatialService` decides |
| Why steps mutate a context and nothing else | Why target-finding is not a pipeline |
| The Scheduler contract | The rows it adds, and why ordering is unaffected |

| `Hurtboxes.md` owns | This document owns |
|---|---|
| What a `CFrame` is, and how to place a capsule by hand | Why the capsule was chosen over a box or a sphere |
| The eight-step authoring recipe | The three routes a hurtbox can be authored through |
| The export round trip | Why geometry must live in the model |

| `Animation.md` / `Timeline.md` own | This document owns |
|---|---|
| How a clip is uploaded, registered, and played | How a clip's motion becomes a hitbox path |
| What a Score is and what plays it | What a **beat** means to the server |

---

## Table of Contents

0. **Orientation — Real, Authoring-Only, And Math**
1. What This Layer Is For
2. The Model — Two Volumes, Two Owners
3. DETECT — A Fifth Phase
4. The Spatial Layer — Component and Service
5. The Sampler
6. Lag Compensation — The Arithmetic
7. Hurtboxes — The Decisions
8. `HitVolume` — The Declarative Half
9. **Motion — Where The Transform Comes From**
10. Why There Is No Part
11. `TargetResolution` — The Engine
12. The Trust Amendment
13. The File Map
14. Current State
15. Known Gaps
16. Rejected Designs, And The Reversals
17. Naming

---

## Part 0 — Orientation — Real, Authoring-Only, And Math

**Status:** SETTLED as the vocabulary. Written 2026-08-21 after the same
confusion recurred across an entire day of conversation.

> **Read this first if you are returning to this document.** Every argument
> that went in circles went in circles for one reason: *"is the hitbox a real
> part"* has three different answers depending on which stage you are asking
> about, and none of the earlier revisions said so.

### 0.1 — The three categories

**REAL — actual Instances, alive while the game runs:**

| | |
|---|---|
| The creature's mesh, or its rigid parts | what you see |
| Its `Bone`s or `Motor6D`/`AnimationConstraint` joints | what the animation moves |
| The `Animator` on each rig | what plays clips |
| A hitbox proxy part — **only under `LIVE`** (9.6) | a **ruler**, never a collider |
| Debug overlays | drawings. Nothing is ever tested against them |

**AUTHORING-ONLY — real parts in Studio, gone before the game runs:**

| | |
|---|---|
| Hurtbox parts placed on limbs | read once at spawn, then deleted (Part 7) |
| The hitbox part dragged through a swing | recorded into a path, never shipped (9.4) |

**MATH — numbers, no Instance, ever:**

| | |
|---|---|
| Every hurtbox capsule | anchor + offset + radius + halfHeight |
| Every hit volume | a shape and a transform |
| **The overlap test** | **always, in every design** |
| Position history | ring buffers of `CFrame`s |

### 0.2 — The rule the three categories collapse into

> **You author with real parts. The game runs on numbers.**

**Both volumes. Every time.** A part is an excellent authoring tool — you can
drag it, resize it, and judge it by eye, which a typed number can never be — and
it is impossible as a test mechanism, because **a part only exists *now*** and
this layer's entire job is answering questions about a moment that has passed.

**Roblox collision is never used.** Not `Touched`, not `GetPartsInPart`, not
`Shapecast`. Every hit is our own arithmetic. Where a real part survives to
runtime (`LIVE` only), it supplies *one number* — where the blade is — and that
number then enters the same math as every other route.

### 0.3 — The end-to-end trace, both directions

**A boss wing-slam.** The server owns this rig, so the hitbox is `LIVE` — no
path file, no export step.

```
SPAWN
  clone the boss into Workspace
  read 9 hurtbox parts  ->  9 zones of numbers.  Parts deleted
  SpatialService samples all 9 zones, 30Hz, forever

THE ATTACK
  server plays the clip        <- the server's OWN parts genuinely move
  the score's beats say: live from 0.55s to 0.80s

  each tick at 60Hz while live:
      hitbox   read the welded proxy part's CFrame     REAL PART, as a ruler
      targets  each player's zones, NO REWIND          the telegraph is the
                                                       compensation (Part 6)
      test     capsule vs capsule                      MATH
      dedup    once per activation
```

**A player sword swing.** A client owns this rig, so the hitbox is `PATH`.

```
CLICK
  client plays the swing immediately, optimistically
  sends "I pressed attack"

SERVER
  validate: owns the skill, off cooldown, allowed to act

  each tick at 60Hz across the window:
      hitbox   rootCFrame * lerp(path[11], path[12], 0.4)   MATH. No part
      targets  zones rewound to viewTimeFor(player)         MATH, from history
      test     capsule vs capsule                           MATH
      dedup
```

**Both traces call the identical overlap function and the identical dedup.**
Exactly one line differs, and it is the line marked `hitbox`.

### 0.4 — This is what Souls-likes build

Worth stating because it comes up as a doubt rather than as a question:

| What makes that genre's hit detection good | Us |
|---|---|
| Many capsules per creature, never one envelope | the hitzone list, Part 7 |
| Hit windows tied to animation events | beats, 9.10 |
| Hitbox follows the weapon's real motion | `LIVE` on server rigs, an authored path on client rigs |
| Consistent frame to frame | the 60Hz driver, 9.4.4 |

**The capsule approximation is on both sides of that table.** Nobody runs
per-triangle collision against a deforming mesh, and not for performance
reasons — see 16.2, *"it makes every art change a balance change."*

**The one row we have and they do not:** the attacker and the victim are on
different machines. Rewind (Part 6) is the entire answer to it, and it is the
only part of this architecture that is not borrowed.

### 0.5 — The overlay is not a nicety. It is how this gets verified.

Every claim in this document about *where* a volume is can be checked by
drawing it, and **essentially none of it can be checked by reading numbers.**

> **Requirement, not an aspiration: every volume this layer tests against must
> be drawable in colour, live, behind a `DebugConfig` flag.** Hurtboxes,
> hitboxes, and the path a hitbox travels.

The reason is Part 15's recurring theme — **nearly every failure in this layer
is silent.** A hurtbox anchored to the wrong bone still returns hits. A path
that cuts the corner of an arc still hits things. A stale recording still hits
things. None of them error, none of them fail a test, and all of them are
obvious the instant they are on screen next to the model.

---

## Part 1 — What This Layer Is For

**Status:** SETTLED.

Three things depend on space existing, and none of them work without it:

| Depends on it | What it needs |
|---|---|
| `CombatService:OnAttack` — "is the target in latency-tolerant range" | something to ask |
| Latency-tolerant hit registration | a position history to rewind through |
| Dodge, parry, block, Void | attacks that **occupy space**, so leaving it means something |

The last one is load-bearing. **A dodge that does not move you out of anything
is a button that grants i-frames**, and the design premise — that class choice
matters per fight because attack *categories* gate mitigation — collapses into
a timing minigame with no geometry.

---

## Part 2 — The Model — Two Volumes, Two Owners

**Status:** SETTLED. Unchanged across every revision, and the one part of this
document that has never been attacked successfully.

Fighting games draw a line this project needs. An attack has a **hitbox** — the
volume it fills while swinging. A body has a **hurtbox** — the volume that can
receive one. Different objects, different owners, different schedules.

| | Hitbox | Hurtbox |
|---|---|---|
| Belongs to | an attack | an entity |
| Declared in | the Content Layer, per skill | the `Spatial` component |
| Exists | only during its active window | always |
| Shape | sphere, box, arc, capsule | layered capsules mirroring the rig |
| **Where its position comes from** | **Part 9 — and this is the part that changed** | observed, sampled, stored |

The whole layer answers one question, in the narrowest form available:

> **Given a hitbox, a pose, and a moment in time — which entities' hurtboxes
> were inside it?**

Notice what is *not* in that sentence. Not damage. Not whether the hit counted.
Not parry, block, dodge, or invulnerability.

**DETECT finds bodies. It never decides whether a hit lands.**

That boundary keeps this layer small, and it is not stylistic. Mitigation has a
home: `StateFlags` holds `INVULNERABLE`, and the INTERCEPT phase of
`DamageResolution` owns parry, block, dodge and absorption. If DETECT started
skipping invulnerable entities "as an optimization," mitigation would live in
two places, INTERCEPT's steps would silently never run for those entities, and
the first bug would be a parry that awards no stagger because the parrier was
never returned as a target at all.

**So DETECT returns the dodging player. INTERCEPT decides they dodged.**

---

## Part 3 — DETECT — A Fifth Phase

**Status:** SETTLED. BUILT for the player direction.

Hit detection fits none of the four existing phases, and forcing it into one
breaks something:

- **Not VALIDATE.** Validation is legality — owns the skill, off cooldown,
  allowed to act. Cheap table lookups. Target-finding is the expensive
  operation in the flow and must sit *behind* the cheap checks, so an illegal
  action never pays for it. That is also a security property: the rate limiter
  and the cooldown check both gate the spatial query, in that order.
- **Not RESOLVE.** The pipeline's contract is pure arithmetic on a context.
  Target-finding is a query about the world, and it runs **once per activation**
  while RESOLVE runs **once per target.** Not the same loop.

```
VALIDATE   Service.   Is this legal?               once per activation
DETECT     Service.   Who is inside the volume?    once per activation
RESOLVE    Pipeline.  How much, to this one?       once PER TARGET
COMMIT     Service.   Apply it.                    once per target
ANNOUNCE   Service.   One diff for the whole thing. once per activation
```

`resolveAttack` keeps its single-target signature and becomes the *inner* call
— DETECT produces the set, the Service loops it. `DamageResolution` does not
change, and `AttackContext` never learns what a volume is.

ANNOUNCE stays once per activation. **One swing that hits five mobs is one
outbound diff carrying five entries**, not five messages.

---

## Part 4 — The Spatial Layer — Component and Service

**Status:** BUILT.

The Component holds data; the Service holds rules and is the one door.

### `SpatialComponent`

The first Component that references a Roblox Instance — a departure worth
naming rather than slipping in. The Component contract requires that a
Component's truth be checkable by looking at itself alone, and this one
satisfies it: it can answer "am I anchored, and where" without consulting any
Service, registry, or other entity.

| Holds | Invariant |
|---|---|
| `anchor` — the entity's `BasePart` | reports unanchored rather than erroring when the instance is gone |
| the parts it tracks — the anchor, plus every limb a zone rides | resolved at attach; re-anchoring clears every buffer |
| `times` / `poses` + one pose array per tracked part | fixed length, allocated once, **never grows**. **One shared timeline and cursor** across every part |

**Shape is not here.** `HurtboxComponent` owns the zone list; this owns where
those zones' limbs were, and when. *The test that separates them: does it change
while the game runs?* Shape does not. Position does.

**One timeline, many pose arrays**, because every tracked part is sampled on the
same tick at the same instant. Per-part timestamps and cursors would be eleven
sets of identical numbers plus eleven counters that must never diverge — a class
of bug that cannot exist when there is one.

**The anchor's poses stay a plain field** rather than an entry in the part-keyed
map, for two reasons: it is genuinely privileged (it is what the broadphase
culls against and what an attack's origin is built from), and it has to exist
*before* there is an anchor to key it by — an entity is constructed on join and
its body arrives later. Tests rely on the same property, recording into a bare
component with no Instance anywhere.

**The buffer is preallocated and never reallocates.** Not premature
optimization: this is written by a 30Hz tick for every entity in the world,
forever, and a buffer that grew would be the one piece of the combat path
producing garbage on a fixed schedule.

Two parallel arrays rather than an array of `{t, cf}` tables, for the same
reason — the point of preallocating is to never allocate again, and a table per
sample would defeat it.

### `SpatialService`

Stores nothing. Owns three rules: when to sample, how far to rewind, who is
attached.

```
attach(entity, anchor, zones)         zones REQUIRED -- see below
detach(entity)
tick(dt)                              samples every tracked part, 30Hz
poseAt(entity, t) -> CFrame?          the rewind query
candidatesNear(position, radius, margin)   broadphase
viewTimeFor(player) -> number         the rewound moment
```

**`zones` is required and asserted, not defaulted.** A body attached without a
zone list is simply not hittable, and the assert is what stops that being a
silent outcome. The alternative — falling back to some default capsule — is how
a boss ships with a placeholder shape nobody notices for a month.

**Order matters inside `attach`:** `setAnchor` clears history, so the tracked
limbs are collected and registered *after* it. Reversed, every limb buffer is
wiped immediately after being created, and the only symptom is that rewound
zone lookups quietly return nothing.

**Explicit registration gives a second thing for free: the set of attached
entities *is* the candidate set.** There is no entity registry in this
codebase, and this layer does not need one invented. Anything that can be hit
is, by definition, something that registered a hurtbox.

**Why an authority Service.** Same argument as `StateService`: if every damage
source read `entity.spatial._poses` directly, the first source that forgot to
rewind would make lag compensation mean "compensated for whatever remembered to
compensate." One door, or the guarantee is not a guarantee.

---

## Part 5 — The Sampler

**Status:** BUILT. 30Hz, one Scheduler row.

Every attached entity's `CFrame` is written into its ring buffer thirty times a
second. That is the entire mechanism, and it is what makes the rewind a
**lookup** rather than a simulation.

**`CFrame`s, not positions**, and this matters more than it looks. A capsule
hurtbox leans with the body. A target that has rotated since the attacker saw
it must be reconstructed at the orientation they saw, not merely at the place
they saw. Storing positions would silently make every rewound test wrong for
anything that turns.

**Non-advancing timestamps are ignored rather than asserted.** This runs inside
a `pcall`'d Scheduler tick, so an assert would warn once per frame forever
instead of failing usefully. The binary search in `poseAt` depends on ordering,
so the guard is not optional.

**History from a previous body is not history for this one.** A respawned
character that inherited the old buffer would be rewindable to a position it
never occupied, which is worse than having no history at all. `setAnchor`
clears.

---

## Part 6 — Lag Compensation — The Arithmetic

**Status:** BUILT. One **OPEN** item and one **GAP**, both named in Part 15.

### The two directions are not symmetric

Getting this backwards produces a system that feels worse than no compensation
at all.

**Player attacks an enemy — the active window has already happened.** The
client played its animation optimistically the moment the button was pressed.
By the time the event reaches the server, the frames where that swing was live
are in the past *on the client*. So the server rewinds to when the client saw
them.

**An enemy attacks a player — the active window has not happened anywhere.**
The Telegraph/Execute pattern fires a telegraph, waits ~1.0–1.2s, then
executes. Detection is *scheduled* for the execute moment and runs with **no
rewind at all.** The telegraph **is** the compensation — that is why the
pattern exists — and rewinding on top of it would retroactively hit a player
who visibly dodged in time.

One engine serves both. The only difference is the timestamp handed to it.

### The rewind arithmetic

Derived rather than copied, because the derivation is what makes it checkable.
Let `L` be one-way latency and `I` the client's interpolation delay:

```
server sends snapshot at             T
client receives it at                T + L
client is rendering state from       T − I        (it interpolates)
client presses attack at wall time   T + L
command reaches server at            T + 2L

rewind = (T + 2L) − (T − I) = 2L + I
```

**The rewind is a full round trip plus interpolation, not half of one.** Every
"backtrack by half the ping" implementation is either using a one-way figure or
is under-rewinding.

| Constant | Value | Why |
|---|---|---|
| `INTERPOLATION_CONSTANT` | 0.1s | Roblox character replication is ~20Hz and clients interpolate on top. Two independent open-source implementations converged on this |
| `MAX_REWIND` | 0.5s | Past this a player is hit by something that left their screen half a second ago. Also the exploit ceiling — it bounds what a manipulated latency figure buys |
| `HISTORY_SECONDS` | 1.5s | What is **stored**, not what is **reachable**. Sized so the ceiling can move without this having to |

**0.5s is permissive, not conservative.** Competitive shooters land near 0.2s.
This game gets more room because the rewound thing is usually an NPC:
over-rewinding means other players watch damage land on empty air, not that a
human was robbed of a dodge.

**Past the ceiling is degradation, not failure, and that is the design.** A
600ms player is compensated 0.5s of a ~0.7s deficit, so their swings under-lead
a moving target by the ground it covered in the remainder — bounded,
self-limiting, survivable.

**Clock source is `workspace:GetServerTimeNow()`, never `os.clock()`.**
`os.clock()` has an arbitrary per-process origin and differs between client and
server. `SkillService._cooldowns` uses `os.clock()` and that stays correct —
those are server-local durations no client reasons about. **The two must never
meet in one comparison.**

### MEASURED — `GetNetworkPing()` returns seconds

Measured in a Team Test session against an independently measured round trip.
The unit question is closed.

### Defense is generous, offense is exact

For **player attacks**, the rewound position is used exactly. What the player
saw is what counts.

For **enemy attacks**, the player gets the most favourable reading available:
outside the volume at *any* sample across the window means they dodged.

Both rules favour the human. A high-ping player is marginally harder to hit,
which is the same trade every "favor the shooter" system makes, pointed at
defense instead. **A player who dodged on their own screen and took damage
anyway will not accept any explanation. A boss that occasionally misses a laggy
player costs nothing.**

---

## Part 7 — Hurtboxes — The Decisions

**Status:** **BUILT 2026-08-22** for the typed route — ten limb-anchored zones
per player, one per dummy, each rewound through its own limb. The single
enveloping capsule is deleted. Reading zones off a rig's own parts (the boss
route, 7.3) is still **UNBUILT**. Authoring procedure lives in `Hurtboxes.md`;
this Part keeps only the decisions and what they rejected.

**A hurtbox is a list of capsules roughly mirroring the model's parts.** Six or
so for a humanoid; more for a boss with anatomy worth distinguishing.

### 7.1 — Why one enveloping volume is a bug, not a stage

A single sphere or box around a large enemy makes the space **between** its
limbs hittable. Fire under a raised arm and it registers. The player's current
radius is already ~2.5× too wide horizontally.

This was the built behaviour until 2026-08-22 and it was a placeholder rather
than a design. **It was already wrong at the numbers of the day** — the ten
dummies were enough to see it, and it never needed a boss to justify fixing.
**Closed:** the single capsule is deleted and a body with no zone list is
simply not hittable, asserted at attach rather than silently falling back.

### 7.2 — The one fact that decides the shape

`Overlap.arc` subtracts a target's **angular half-width**,
`asin(radius / distance)`, from the angle to its centre before comparing. That
one line is what makes the arc test both exact and cheap, and it is the step
naive implementations skip.

**It requires the target to have a radius.**

| Target shape | Candidate points | Exact? |
|---|---|---|
| Sphere | 1 | yes |
| **Capsule** | **3** | **yes** |
| Oriented box | 9 | no — approximates in all three dimensions |

A box has no radius, so the trick is unavailable and the test degrades to
sampling corners. **A limb is a cylinder, not a box.** A capsule fits it in the
long direction, keeps the half-width trick, and costs a third of the corner
sampling.

> **DEMOTED — this is no longer *the* deciding fact on its own.** The
> `asin` argument weakened once melee stopped being primarily an ARC: a
> `CAPSULE` volume against a capsule target does not use the angle test. What
> survives, and is the durable form of the argument: **a capsule keeps three of
> the four volume tests in closed form.** A box has no radius to sum, and every
> one of the four degrades.

### 7.2a — EACH ZONE ANCHORS TO ITS OWN LIMB, NOT TO THE ROOT

**Status:** SETTLED 2026-08-21. **Corrects a design proposed and nearly built
the same day**, which is why it is called out rather than folded in silently.

The rejected version stored each zone as an offset **from the body's root**,
read once at spawn. It is cheaper — one history per entity instead of one per
zone — and it is wrong the moment anything animates:

> A boss flaps its wings. The wings move. **The hurtboxes stay in the rest
> pose.** Nothing errors. The wing is simply not where it can be hit.

```
WRONG    zone = rootCFrame * offset          the wing flaps, the zone does not
RIGHT    zone = wingAnchor.CFrame * offset   the zone flaps with it
```

**The offset is frozen; the thing it hangs off is not.** Expressed in the
wing's own frame, a 40° wing rotation rotates the zone 40° for free.

**What it costs, and it is affordable.** Each zone needs its own history — the
wing and the torso are in different places at different moments, so one buffer
per body cannot serve both. Ten zones × 47 slots × a `CFrame` is roughly 30KB
per body; twenty bodies is about half a megabyte. Sampling is ten `CFrame`
reads instead of one, thirty times a second.

**This was previously blocked and is no longer.** The root-relative version was
chosen to avoid depending on whether a server script can observe animated limbs.
`LimbProbe` answered that (9.6): it can. The simplification outlived its reason
and was not revisited when the reason expired — which is its own lesson.

#### It applies to PLAYERS too, and that took two attempts

**Status:** SETTLED 2026-08-22, after building the wrong one and looking at it.

A player's limbs are animated by their *client*, so the server's copy is ~0.104s
stale (9.6). The first answer was to spare players that by anchoring their zones
to the **root** — the slowest, best-replicated part of the body.

**Built, drawn, and immediately obviously wrong.** It produces a rigid
arrangement of capsules that ignores the pose entirely: a mannequin riding the
player, arms fixed at its sides no matter what the body does.

The error the design was avoiding is `limb speed × 0.104s`, and that is the
number worth writing down:

| Limb doing | Speed rel. root | Error | Arm capsule radius |
|---|---|---|---|
| **Standing, walking** | ~3 studs/sec | **0.30 studs** | **0.28** |
| Running | ~6 studs/sec | 0.62 studs | 0.28 |
| Mid sword-swing | ~45 studs/sec | 4.68 studs | 0.28 |

**At the speeds a body spends nearly all its time at, the error is smaller than
the capsule's own thickness.** Root-anchoring bought exactness on zones that
were never meaningfully inaccurate, and paid for it with a permanent visual
wrongness on every zone.

**The swing row is real and is accepted.** During a player's own attack an ARM
zone is briefly stale — the smallest zone on the body, on the *defensive* side,
where Part 6's "defense is generous" already errs their way. And it says nothing
about their own attacks, which use `PATH` (9.4) and touch no limb at all.

> *The test that catches the first attempt: draw it and look. A design whose
> cost is "the body no longer matches the pose" cannot survive being seen, and
> was argued about for an hour before anyone rendered it.*

#### Splitting at the joints is the point

Riding limbs with **one capsule per arm** — anchored to the upper arm, stretched
over the forearm — is fine while the arm is straight and wrong the moment an
elbow bends, which is most of what an arm does. That would keep the mannequin
problem in a smaller costume.

So the player list is **ten zones**: head, torso, and upper/lower for each arm
and leg. Torso stays merged because the waist barely articulates; hands and feet
ride the forearm and shin capsules until something needs to tell a hand from an
elbow.

#### `anchor` is a NAME, never an Instance

One definition table is shared by every body of a kind and survives every
respawn. An `Instance` reference would bind one list to one corpse.

**`bind` resolves names per body, on every attach including respawn.** Not an
optimisation to skip: a respawned character is a whole new set of Instances, and
a zone hanging off a destroyed part silently stops moving — which reads as *"the
hurtbox is stuck"*, a bug nobody would think to look for in a component.

**A missing part falls back to the root and warns**, rather than erroring. The
zone list is content and the rig is art, and the two drift — an R6 character, a
renamed limb, a boss exported without a part. One bad zone name should not cost
a whole body's hittability, and the warning is what stops the fallback being
silent.

### 7.2b — The anchor is a `Bone` on a skinned mesh and a `Part` on a rigid rig

**Status:** SETTLED 2026-08-21.

Two rig kinds exist and they are genuinely different objects. Earlier revisions
of this Part described only the first, which made every statement here quietly
wrong for creatures exported from Blender.

| | **Rigid-part rig** | **Skinned mesh** |
|---|---|---|
| What it is | separate parts joined by `Motor6D` / `AnimationConstraint` | **one mesh**, deformed by a tree of `Bone`s |
| R15 characters | this | — |
| A creature rigged in Blender | — | **this** |
| Is there a "wing part" to read? | yes | **no. There is no wing part** |
| A hurtbox anchors to | the Part | **the Bone** |

**One branch, at spawn: is this anchor a `Part` or a `Bone`?** Both expose an
animated world `CFrame`, so everything downstream is byte-identical. Nothing
else in this layer learns which kind it got.

**The honest limit, stated so it is not discovered as a bug:**

> **Joint motion is captured exactly. Surface deformation is not.**

A capsule on a wing bone follows that wing perfectly through a flap, a dive, a
dash — because the bone *is* the source of truth for where the wing is. The
membrane billowing around it is not a capsule and never will be.

| Situation | Captured? |
|---|---|
| Wing sweeping through an arc | **exactly** |
| A tail whipping | **exactly — with 3–4 capsules along it.** One capsule for a whole tail is bad, and that is an authoring failure rather than a model failure |
| Membrane billow, cloth, fur, muscle bulge | no. Nor in any shipped game |
| Squash-and-stretch on a landing | no. A few percent |

**Surface deformation is almost never what decides a hit**, and chasing it is
what 16.2 rejects under *"exact intersection against real mesh geometry."*

### 7.3 — Three places a hurtbox can be authored

All three reduce to **an anchor, a radius, and a half-height**, so nothing
downstream can tell which was used. That is what makes the choice per-hitzone
and reversible.

| Route | The geometry comes from | Good for |
|---|---|---|
| **Derive** | `part.Size` — longest axis is the segment, half the smaller of the other two is the radius | roughly cylindrical limbs |
| **Declare** | numbers typed in the Content Layer | when the part is a bad proxy and you know the answer |
| **Author** | a hurtbox part placed by hand inside the rig | curved horns, diagonal limbs, anything `Size` lies about |

**`Size` lies more often than it looks.** It is the axis-aligned bounding box in
the part's **local** axes, so a diagonal limb, a curved horn, a flat plate, or a
part with one outlying spike all derive badly. `Hurtboxes.md` carries the table
and the fix.

**Complexity is absorbed by COUNT, not by the primitive.** A curved horn is
three capsules, not one clever shape. That is the whole reason the list exists.

### 7.4 — Client-owned rigs: a bound, not a ban

**Status:** the principle is SETTLED; **the bound itself is UNBUILT, and was
claimed as built in a code comment until 2026-08-23.**

Anchoring to a part driven by a *client's* animation lets that client reshape
its own hittable volume — position validation does not catch it, because the
position is fine and the **shape** is the lie. The server's answer to *"where
is this player's forearm"* is ultimately something that player's machine said.

**The title is the rule, and the built design relies on it.** An earlier
revision of this Part opened *"a hurtbox may be anchored to any part whose
position the server controls"* — which reads as a ban, and which the limb
reversal (7.2a) contradicted the moment it shipped. **Every one of a player's
ten zones is anchored to a client-driven part**, Head and Torso included. That
is deliberate. A ban would mean the mannequin, and the mannequin was worse.

#### What a liar actually wins, and why it is deferred

The exploit is moving your own zones off your own visible body, so attacks
aimed where you appear to be pass through empty space — the classic
hitbox-desync cheat. Two things bound the damage:

**It is purely defensive.** The zones a client can displace are its *own*. It
buys being harder to hit; it cannot make anyone else easier to hit.

**The game is PvE.** An unhittable cheater in a dungeon run has cheated
themselves and cost nobody. **That is the only reason this is deferred**, and
it is therefore also the trigger: *any mode where one player's survivability
affects another player's outcome* — PvP, scored clear times, a shared
leaderboard.

#### The bound, when it is built

**DECIDED 2026-08-23.** The stated principle is to mitigate cheating rather
than chase eliminating it, and never at the cost of how the game feels.

> Your arm cannot be forty studs away from you. It can be somewhere slightly
> wrong, and that is a trade taken knowingly.

| | |
|---|---|
| **Clamp, do not reject** | pull an implausible zone back into the envelope. Rejecting makes a laggy player's hurtbox vanish, which is worse than a mildly wrong one |
| **Cost is a mitigation** | warping a hurtbox past a bound means writing and maintaining a real exploit for a purely defensive payoff — more work than the work it avoids. Detection is a legitimate later layer, not a prerequisite |
| **Err loose** | see below. This is the one that is easy to get backwards |

**The error asymmetry is the inverse of the broadphase margin's, and it matters
more.** Too loose permits a little more cheating, which costs a cheater their
own experience and nobody else's. **Too tight clamps a *legitimate* limb** — an
honest player on a bad connection, or mid-animation, silently gets a hurtbox
that does not match their body. That is the exact failure this entire layer
exists to prevent, inflicted on the people who did nothing wrong.

> **A wrong bound punishes the honest before it inconveniences the dishonest.
> Pick generously.**

**What the number should be is deliberately not decided.** `boundingRadius` is
already a measured, padded rest-pose reach from the root and is the obvious
candidate — but it exists for the **broadphase cull**, and quietly making one
number serve two purposes is how a tuning change to one silently becomes a
security change to the other.

**The boundary is network ownership, not entity type.** "Players are different
from bosses" is an entity-kind branch, which the architecture forbids, and it
would be wrong on the merits besides: the same hazard applies to a client-owned
pet or any NPC whose ownership was handed to a client for performance.
Ownership can be **read**; entity kind is a category someone has to remember to
check.

**Consequence, stated loudly:** "NPC animations are started by the server" is
no longer a rendering detail. **It is load-bearing for hit detection.** Moving a
boss's animation to the client for performance would silently make its
hurtboxes client-controlled, nothing would error, and the exploit would be
invisible.

### 7.5 — A hurtbox is not an Instance, and never lags

A hurtbox is a list of zones, each an `offset` + `radius` + `halfHeight` hung
off a named limb, evaluated on demand by `endpoints(index, pose)`. **Nothing is
stored between calls, so nothing can desync.**

**The caller supplies the pose; the component never reads one.** That is not
ceremony — it is the single property that makes a hurtbox rewindable. Hand it
a pose from 100ms ago and it produces the shape the body had 100ms ago, for
free, with nothing stored per moment. A component that read `part.CFrame`
itself could only ever answer about *now*, which is the one tense this layer
does not care about.

The debug overlay is a separate thing that *draws* one, and an earlier version
of it trailed the player by a full round trip because it was anchored parts
being teleported from the server's stale copy. That was a property of the
overlay, never of the hurtbox. `Hurtboxes.md` carries the trap in full.

---

## Part 8 — `HitVolume` — The Declarative Half

**Status:** BUILT.

The generic engine is `TargetResolution`; the declarative configuration is a
`HitVolume` — a plain table on a skill definition describing a shape and
nothing else. **Adding an attack shape is a data edit. Adding a new *kind* of
shape is one vocabulary entry plus one overlap function.**

| Shape | Fields | For |
|---|---|---|
| `SPHERE` | `radius` | point-blank AoE, ground markers, explosions |
| `BOX` | `size`, `offset` | cleaves, walls, rectangular zones |
| `ARC` | `radius`, `angle` | shockwaves, point-blank bursts, breath cones |
| `CAPSULE` | `length`, `radius` | swords, thrusts, beams, dash attacks |

| Field | Default | Meaning |
|---|---|---|
| `anchor` | `ATTACKER` | or `POINT` — a ground-targeted AoE anchors to a location |
| `activeWindow` | `0` | seconds the hitbox is live; `0` is instantaneous |
| `maxTargets` | `nil` | unlimited; a cap makes a skill single-target by data |
| `requiresLineOfSight` | `false` | one raycast per surviving candidate, after narrow phase |
| `aimSource` | `FACING` | or `CLIENT_AIM` — Part 12 |
| **`motion`** | **`STATIC`** | **where the transform comes from — Part 9** |

### 8.1 — ONE APPLICATION PER ACTIVATION

**Status:** SETTLED and BUILT. Named because it is the fifth thing in this
project that gets called "hits" in conversation.

> **An activation applies to any given entity at most once, however many
> moments it was tested at.**

| | Means |
|---|---|
| `hitsPerTarget` | how many times an attack **deliberately** strikes each victim — a three-hit flurry. Content data. Reaches the damage roll |
| **once per activation** | an implementation guarantee that **incidental** re-detection never becomes extra damage. Never content, never tunable, never visible |

A three-hit flurry is `hitsPerTarget = 3` **and** once-per-activation — the
skill deliberately strikes three times, and the engine guarantees that testing
the swing eight times does not turn that into twenty-four.

**The load-bearing case is a moving volume.** A swinging blade passes through a
body for several consecutive steps *by design*. Without dedup across the whole
activation, that body takes a hit per step.

### 8.2 — An `ARC` is a CONE, and that is why a sword is not one

`Overlap.arc` measures the full three-dimensional angle between facing and
target, so **a 120° arc opens 60° in every direction — up and down included.**
Jump clean over an enemy and you hit them anyway.

`BASIC_SWING` was a 12-stud, 120° `ARC` from the first day of this layer until
2026-08-16, and it was the wrong shape for a sword in a way that is invisible
until someone jumps. It is now a **`CAPSULE`**: 6.5 studs of arm-plus-blade,
0.5 of thickness, swept through 160°.

**The thickness is the number a cone had no equivalent of at all.** An arc has
no concept of how thin a blade is.

`ARC` stays in the vocabulary. It is the right shape for a shockwave, a
point-blank burst, or a cone of breath. It was never the right shape for a
slash.

---

## Part 9 — Motion — Where The Transform Comes From

**Status:** DESIGNED. `STATIC` and `SWEEP` are **BUILT**; `PATH`, `PROJECTILE`
and `LIVE` are **UNBUILT**. This Part is the reframe.

> **DECIDED 2026-08-21, and this supersedes a flat "`PATH` is the default"
> written earlier the same day.** The choice is not a preference. It is read off
> network ownership:
>
> | Rig animated by | Hitbox | Files per attack |
> |---|---|---|
> | **the server** — bosses, NPCs | **`LIVE`** (9.6) | **zero** |
> | **a client** — players | **`PATH`** (9.4) | one, generated |
>
> **This is an ownership branch, not an entity-type branch**, and that
> distinction is the same one 7.4 already draws for hurtboxes: *ownership is a
> property that can be read; entity kind is a category someone has to remember
> to check.*
>
> `SWEEP` is not deprecated — it stays as the cheap option for volumes that
> genuinely are a rotating fan. See 9.0a for why ownership is the deciding
> axis rather than taste.

### 9.0a — Why ownership decides, and why this argument kept recurring

**Status:** SETTLED 2026-08-21, after research rather than another round of
weighing properties.

The industry is genuinely split on this, and **it splits on exactly one axis:**

| Approach | Used by | Why |
|---|---|---|
| Colliders attached to bones, read at runtime | 3D action games, Souls-likes, the Unity/Unreal default | the simulation is trusted and single-authority |
| Per-frame authored hitbox data | fighting games, rollback netcode | must be deterministic across two machines |

The deciding finding, near-verbatim from the research: *frame-authored data
gives more predictable netcode because the hit windows are predetermined;*
**bone-attached colliders require the netcode to guarantee both machines have
synchronised skeletal animation at the same frame.**

**That is the condition `LimbProbe` measured, and it does not hold for a
client-owned rig** — ~0.104s of divergence (9.6). It holds perfectly for a
server-owned one, where there is no second machine in the loop at all.

The same story from the Roblox side: the widely-used bone-attached module has
the reported failure *"fires raycasts on the server which can have latency
issues for players with high ping,"* and the community workaround is
client-reports-hits with a server sanity check — which Part 12 refuses outright.

**Why this Part kept being re-argued:** every previous attempt asked *"which is
better."* There is no answer to that, which is why it never stayed settled.
Asked as *"better for which ownership,"* it resolves and stays resolved — you
read the ownership and it tells you.

**And the file-count objection dissolves on its own.** The worry was N path
files for N animations. Bosses — where nearly all the attack variety lives — get
the **zero-file** route, because the server owns the rig. Players get files, and
a class has perhaps a dozen attacks, generated by a recording step rather than
typed.

### 9.0 — The question every previous revision skipped

A hit test needs a **shape** and a **transform** — what the volume looks like,
and where it is. Part 8 is entirely about the shape. Until this revision,
*where it is* had exactly one answer, hardcoded and unnamed:

> the attacker's root position and facing, optionally rotated by a formula.

That was never written down as a decision because it never felt like one. It
is one, and naming it is what makes the rest of this Part possible.

**Make it a field, and four things that were separate problems become one
problem.**

### 9.1 — The five motion kinds

```lua
motion = "STATIC" | "SWEEP" | "PATH" | "PROJECTILE" | "LIVE"
```

| `motion` | The transform at step *n* | Cost | For |
|---|---|---|---|
| `STATIC` | fixed at the origin | cheapest | explosions, ground AoE, breath cones |
| `SWEEP` | rotate by a formula | cheap | horizontal slashes. Today's model |
| **`PATH`** | **evaluate an authored path** | **one lerp** | **weapons. THE DEFAULT** |
| `PROJECTILE` | translate over time | cheap | ranged attacks, travelling shapes |
| `LIVE` | read a welded part's CFrame each tick | a CFrame read | **held in reserve** — 9.6 |

**Every one of them feeds the identical overlap math and the identical rewind.**
What differs is only how a `CFrame` is produced — computed from a formula, or
read from a table, or observed.

> **An earlier draft of this Part listed `BAKED` as a separate kind, meaning "a
> path recorded off a rig at dev time." That was a category error: recording a
> rig is an *authoring method*, not a runtime behaviour.** Hand-authoring a path
> and generating one by recording a weapon produce the identical artifact and
> the identical runtime code. Both are `PATH`. See 9.4.2.

### 9.2 — `STATIC`

The volume does not move. `activeWindow` may still be non-zero, in which case
the same shape is tested at several moments while targets move through it.

This is the degenerate case of all three others, and nothing special-cases it.

### 9.3 — `SWEEP` — formula-driven rotation

**Status:** BUILT.

**The problem it exists for: a blade is not everywhere in its arc at once.** A
one-second slice travels through its arc, and a target at the far end has most
of that second to leave. Treating the whole fan as live for the whole window
hits them anyway, and **no amount of extra sampling fixes it, because every
sample tests the same fan.**

With `sweep > 0` on a `CAPSULE`, `angle` stops meaning "the whole fan" and
starts meaning **the blade's own width**; `sweep` is the arc it traverses.

```lua
{ shape = CAPSULE, length = 6.5, radius = 0.5,
  motion = SWEEP, sweep = 160, activeWindow = 0.40 }
```

A target at +50° is missed early and caught late — **and clean if they leave
before the blade arrives.** That is the dodge behaviour the fan model cannot
express at any sample count.

**`SWEEP` rotates about the attacker's own Y axis**, so a swing on a slope
stays in the plane the attacker is standing in. It is also, today, the entire
limit of what `SWEEP` can express — see Part 15.

### 9.4 — `PATH` — an authored path, evaluated over time

**Status:** DESIGNED, UNBUILT. **The chosen model for weapon attacks**, and the
reason the rest of this Part exists.

**The hitbox is its own object with its own authored motion.** Not welded to a
bone, not derived from a formula — a volume travelling a path someone placed by
hand, anchored to the attacker's root.

```
AUTHORING          move a part through the swing in the Conductor, watching it
                   against the rig clip on one shared transport

STORAGE            a track in the Score -- a list of { t, CFrame }

RUNTIME (server)   transformAt(n) = rootCFrame * evaluate(track, t)
                   one lerp between two keys. Cheaper than SWEEP's trig
```

#### What it buys

| | |
|---|---|
| **Authored by eye, not by number** | `sweep = 160` cannot be judged by looking at it — it is tuned by swinging, missing, and guessing. A part you can drag and watch against the blade can be judged. **This is the argument that decided it** |
| **Any motion at all** | diagonals, overheads, X slashes, spirals, arcing thrusts. `SWEEP` expresses exactly one of these |
| **No network in the loop** | the path is local data. Nothing about it replicates, so nothing about it can diverge — 9.6 measured what happens when something does |
| **Deterministic** | same input, same path, every time. A physics read is not |
| **The client cannot influence it** | the server evaluates its own copy. No bounds check to write, no trust to spend |
| **Cheaper than today** | a lerp between two keys, against `CFrame.lookAt` plus an angle rotation |

#### 9.4.0 — STORE THE PIVOT, NOT THE BLADE TIP

**Status:** SETTLED 2026-08-21. Small, easy to get wrong, and invisible when
wrong.

A blade travels an **arc**. Interpolating between two stored *positions* gives a
**straight line**, so a lerp cuts the corner:

```
        the actual arc
      ,--------------.
     /                \        the gap is the error
    A ----------------- B      <- what a position lerp gives you
```

The gap scales viciously with how far apart the keys are. For a 6.5-stud blade
through 160°:

| Keys in the path | Degrees per segment | Worst-case error |
|---|---|---|
| 3, hand-placed | 80° | **1.52 studs** — three blade-widths |
| 8 | 23° | 0.13 studs |
| 24, recorded at 60Hz | 6.7° | 0.011 studs — nothing |

**The fix removes it entirely rather than shrinking it.** `CFrame:Lerp`
interpolates *rotation* spherically, not linearly. So store the **pivot's**
frame — where the shoulder is and which way it points — and define the blade as
a capsule extending from it. Interpolating gives a true in-between **angle**, and
the tip traces the real arc.

> **The arc is then exact at any key density.** Three keyframes or three
> hundred.

This is also what `SWEEP` already does — rotate the origin, let the blade extend
from it. Same trick, with the angle read from data instead of computed.

**The trap it prevents:** storing tip positions works fine on a dense recording
and fails badly the moment someone hand-authors a sparse path, which is exactly
the case where nobody would think to check.

#### 9.4.1 — The drift risk, named because it is the one real cost

**The blade you SEE comes from the rig animation. The hitbox comes from a
separate track.** Re-author the swing so the blade passes lower, and the hitbox
does not know.

That is the same two-numbers-in-two-places problem this document keeps closing,
reappearing one level up. Not fatal, and not free.

**Two things blunt it:**

1. **They are authored against each other, on one transport.** The Conductor
   previews the rig clip and the hitbox track together, so a mismatch is visible
   while you are making it rather than discovered in a playtest.
2. **Recording the rig generates a track** (9.4.2), which removes the authoring
   gap entirely for anyone who wants it removed.

**The test that catches a bad version of this:** can a designer change an
attack's reach without touching the animation? Under `PATH`, yes — inflate the
volume's `radius` against the same path. If that answer ever becomes "re-animate
it," this has drifted into the thing 16.1 rejected.

#### 9.4.2 — Recording a rig is an authoring method, not a motion kind

An earlier draft of this Part called this `BAKED` and listed it beside `SWEEP`
as though it were a different runtime behaviour. **It is not.** Play the swing
in Studio, sample the weapon part's CFrame relative to the root each frame,
write the list into a track — and what comes out is **a `PATH` track, identical
in every respect to one placed by hand.**

| Authoring route | Good for | Cost |
|---|---|---|
| **Hand-placed in the Conductor** | tuning reach and feel independently of the art | can drift from the visual (9.4.1) |
| **Recorded off the rig** | guaranteeing the hitbox *is* the blade | must be re-recorded when the animation changes, **and forgetting is silent** |

Both are supported, both are chosen per attack, and **nothing downstream can
tell which was used** — the same property that makes the three hurtbox
authoring routes interchangeable (7.3).

#### 9.4.3 — Walking while attacking

The path is authored **relative to the attacker's root**, and the root is
re-read at **every step** rather than captured once when the swing begins.

**Per step, not once.** Anchor at the swing's start and the hitbox stays behind
while the player walks out of it — the swing lands where they used to be. Per
step and it travels with them, which is what it looks like on screen.

Not new machinery: `_origin` already reads the attacker's live pose for every
wedge, for the same reason.

**The animation side needs nothing from this system.** An upper-body attack over
a walk cycle is `AnimationPriority` — `Action` outranks `Movement`, so arms
swing while legs walk. Roblox's layering handles it.

#### 9.4.4 — Tunneling, and the rate that prevents it

A path sampled at discrete ticks leaves the space between ticks untested. The
criterion is exact:

> **Tunneling is impossible while the hitbox moves less than the smallest
> hurtbox radius per tick.** If the gap is narrower than the target, the target
> cannot fit inside it.

`BASIC_SWING` is a 6.5-stud blade through 160° in 0.40s, so the tip travels
~18 studs in 0.4s ≈ **45 studs/second**:

| Tick rate | Tip travel per tick | Against a 1.5-radius hurtbox |
|---|---|---|
| 30Hz | 1.50 studs | **exactly at the limit — marginal** |
| **60Hz** | **0.75 studs** | safe, 2× margin |

**So a `PATH` is evaluated at 60Hz, not the 30Hz the spatial sampler uses.**
They are different rates for different jobs and that is deliberate: the sampler
records where bodies were, and 30Hz is plenty for a body; the driver decides
where a blade is, and a blade is the fastest thing in the game.

> **THIS INTERACTS WITH THE HITZONE LIST AND THE INTERACTION IS EASY TO MISS.**
> Today a body is one capsule of radius 1.5. Split it into six limb capsules
> (7.1) and some of those have radius ~0.3 — at which point 0.75 studs per tick
> **does** tunnel. **Finer hurtboxes require a faster driver**, and the failure
> is a hand that silently cannot be hit.
>
> The alternative, if the rate ever gets uncomfortable, is the same trick
> `SWEEP` already uses: test the volume **spanning** tick *n* to tick *n+1*
> rather than the pose at each. A capsule from A to B is math `Overlap` already
> has.

### 9.5 — `PROJECTILE` — and why it is not rewound

**Status:** DESIGNED, UNBUILT.

```
position(t) = origin + direction * speed * t      (+ gravity, if it arcs)
```

Each server tick: advance, test, stop on hit or expiry. The client separately
spawns a cosmetic part that flies the same path. **The cosmetic part never
decides anything.**

**A projectile in flight is not rewound, and this is a real distinction rather
than an omission.** Rewind exists because the round trip made the attacker's
view stale — decisive for an instant attack, where everything resolves in the
moment the event arrives. A fireball that takes a second to cross the room is
simulated live by the server the whole way. When it reaches a target, that
target is genuinely *there, now.* Nothing is stale.

```
the launch moment       → rewind applies. Did they aim where they saw the target?
flight, tick by tick    → live. The server is watching in real time
```

**The one care it needs: test the capsule from last position to current, not a
sphere at current.** A fast projectile jumps between ticks and will pass
straight through a body. This is the same tunneling problem `SWEEP` solves with
wedges, and it uses overlap math that already exists.

### 9.6 — `LIVE` — the fallback, and the measurement that made it one

**Status:** DESIGNED, UNBUILT, **DELIBERATELY NOT CHOSEN.** Recorded in full
because it is the fallback if `PATH` disappoints, and because the measurement
behind the decision is worth keeping.

**The design:** weld an invisible proxy part where the blade sweeps. It joins
the body's physics assembly, so it rides the animation for free — no per-frame
writes, no code moving it. The server records its CFrame each tick into history
and rewinds that history exactly like a hurtbox.

**Its genuine advantage over `PATH`, and the reason it is kept rather than
deleted: it follows motion an authored path cannot.** IK correcting a swing
toward a target's real position, blending softening a transition, physics
deflecting a blade — the welded part follows all of it. A path does not.

#### MEASURED 2026-08-21 — `diagnostics/LimbProbe.luau`

The question was whether a server script can see a limb move while the **client**
plays the animation. Three revisions of the probe were needed, and the first two
were wrong in instructive ways:

| Rev | Measured | Why it could not answer |
|---|---|---|
| v1 | range of motion on each side, subtracted | the two windows covered different seconds of a **non-repeatable input** (walking). The difference measured the walking |
| v2 | client reports a pose stamped with server time; server rewinds to it and subtracts | correct in shape, **assumed the clocks agree**. A 50ms stamp error manufactures ~0.33 studs out of a healthy system |
| v3 | searches a range of offsets, keeps the best match | the shift is the skew; the residual at that shift is the fidelity |

**What it found:**

| | |
|---|---|
| Does the server see a client-animated limb move? | **Yes**, unambiguously |
| Does a welded proxy ride it exactly? | **Yes** — proxy and limb reported identical figures |
| Is the joint a `Motor6D`? | **No — `AnimationConstraint`.** Avatar Joint Upgrade is enabled on this place |
| How far behind is the server's live view? | best-match offsets of −0.150, −0.050, −0.170, −0.045 → **mean ≈ 0.104s** |

**That last number is the finding.** `INTERPOLATION_CONSTANT` is **0.100s**. The
server's live view of a limb trails by almost exactly the interval Part 6 says
client-visible state trails by. **That is the design working, not failing** — and
it is precisely what rewind exists to undo.

**Two flaws in the probe, recorded so the numbers are not over-trusted:**

- The error was reported as a fraction of the limb's **cumulative path length**
  over the window (~34 studs of accumulated wiggle), which is meaningless. It
  should be against the swing's amplitude.
- The alignment picks the best offset **independently per report**, taking the
  minimum of a noisy signal forty times and averaging the minima. That biases
  the residual **downward**, so the true figure is worse than the 0.19–0.38
  studs printed.

#### Why this did not decide it

**Because `PATH` does not depend on any of it.** The trail is real, expected, and
already handled — but a path anchored to the root never reads a limb, so there is
nothing for it to inherit. The probe's value was in removing an unknown, not in
choosing a design.

**`LIVE` remains correct and fully trustworthy for server-owned rigs**, where the
server plays the animation and reads its own parts with no replication in the
loop. If a boss ever needs IK-corrected contact, that is where this comes back.

> **UNTESTED AND NAMED AS SUCH:** the probe's control rig has its joint written
> **directly by a script**, not by an `Animator`. The client sees that control as
> completely static — correct behaviour, since a scripted `Transform` write does
> not replicate in either direction. So **a server-animated boss remains
> unmeasured**, and needs one real uploaded animation to settle.

### 9.7 — One driver, several sources — and why this is not "two engines"

The previous revision rejected running two detection systems side by side —
live built-in queries for cheap cases, buffer math for compensated ones — on
the grounds that two code paths that must agree will drift. **That rejection
stands, and this is not that.**

```
                    ┌─ STATIC      → the origin, unchanged
transformAt(n) ─────┼─ SWEEP       → origin * Angles(0, θ(n), 0)
     │              ├─ PATH        → origin * evaluate(track, t(n))
     │              ├─ PROJECTILE  → origin + direction * speed * t(n)
     │              └─ LIVE        → the proxy part's recorded CFrame
     ▼
  Overlap.test(transform, volume, capA, capB, radius)     ← ONE function
     ▼
  poseAt(entity, at)                                      ← ONE rewind
```

**There is one driver, one overlap function, and one rewind.** The four kinds
differ only in a `CFrame` supplier. Two engines would mean two answers to "was
this a hit"; this has one, reached four ways.

The test that distinguishes them: *if I fix a bug in the overlap math, how many
places do I change?* Two engines: two. This: one.

### 9.8 — Wedges — closing the gap between steps

**Status:** BUILT for `SWEEP`.

**The problem.** Testing a blade *at* each step leaves the space *between*
steps untested. 140° across 8 steps is a 20° jump, and anything narrow enough
to sit in a gap passes straight through. The name is **tunneling**, and every
discretely sampled system in every engine has it.

**The fix falls out of the geometry.** A blade that pivots at its own origin
and rotates from one angle to the next sweeps a **pie slice** — radius is the
blade's length, width is the step. A pie slice is an `ARC`. So a sweep resolves
as **wedges that tile the whole arc with nothing left out**, using overlap math
that already existed and was already tested.

```
tested   gap    tested          wedge 1   wedge 2   wedge 3
  |              |              ┌───────┬────────┬────────┐
  ↓   ← 20° →    ↓       →      │       │        │        │
  ╲      ●      ╲                ╲  ●   │        │        │
      MISSED                        HIT — nothing is untested
```

**Coverage no longer depends on the count**, which changes what the number is
for:

> **Step count is not "how much space do I cover." It is "how finely do I
> distinguish *when*."**

With one wedge you test the whole arc at a single instant, so someone who
walked in *after* the blade passed is hit anyway. More wedges is a finer answer
to *when*.

**That makes it a safety property, not a design knob**, so content does not
author it:

```
wedges = max( ceil(sweep / 20°), ceil(activeWindow / 0.05s) )
```

| Cap | Stops |
|---|---|
| 20° per wedge | a wedge widening until it is a fan rather than a blade |
| 50ms per wedge | a running target crossing a wedge inside its own duration |

**Angle alone is not enough**, which is the trap: a 360° spin over two seconds
is *slower* than a 90° flick over a tenth of a second, and the flick is the one
needing fine timing.

`samples` is **rejected at boot** on a moving volume rather than ignored — a
number that silently does nothing is worse than one that fails with a reason,
and two loops stepping the same window would each be right while the pair was
wrong.

**Three details that are easy to get wrong:**

| | |
|---|---|
| Each wedge is aimed at the **middle** of its span | aiming at an edge gives correct total coverage, shifted half a step off where the blade is |
| Each wedge is evaluated at the **middle** of its time span | the wedge covers its whole span whichever moment it fires; the timing decides where the *targets* are |
| The wedge is widened by the blade's own thickness | a blade of radius `r` looks wider nearer the pivot, so there is no single right number. Measured at half the blade's length: representative, and it errs generous |

**This generalizes to `PATH` and `PROJECTILE` unchanged.** An authored path is
sampled at discrete frames, so the gaps between frames still need covering —
by the capsule from step *n* to step *n+1*. A projectile needs the same. **The
wedge is the rotational case of a swept volume; it is not special.**

### 9.9 — How it actually runs — the stopwatch

**Status:** BUILT.

A moving volume does **not** resolve in one call. Each step fires **live**,
from a 60Hz Scheduler row, when its moment arrives:

```
step 3 comes due   →  now = 9.125
                   →  at  = viewTimeFor(player) = 9.025    (100ms back)
                   →  "was this body inside step 3's volume at 9.025?"
```

**Each step gets its own small rewind, computed fresh at its own moment.** This
is worth stating plainly because the natural reading of "rewind" is a single
large jump into the past, and it is not that. It is *N* live evaluations, each
looking back by roughly one round trip.

**There is no future prediction anywhere in this design.** An older path —
walking `samples` forward from one fixed `at` — did put later samples in the
future, where `poseAt` clamps them to the newest entry and quietly returns the
same answer repeatedly. That path applies only to instantaneous volumes, and
`samples > 1` is rejected on moving volumes specifically so the two can never
both run.

### 9.10 — Windows, beats, and where timing comes from

**Status:** DESIGNED, UNBUILT. This is the seam to the animation work.

`activeWindow` answers *when is this attack live*, and today it is a number
typed into the skill definition with no relationship to the animation at all.

**A beat is that number, read off the score.** A Score (see `Timeline.md`)
carries named moments; those named `activeStart` / `activeEnd` are **beats** —
gameplay-meaningful, read by the server from its own copy of the score.

```
SHADOW_CUT
  t=0.00   clip     RIG_DASH_SLASH
  t=1.20   BEAT     activeStart          ← the server reads this
  t=1.60   BEAT     activeEnd            ← and this
  t=1.20   spawn    slash prefab         ← the client draws this
```

**No trust is transferred.** The server never hears from the client about when;
it read the file itself. The client reads the same file to know when to draw.
One number, one place, tuned where you can watch it.

**Two consequences:**

1. **A start delay becomes expressible.** Today a window opens the instant the
   event arrives. A beat at 1.2s is a window that opens late — which is the
   entire mechanism behind a delayed slash, and it currently has no field.
2. **An activation may carry more than one window.** An X attack is two slashes
   with two beat pairs, not one clever shape. This is the composition answer,
   and it is better than growing the shape vocabulary to express crossings.

---

## Part 10 — Why There Is No Part

**Status:** SETTLED. Re-examined 2026-08-21 under the part-driven proposal and
upheld, for a reason that is narrower than the original.

There is no invisible `BasePart` anywhere in this system. `Overlap.luau` has no
requires, no state, and no engine calls. A hitbox at test time is a `CFrame`
and four numbers, and the test is dot products, squared distances, and one
`asin`.

**The decisive reason is one line:**

> **A Part exists only *now*. You cannot ask a Part where it was 100
> milliseconds ago.**

Rewind means reconstructing a moment that has passed. Every Roblox spatial
query — `GetPartsInPart`, `GetPartBoundsInBox`, `GetPartBoundsInRadius`,
`Shapecast` — answers about the present tense and nothing else. **The instant
the hitbox becomes a real Part, lag compensation becomes impossible.**

That is a trade, not a law, and it is worth naming as one:

| | Roblox's queries | Math over history |
|---|---|---|
| Answers about | **now, only** | any reconstructable moment |
| Lag compensation | impossible | the entire point |
| Needs an Instance | yes | no |
| Returns | Parts — walk the ancestry to find whose body | entities directly |
| Arc / cone query | **does not exist** | `Overlap.arc` |
| Respects | collision groups, `CanQuery` | nothing to configure |

**Three further reasons hold even where rewind does not apply** — enemy attacks
resolve at `at = now`, so the built-ins genuinely are usable in that direction:

1. **There is no cone query.** Roblox offers box, radius, and part overlap. No
   arc. The angle math is hand-written regardless, so the built-ins do not
   cover the primary shape.
2. **`GetPartBoundsInBox` tests bounding boxes**, so it is *less* precise than
   the capsule tests here. Only `GetPartsInPart` is exact, and it requires a
   real Part in the world.
3. **Entity mapping.** A buffer query can only ever return a registered entity.
   The classic Roblox bug — hit a part, walk its ancestry guessing whose body
   it is — cannot occur.

> **Where the built-ins genuinely win, and it is worth not dismissing:**
> `GetPartsInPart` does full mesh collision, which beats a capsule
> approximation on a concave shape like a crescent wing. It cannot be the
> primary engine, but it is a legitimate refinement for one specific hitzone if
> one ever proves it needs one.

### 10.1 — What this does *not* forbid

**Recording a part's motion is not the same as testing against a part.** Part
9.4's PATH track may be produced by watching a real part move in Studio — at dev
time, once, into a table. At runtime there is no part, no physics, and no query.

The rejection is of **Parts as the test mechanism**. It was never a rejection of
parts as an *authoring* mechanism, and conflating those two is what made this
argument feel unresolvable for several rounds.

---

## Part 11 — `TargetResolution` — The Engine

**Status:** BUILT.

Five stages. **Not a pipeline, and that is deliberate** — `DamageResolution`
earns its registration machinery because a dozen modifier types will genuinely
accumulate. This has five stages and will still have five in a year. They do
not accumulate, they are not independently authored, and nobody will ever
register a sixth from a content file.

| Stage | Does |
|---|---|
| **ORIGIN** | build the volume's transform. **The attacker is not rewound — only targets are** |
| **BROAD** | squared-distance cull, widened by how far anything could have moved |
| **NARROW** | exact overlap against each candidate's **rewound** capsule |
| **FILTER** | eligibility. Runs *before* the exact test, to avoid paying for an ineligible entity |
| **LIMIT** | `maxTargets`, with the client's `preferredId` sorted first |

### The attacker is not rewound

Walk the timeline. The client is at P when it presses attack. Its position
update and its attack command travel together and **arrive together** — so when
the server processes the swing, its newest record of the attacker already *is*
P. Rewinding the attacker on top of that double-counts the latency and drags
the swing backwards through space, which shows up as **attacks landing behind a
moving player**.

The target is the opposite case: the client saw it where the server said it was
a full round trip plus interpolation ago, which is exactly what gets rewound.

### The broadphase margin is not optional

Culling by reach alone discards an entity that has since run out of range but
**was** inside the volume at the moment being resolved. That is a miss caused
by culling, which looks identical to a miss caused by bad detection and is much
harder to find. The margin is `MAX_ENTITY_SPEED × window`, deliberately
generous: wrong-high costs a few extra exact tests, wrong-low silently drops
real hits.

### Line of sight is deliberately not part of target-finding

A separate raycast against world geometry, run **last**, on the few candidates
that already passed. Folding geometry into the overlap tests is how a hitbox
system ends up hitting a wall and walking its ancestry trying to work out whose
body it belongs to.

---

## Part 12 — The Trust Amendment

**Status:** SETTLED. The one place this document *changes* something the
architecture states rather than extending it.

| | |
|---|---|
| **Add to NEVER** | "I hit these five enemies." The server computes every target set. **There is no code path that accepts one.** |
| **Add to ALLOWED, conditionally** | "I am facing this direction" — a unit vector, and only for volumes that ask |

The volume's *origin* is always the server's own rewound view of the attacker.
Only the *direction* is ever in question, and for a wide arc the replicated
facing is good enough: at 100ms round trip a player turning at 180°/s has moved
18° — inside the tolerance of a 90° cleave.

So `aimSource` defaults to `FACING`, and **most attacks introduce no new trust
whatsoever.** Only narrow volumes set `CLIENT_AIM`. What a liar gains: swinging
somewhere they were not facing, which they could have achieved by turning.

### `targetId` is demoted, not removed

It stays on `CombatEvent` as a **hint**. The server always computes the set;
`preferredId` only sorts within it, and an id naming an entity that is not in
the computed set is ignored.

**The point is that there is one code path.** A trusted-target fast path
alongside a computed-volume path is two systems that must agree about range,
line of sight, and validity — and the trusted one would be the one exploited,
precisely because it is the one that skips the work.

### 12.1 — Client-authored hitbox positions — held in reserve, not rejected

Under `PATH`, the client never supplies a hitbox position, so the question does
not arise for authored attacks. It returns only for motion an authored path cannot
capture: procedurally adjusted swings, IK correcting to a target's real
position, physics-affected blades.

**For those, bounds validation is the right answer and exact validation was
never available.** Blending and IK make the precise blade position fuzzy by
design, so the check is not "is this exactly where we expect" but "is this
inside a plausible envelope." A claimed reach of 12.4 against a path that
reaches 12 is accepted; 40 is rejected.

Recorded as a **decided approach for an undecided case**, so that when the case
arrives nobody re-derives it from scratch.

---

## Part 13 — The File Map

| Module | Owns | Tree | Status |
|---|---|---|---|
| `components/SpatialComponent.luau` | anchor, tracked parts, one position ring buffer per part | `serverShared` | **BUILT** |
| `components/HurtboxComponent.luau` | the zone list — shape only, no position, no history | `serverShared` | **BUILT** |
| `definitions/HurtboxDefinitions.luau` | zone lists as content. `PLAYER_R15` (ten zones), `DUMMY` (one) | `serverShared` | **BUILT** |
| `services/authority/SpatialService.luau` | sampling, rewind, attachment registry | place `server/` | **BUILT** |
| `resolution/targeting/HitVolume.luau` | shape vocabulary, defaults, validation, step-count derivation | place `server/` | **BUILT** |
| `resolution/targeting/Overlap.luau` | the four volume-vs-capsule tests. Pure math, no requires | place `server/` | **BUILT** |
| `resolution/targeting/TargetResolution.luau` | the five stages | place `server/` | **BUILT** |
| `resolution/targeting/TargetQuery.luau` | the declared query shape | place `server/` | **BUILT** |
| `services/domain/CombatService/init.luau` | DETECT; the stopwatch driver for moving volumes | place `server/` | **BUILT** |
| **`resolution/targeting/Motion.luau`** | **the four transform suppliers** | place `server/` | **UNBUILT** |
| **`definitions/paths/*.luau`** | **baked blade paths** | place `server/` | **UNBUILT** |
| **a Studio recorder** | **samples a part's CFrame per frame, writes the table** | dev-only | **UNBUILT** |

**Everything is server-only, and none of it goes in `src/shared/`.**
`ReplicatedStorage` is a broadcast: putting the volume table there would publish
every skill's exact reach and arc to any client that cares to read it.

> **This is the one place the beats design creates tension, and it is named
> rather than resolved.** A Score lives client-side so the client can render it.
> A beat inside that Score is a gameplay number the server reads. Either the
> beats are extracted server-side at build time, or the Score's timing becomes
> client-readable. **OPEN** — decide it when the first Score exists, not before.

---

## Part 14 — Current State

**Status:** as of 2026-08-21. `Implementation-Status.md` is authoritative and
is not duplicated here; this is the shape of it.

| | |
|---|---|
| Spatial layer, sampler, rewind | **BUILT**, tested, run in Team Test |
| Overlap math, four shapes vs capsule targets | **BUILT** |
| `TargetResolution`, five stages | **BUILT** |
| `SWEEP` + wedges + the stopwatch driver | **BUILT**, player direction verified |
| `HurtboxComponent` + `HurtboxDefinitions` | **BUILT 2026-08-22.** Ten limb-anchored zones for a player, one for a dummy. Drawn, looked at, and confirmed to follow the pose |
| Per-zone history | **BUILT 2026-08-22.** `SpatialComponent` keys rings by `BasePart` — one shared timeline and cursor, one pose array per part — 7.2a |
| Resolution testing the zone list | **BUILT 2026-08-22.** Each zone rewound through its own limb; returns on the first zone that connects, because dedup would discard the rest anyway |
| One capsule per entity | **DELETED 2026-08-22**, along with `capsuleFromSize`. No hurtbox now means not hittable, asserted at attach |
| Reading zones off a rig's parts (bosses) | **UNBUILT.** Players are typed; bosses want the authored route — 7.3 |
| `motion` as a field | **UNBUILT.** Currently implied by `sweep` |
| `PATH`, `PROJECTILE`, `LIVE` | **UNBUILT.** Ownership decides which — 9.0a |
| Beats | **UNBUILT**, and blocked on the Score existing |
| Enemy attacks | **never run.** No enemy has attacked |

**Two bugs the live run caught and nothing else would have**, both silent, both
worth keeping because the shape recurs:

**`boundingRadius` measured from the wrong origin.** A zone's offset is relative
to ITS LIMB, so summing offset + halfHeight + radius answered *"how far does
this capsule reach from its own arm"* — 1.45 studs for a player, when the real
reach from the root is ~3.3. **The broadphase culls from the root.** It never
surfaced because the volume's own reach (7.5) dominated the sum, so nothing near
the edge of range had been tested. Now measured in `bind` as (limb from root) +
(zone from limb), padded 2× because that is a rest-pose reading and limbs move.
**Wrong-low silently drops real hits before the exact test ever runs.**

**`idsOf` was a local declared after its first use**, so the instantaneous AOE
path threw `attempt to call a nil value` the first time anyone pressed the key.
Pre-existing, on a path nothing had exercised.

---

## Part 15 — Known Gaps

Each named so it is not mistaken for an oversight.

| Gap | Why acceptable now | Trigger to fix |
|---|---|---|
| ~~**One enveloping hurtbox per entity**~~ | **CLOSED 2026-08-22.** Ten limb-anchored zones per player, per-zone history, resolution testing them, the single capsule deleted | — |
| **The client-driven zone bound is DECIDED and UNBUILT** | A client owns its own limbs, so it can move **all ten** of its own zones — Head and Torso included, not just an arm. What that wins is purely defensive, and the game is PvE, so an unhittable cheater has cheated only themselves. 7.4 carries the design: clamp not reject, err loose | **Any mode where one player's survivability affects another player's outcome** — PvP, scored clear times, a shared leaderboard. That is the only thing deferring it |
| **`SWEEP` rotates about Y only** | Every attack so far is a horizontal fan | The first diagonal or overhead slash. Either a `sweepAxis` field, or `PATH` makes it moot |
| **One window per activation** | No attack has needed two | The first X or multi-beat attack. `_sweeps` must hold several per activation |
| **No start delay** | Every window opens on arrival | The first delayed attack. A beat is the field |
| **A stale recorded PATH is silent** | Nothing is recorded yet, and hand-authored tracks do not have this failure | Boot validation comparing a recorded track against the clip it came from (9.4.2) |
| **Enemy sweeps collapse to one instant** | Never surfaced — no enemy has attacked | The first enemy attack with a window. Needs the stopwatch on that direction |
| **Sweep steps 2..N over-rewind by one one-way latency** | Every step calls `viewTimeFor`, which returns `2L + I` — the correction for the *click*. Mid-swing the client is only `L + I` behind. Invisible at localhost; grows with ping and swing length | A playtest at real latency where a swing's later half feels laggy. **The fix needs deciding rather than assuming** — resolving the whole swing against the click's picture is also defensible |
| **Ping read fresh per swing, never smoothed** | One spiking sample widens that swing's rewind and nothing else's, and nothing can inspect a player's latency history when a hit is disputed | Planned: a measured, smoothed ping as a component on the player entity |
| `INTERPOLATION_CONSTANT` is borrowed, not measured | It contributes most of the rewind at realistic pings, so it is the lever that matters — but 0.1s is two independent implementations' answer | First playtest where hits feel late or retroactive |
| No spatial partitioning | Linear scan is microseconds at design scale | Broadphase appears in a profile, or ~500 attached entities |
| Line of sight unimplemented | The flag exists; no map has cover that matters | The first arena with pillars |
| Nothing registers with `SpatialService` except players and dummies | `EnemyEntity` is not constructed anywhere | Whatever spawns enemies gets written |
| ~~Does the server see a player's animated limb move?~~ | **CLOSED 2026-08-21 — yes, trailing by ~0.104s, which is the interpolation constant.** Does not affect `PATH`, which never reads a limb. See 9.6 | — |

---

## Part 16 — Rejected Designs, And The Reversals

Each kept with the **test** that catches it, not the narrative of who said what.

### 16.1 — The reversals

These are decisions this document previously made and now unmakes. They are
recorded at length because each was argued in full and sounded correct.

---

**~~Deriving the attack volume from the weapon's real pose.~~ REVERSED
2026-08-21 — partially.**

The previous revision rejected it on three grounds. Two of them were about
*runtime rig reading*, and baking answers both:

| Original objection | Status |
|---|---|
| "Retiming an animation silently changes what it hits, with nothing in the diff to review" | **Answered.** A baked path is a file. Re-baking produces a reviewable diff. The objection was to *invisible* coupling, and baking makes it visible |
| "Makes a swing a stateful multi-frame read of the rig" | **Answered.** Nothing reads the rig at runtime |
| "Costs tunability — 'make the slam more generous' becomes a re-animation" | **Partially stands.** Mitigated by inflating the volume's radius against the same path |

**And the load-bearing claim was simply false.** The previous revision closed
with: *"The precision it offers is available from `sweep` without any of
that."* That is true **only for horizontal fans about the attacker's Y axis.**
It is false for a diagonal, an overhead, an X, a spiral, a thrust that arcs, or
anything that travels. `sweep` is not a general model of blade motion; it is one
formula that happens to fit the first attack that was built.

> *The test that catches the original rejection: name a motion `sweep` cannot
> express. There were four within a minute of asking.*

> *The test that keeps the rejection alive for the runtime version: does the
> server read the rig during resolution? If yes, it inherits `Transform`
> replication and client ownership. If no, it is baking, and neither applies.*

---

**~~`BAKED` is a motion kind alongside `SWEEP`.~~ FOLDED INTO `PATH`
2026-08-21.**

Listing it beside `SWEEP` implied it was a different runtime behaviour. It is
not — recording a rig and hand-placing keyframes produce **the same artifact and
the same runtime code**. A path is a path. Recording is one way to author one.

The error is worth keeping because it is a recurring shape: *a way of producing
data got listed as a way of consuming it.* Both routes are now 9.4.2, chosen per
attack, and nothing downstream can tell them apart.

> *The test: would the engine execute different code? If no, it is not a
> separate kind.*

---

**~~The hitbox rides the rig.~~ SET ASIDE 2026-08-21 in favour of `PATH`.**

`LIVE` — a proxy part welded to the weapon, its position recorded per tick — was
the leading design for most of a day and is **not rejected**. It is kept in full
at 9.6 as the fallback, because it does one thing `PATH` cannot: **follow motion
that is not authored**, such as IK correcting a swing toward a target's actual
position.

**Why it lost, in one line: it puts the network in the loop and `PATH` does
not.** `LimbProbe` measured the server's live view of a client-animated limb
trailing by ≈0.104s against an `INTERPOLATION_CONSTANT` of 0.100s — the design
working exactly as Part 6 says it should, and an inheritance `PATH` simply never
takes on. `PATH` is also deterministic, cheaper than the trig it replaces, and
impossible for a client to influence.

**It remains correct and fully trustworthy for server-owned rigs**, where the
server plays the animation and reads its own parts with nothing replicating in
between.

> *The trigger to revisit: an attack whose contact point must adapt at runtime —
> a boss whose foot has to land on a player wherever they actually are. An
> authored path cannot express that and a welded proxy can.*

---

**~~Hitboxes never need position history.~~ CORRECTED 2026-08-21.**

The claim was: *hurtboxes need history because they are **observed**; hitboxes
do not because they are **generated**.* True — for a hitbox defined by a
formula, where the server can recompute the blade's position at any moment on
demand. Nothing was observed, so there is nothing to store.

**The moment a hitbox comes from an animation it becomes observed too**, and
then it needs history for exactly the same reason a hurtbox does. The claim was
conditional on an assumption that was never stated.

**And a baked path *is* that history** — recorded once at dev time rather than
every frame at runtime. Same data, cheaper, and it cannot be tampered with.

> *The test: is this volume's position computable from a formula? If yes, no
> storage. If no, it is observed data and something must have written it down.*

---

**~~The hurtbox strategy question is settled by `asin(radius/distance)`.~~
DEMOTED 2026-08-20.**

The angular half-width argument is real, but it only applies to the arc test,
and melee stopped being primarily an `ARC`. The durable form: **a capsule keeps
three of the four volume tests in closed form; a box has no radius to sum and
degrades all four.** Same conclusion, honest reason.

### 16.2 — Standing rejections

**`.Touched`.** Fires on the physics thread, misses fast-moving contacts, cannot
be rewound, and gives no control over when it runs. *The test: can it answer a
question about the past? No.*

**Hitbox Parts parented into the workspace and moved.** Allocation churn per
swing, unwanted physics interaction, and decisively — **you cannot move a part
into the past.** *The test: Part 10's one line.* This does **not** forbid
recording a part's motion at dev time (Part 10.1).

**Two engines: live built-in queries for cheap cases, buffer math for
compensated ones.** Two code paths that must agree and will drift. The buffer
engine subsumes the live one — a rewind of zero is the newest sample. *The test:
fixing a bug in the overlap math touches how many files?* Part 9.7's five
motion kinds are explicitly **not** this: one overlap function, one rewind, four
`CFrame` suppliers.

**Client detects, server validates.** Genuinely tempting — sharper, and moves
broadphase cost off the server. Rejected because the client would report a
target list, and the server-side re-check becomes load-bearing rather than a
backstop. *Explicitly reconsidered and explicitly declined.*

**`ARC` as the standard melee swing.** An `ARC` is a **cone** — a 120° arc opens
60° up and down. Jump over an enemy and you hit them anyway. *The test: jump.*
A sword is a `CAPSULE` with a thickness the cone had no equivalent of.

**One enveloping hurtbox per entity.** Makes the space between limbs hittable.
*The test: fire under a raised arm.*

**Oriented-box hurtboxes — adopted for one revision, reversed.** A box has no
radius, so the arc test degrades from one exact evaluation to nine approximate
corner samples. **Both the original rejection and the adoption were argued from
the wrong property** — the first claimed rewinding a box was expensive, but the
buffer stores `CFrame`s, so orientation was always present and rewinding a box
is free. *The right property is whether the target has a radius.*

**Exact intersection against real mesh geometry.** Curves do not survive export,
and Roblox's own physics never uses the render mesh at any fidelity. Undesirable
regardless, because it makes **every art change a balance change.** *The test:
would re-exporting a model silently change damage?*

**Choosing hurtbox strategy by entity kind.** An engine that asks whether a
target is a player is a type branch in a different costume. **Entities differ by
the contents of their hitzone list, never by a branch.**

**A general convex solver (GJK / SAT) instead of per-pair closed forms.**
Rejected on arithmetic: a general solver wins when the pair matrix is large, and
committing to **one target shape** keeps this at 4×1. *Sixteen is where you
write GJK; four is not.* Two further reasons: closed forms are exact and
non-iterative, and **a solid cone is convex only while its half-angle is under
90°** — so permitting `angle > 180` would make GJK silently wrong on the shape
this game uses most.

> **The trigger to revisit, recorded as a measurement rather than a mood:** the
> pair matrix reaching roughly **3×3**, or any hitzone or volume needing a
> **concave** shape.

**A `HitDetectionService`.** A Service wrapping one mechanic. The engine is a
module called by `CombatService`; the only Service here is `SpatialService`, and
it earns that because it owns state and a rule about who may read it.

**Content authoring the step count.** A designer who picks it per attack will
eventually pick a bad one, and **the failure is silent** — the attack still hits
things, just at the wrong moments. *The test: is this a design knob or a safety
property?*

---

## Part 17 — Naming

`TargetResolution`, not `HitboxSystem` — name it after what it *resolves*, not
what triggers it. It resolves a volume into a set of entities. A player swing, a
boss slam, a DoT aura tick and a future zone hazard all need the identical five
stages; `HitboxSystem` implies attacks own it, and the first hazard would feel
like a hack.

`motion`, not `path` or `drive` — it is a property of how the volume *moves*,
and a track's data is what a `PATH` motion reads. `motion = PATH`
reads as a sentence; `path = PATH` reads as a stutter.

**The document is called Hit Detection because that is what someone looking for
it will search for.**

---

## Related Documents

| Document | What it covers that this one does not |
|---|---|
| `Hurtboxes.md` | Studs, `Vector3`, `CFrame`, and the procedure for authoring a hurtbox by hand |
| `Animation.md` | Clips, upload, ownership, manifest, and why a marker never drives damage |
| `Timeline.md` | The Score, the Conductor, and what a beat is on the client side |
| `Architecture-Reference.md` | The generic-engine test, the phase boundaries, the Component contract |
| `Implementation-Status.md` | What is actually built, authoritatively |

---

## Appendix — What Changed On 2026-08-21

A single day's conversation reversed or corrected seven things. Listed together
because the *pattern* is more useful than any individual entry.

| # | Was | Is | What caused the error |
|---|---|---|---|
| 1 | A hitbox is typed numbers | It has a `motion` field — Part 9 | An assumption nobody had attacked, because no requirement had tested it |
| 2 | Art-driven hitboxes rejected: *"the precision is available from `sweep`"* | False. `sweep` rotates about Y only | Generalising from the one attack that existed |
| 3 | Hitboxes never need history | True only for formula-driven ones | A conditional claim stated unconditionally |
| 4 | `BAKED` is a motion kind | It is an authoring route for `PATH` | A way of **producing** data filed as a way of **consuming** it |
| 5 | `PATH` is the default, flatly | Ownership decides — 9.0a | Asking "which is better" instead of "better for what" |
| 6 | Hurtbox zones offset from the **root** | Offset from **their own limb** — 7.2a | A simplification adopted to dodge an open question, not revisited when the question closed |
| 7 | Every rig has parts to anchor to | Skinned meshes have `Bone`s and no limb parts — 7.2b | Describing one rig kind as though it were the only one |

**Three of those (3, 4, 6) share a shape worth recognising:** a statement that
was true under conditions nobody wrote down, left standing after the conditions
changed. The defence is not more care at the time — it is recording *what a
claim depends on* alongside the claim.

**And the reason this Part was re-argued so many times** is entry 5. "Which is
better" has no stable answer, so it never stayed settled. "Better for which
ownership" resolves once.
