# Shattered Realms — Hit Detection
### The Spatial Layer, and the One Question It Answers

> **This document is self-contained on purpose.** `EventTape.md` could defer
> every *why* to Architecture-Reference Part 12, because Part 12 argued
> EventTape out in full. There is no equivalent Part for hit detection —
> Part 13 spends four paragraphs promising latency-tolerant hit registration
> and never says how, and nothing else in the reference touches space at all.
> So this file owns the reasoning **and** the implementation map.
>
> What it does **not** own is the frames it plugs into: the four-phase
> resolution boundary (Part 11.1), the client trust model (Part 13), the
> Component contract (Part 7), and the Scheduler (Part 14). Where those
> apply, this file links. It does not re-argue them, and it must never
> restate them — two documents holding the same rule drift, and each stays
> internally consistent while disagreeing with the other.
>
> **Status:** the spatial layer is **BUILT** — `Spatial` and `SpatialService`
> exist, carry 24 tests in the boot suite, and have been run in a Team Test
> session. Everything downstream of them — hit volumes, `TargetResolution`,
> the DETECT phase — is **DESIGNED, UNBUILT**. Per-section tags below.
>
> - **BUILT** — exists, has tests, has been run.
> - **DESIGNED** — the shape is decided and the reasoning is recorded.
> - **MEASURED** — an empirical question that has been answered, with the
>   figure and how it was obtained.
> - **OPEN** — a real decision deliberately left unmade, with the trigger for
>   making it.
> - **GAP** — a known hole, named here so it is not mistaken for an oversight.

---

## Boundary

| Architecture-Reference owns | This document owns |
|---|---|
| Why validation precedes resolution (Part 11.1) | Where DETECT sits between them |
| Why the client reports intent only (Part 13) | The one field that amendment adds |
| Why rewind input is server-measured (Part 13) | The rewind arithmetic itself |
| Why Components hold state and Services hold rules (Part 3, 7) | What `Spatial` holds and `SpatialService` decides |
| Why steps mutate a context and nothing else (Part 11.1) | Why target-finding is not a pipeline |
| The Scheduler contract (Part 14) | The one row it adds, and why ordering is unaffected |

---

## 1 — What Is Actually Missing

**Status:** DESIGNED.

```
grep -rln "CFrame\|Vector3\|Position\|Raycast\|Touched" src/ --include=*.luau
```

Returns nothing. There is no spatial code in this project. Every Component is
abstract — `Identity`, `Stats`, `Buffs`, `StateFlags`, `Equipment`,
`Inventory`, `Resources`, `AIState` — and not one of them knows where its
entity is. `EnemyEntity` is never constructed anywhere.

That makes hit detection not a feature but a **missing layer**, and three
things already written depend on it:

| Already written | What it needs from here |
|---|---|
| `CombatService:OnAttack` — "is the target in latency-tolerant range" | Something to ask |
| Part 13 — Latency-Tolerant Hit Registration | A position history to rewind through |
| The mitigation system — dodge, parry, block, Void | Attacks that occupy space, so that moving out of it means something |

The last one is the load-bearing one. A dodge that does not move you out of
anything is a button that grants i-frames, and the entire design premise —
that class choice matters per-fight because attack *categories* gate
mitigation — collapses into a timing minigame with no geometry.

---

## 2 — The Model: Two Volumes, Two Owners

**Status:** DESIGNED.

Fighting games draw a line this project needs and does not have. An attack
has a **hitbox** — the volume it fills while swinging. A body has a
**hurtbox** — the volume that can receive one. They are different objects,
owned by different things, and they change on different schedules.

| | Hitbox | Hurtbox |
|---|---|---|
| Belongs to | an attack | an entity |
| Declared in | the Content Layer, per skill | the `Spatial` component |
| Exists | only during the active window | always |
| Shape | box, sphere, arc, capsule | a sphere, always (§7) |

The whole of this layer answers one question, and it is worth writing down
in the narrowest possible form:

> **Given a hitbox, a pose, and a moment in time — which entities' hurtboxes
> were inside it?**

Notice what is *not* in that sentence. Not damage. Not whether the hit
counted. Not parry, block, dodge, or invulnerability.

**DETECT finds bodies. It never decides whether a hit lands.**

That boundary is what keeps this layer small, and it is not a stylistic
preference. Mitigation already has a home: `StateFlags` holds
`INVULNERABLE`, and the INTERCEPT phase of `DamageResolution` already owns
parry, block, dodge, and shield absorption (Part 11.1). If DETECT started
skipping invulnerable entities "as an optimization," mitigation logic would
live in two places, the pipeline's INTERCEPT steps would silently never run
for those entities, and the first bug would be a parry that awards no
stagger because the parrier was never returned as a target at all.

So DETECT returns the dodging player. INTERCEPT decides they dodged.

---

## 3 — DETECT: A Fifth Phase

**Status:** DESIGNED.

Part 11.1 defines four phases with hard boundaries. Hit detection fits none
of them, and forcing it into one breaks something:

- **Not VALIDATE.** Validation is legality — owns the skill, off cooldown,
  allowed to act. Those are cheap table lookups. Target-finding is the
  expensive operation in the whole flow, and it must sit *behind* the cheap
  checks so an illegal action never pays for it. That is also a security
  property: the rate limiter and the cooldown check both gate the spatial
  query, in that order.
- **Not RESOLVE.** The pipeline's contract is pure arithmetic on a context
  (Part 11.1). Target-finding is a query about the world, and it runs
  **once per activation** while RESOLVE runs **once per target**. They are
  not the same loop.

So it is its own phase, and it sits between them:

```
VALIDATE   Service.   Is this legal?              once per activation
DETECT     Service.   Who is inside the volume?   once per activation   ← new
RESOLVE    Pipeline.  How much, to this one?      once PER TARGET
COMMIT     Service.   Apply it.                   once per target
ANNOUNCE   Service.   One diff for the whole thing.  once per activation
```

**This changes `CombatService:resolveAttack`'s shape.** It currently takes a
singular `target`. A cleave produces a set. The correction is that
`resolveAttack` keeps its single-target signature and becomes the *inner*
call — DETECT produces the set, and the Service loops it. `DamageResolution`
does not change at all, and `AttackContext` does not learn what a volume is.

ANNOUNCE stays once per activation. One swing that hits five mobs is one
outbound diff carrying five entries, not five messages — the same reasoning
as Part 8's "one calculation, cosmetic fragmentation."

---

## 4 — The Spatial Layer

**Status:** DESIGNED.

Two new pieces, in exactly the relationship `StateService` and `StateFlags`
already have: the Component holds the data, the Service holds the rules and
is the one door.

### `Spatial` — the Component

The first Component that references a Roblox Instance, which is a departure
worth naming rather than slipping in. Part 3 requires a Component's truth be
"checkable by looking at itself alone," and this one satisfies that: it can
answer "am I anchored, and where" without consulting anything else.

| Holds | Invariant |
|---|---|
| `anchor` — the entity's `BasePart` in the world | reports unanchored rather than erroring when the instance is gone |
| `radius` — the hurtbox sphere | positive, set once at attach |
| `history` — a fixed ring buffer of `{ t, cf }` | fixed length, allocated once, never grows |

The ring buffer is preallocated at attach and never resized. Nothing in this
layer allocates per query, per frame, or per hit.

### `SpatialService` — the Authority

Stores nothing. Owns three rules: when to sample, how to rewind, and who is
attached.

```
attach(entity, anchor, radius)     registration is explicit
detach(entity)
tick(dt)                            samples every attached entity, 30Hz
poseAt(entity, t) -> CFrame?        the rewind query
candidatesNear(position, radius)    broadphase, last-known positions
```

**Registration being explicit gives a second thing for free: the set of
attached entities *is* the candidate set.** There is no entity registry in
this codebase — `ServerManager.players` holds players and nothing holds
enemies — and this layer does not need one invented. Anything that can be
hit is, by definition, something that registered a hurtbox.

**Why an authority Service.** Same argument as `StateService`: if every
damage source read `entity.spatial.history` directly, the first source that
forgot to rewind would make lag compensation mean "compensated for whatever
remembered to compensate." One door, or the guarantee is not a guarantee.

**Place scope.** Every place, for a reason that is not Part 13's persistence
test — nothing here survives a teleport. Every place has entities standing
somewhere, including the Hub.

---

## 5 — The Sampler

**Status:** DESIGNED.

One Scheduler row:

```lua
{ service = "SpatialService", hz = 30 },
```

**30Hz, not 60.** Roblox replicates character position at roughly 20Hz. A
60Hz sampler writes each replicated position into three consecutive slots and
learns nothing from two of them. 30Hz is already oversampling the source.

**Buffer length** is `MAX_REWIND × 30`, rounded up. At a 0.5s ceiling that
is 15 slots. Fifteen `CFrame`s per entity is on the order of a kilobyte;
two hundred entities is a fifth of a megabyte. Memory is not a consideration
here and should not be designed around.

**The Scheduler's existing ordering does not need to change, and this was
checked rather than assumed.** `Scheduler.start` drains the EventTape router
*before* any service ticks, so an event processed this frame rewinds against
a buffer whose newest sample is one frame old — up to 33ms stale on the
newest end.

That is harmless in both directions, for different reasons:

- **Player attacks never read the newest end.** The rewind target is always
  at least the interpolation constant into the past (§6), which is 100ms.
  The newest three samples are never the ones consulted.
- **Enemy attacks do read it**, but the underlying character replication is
  already 50ms+ behind. A 33ms sampler lag is a small addition to an error
  that already exists and is already compensated for by the telegraph.

If that ever stops being true, the fix is a `preTick` hook in the Scheduler,
not a reordering of the drain — the drain-first rule exists so a tick never
sees a half-applied frame, and that reason has nothing to do with sampling.

---

## 6 — Lag Compensation

**Status:** DESIGNED. One **OPEN** item and one **GAP**, both named below.

Part 13 already commits the input: *the rewind window is derived from
server-observed latency, never a client-supplied value.* This section owns
the arithmetic that commitment implies.

### The two directions are not symmetric

This is the core of the design, and getting it backwards produces a system
that feels worse than no compensation at all.

**Player attacks an enemy — the active window has already happened.**
The client played its attack animation optimistically the moment the button
was pressed (Part 15). By the time the event reaches the server, the frames
where that swing was live are in the past *on the client*. So the server
rewinds to when the client saw them, and detection runs immediately.

**An enemy attacks a player — the active window has not happened anywhere.**
`AIService` decides to swing; the Telegraph/Execute pattern (Part 5) fires a
telegraph, waits ~1.0–1.2s, then executes. Detection is *scheduled* for the
execute moment and runs with no rewind at all. The telegraph **is** the
compensation — it is why that pattern exists — and rewinding on top of it
would retroactively hit a player who visibly dodged in time.

One engine serves both. The only difference is the timestamp handed to it.

```
player attack   →  resolve(volume, at = now - rewind)
enemy attack    →  resolve(volume, at = now)            scheduled, not delayed here
```

### The rewind arithmetic

Derived rather than copied, because the derivation is what makes it
checkable. Let `L` be one-way latency and `I` the client's interpolation
delay:

```
server sends snapshot at             T
client receives it at                T + L
client is rendering state from       T − I        (it interpolates)
client presses attack at wall time   T + L
command reaches server at            T + 2L
server's clock now reads             T + 2L

rewind = (T + 2L) − (T − I) = 2L + I
```

**The rewind is a full round trip plus interpolation, not half of one.**
Every "backtrack by half the ping" implementation is either using a
one-way-latency figure, or is under-rewinding.

```
rewindTo = workspace:GetServerTimeNow() − roundTrip − INTERPOLATION_CONSTANT
clamped to [now − MAX_REWIND, now]
```

| Constant | Value | Why |
|---|---|---|
| `INTERPOLATION_CONSTANT` | 0.1s | Roblox character replication is ~20Hz and clients interpolate on top of it. Both open-source Roblox rewind implementations converged on this figure independently. |
| `MAX_REWIND` | 0.5s | Past this, a player is being hit by something that left their screen half a second ago. Also the exploit ceiling: it bounds what a manipulated latency figure could buy. |

**Clock source is `workspace:GetServerTimeNow()`, never `os.clock()`.**
`os.clock()` has an arbitrary per-process origin and returns different values
on client and server. `SkillService._cooldowns` and `AttackContext` already
use `os.clock()`, and that stays correct — those are server-local durations
that no client reasons about. Anything a client also sees uses server time.
The two must not be mixed in one comparison.

### MEASURED — `GetNetworkPing()` returns seconds

**Status:** RESOLVED for the unit. One sub-question deliberately left open.

Measured in a Team Test session, against an independently measured round
trip: `GetNetworkPing()` read **0.0122–0.0150** while the probe's own round
trip floor was **~38ms**. As milliseconds that would be twelve
*microseconds* — below the cost of the call. As seconds it is 12–15ms, an
ordinary ping. It returns **seconds**, despite being widely described,
including in its own release notes, as milliseconds.

**This is the single most valuable thing the probe found, and it is worth
recording why it was nearly missed.** The code read the value as
milliseconds and multiplied by `2/1000`, producing a latency term of 24
microseconds. `rewindWindowFor` therefore returned exactly
`INTERPOLATION_CONSTANT`, and lag compensation did nothing whatsoever.
Nothing errored. No test failed — every unit test asserts on arithmetic and
clamping, and the arithmetic was correct on a wrong input. The only reason
it surfaced is that the probe printed the resulting window and `0.100s` was
too round a number to be a coincidence.

The general lesson, which applies past this one constant: **a unit error in a
value that feeds a clamp is invisible to tests.** Anything reading a figure
out of an engine API deserves one log line showing the derived value, not
just a test proving the formula.

> **OPEN — round trip or one way?** The probe cannot separate them. Its own
> client-turnaround overhead measured 14–26ms and varied run to run, which is
> larger than the 12–15ms signal. Two runs at effectively identical real
> latency produced round trip floors of 38ms and 100ms, confirming the
> measurement is dominated by scheduling rather than network time.
>
> **This is now a low-stakes question, which it was not before.** At 12–15ms
> the two readings differ by ~12ms of rewind against a 100ms interpolation
> constant — under 12% of the window. `PING_TO_ROUND_TRIP` stays at `2`, the
> over-rewinding reading. It only becomes worth settling above ~200ms ping,
> and there `MAX_REWIND` is the binding constraint regardless.
>
> **The real tuning lever is `INTERPOLATION_CONSTANT`, not this.** At
> realistic pings it contributes most of the window, and it was taken from
> two third-party implementations rather than measured here.

### Defense is generous, offense is exact

For **player attacks**, the rewound position is used exactly. What the player
saw is what counts.

For **enemy attacks**, the player gets the most favourable reading available:
if they were outside the volume at *any* sample across the last round trip,
they dodged.

Both rules favour the human. The cost is that a high-ping player is
marginally harder to hit, which is the same trade every "favor the shooter"
system makes, pointed at defense instead. It is worth paying: a player who
dodged on their own screen and took damage anyway will not accept any
explanation, and a boss that occasionally misses a laggy player costs
nothing.

> **OPEN — whether enemy-attack generosity is sampled or continuous.**
> Sampling the buffer at the enemy's active window is simple and is the
> starting point. Whether a swept test between samples is needed depends
> entirely on how fast attacks and players actually move, which is not known
> yet. Decide it the first time a playtest produces a "I dodged that" report,
> not before.

---

## 7 — Hurtboxes Are Spheres

**Status:** DESIGNED. The commitment is to the *shape*, not to the count.

Every hurtbox is a sphere. Never an oriented box, never a capsule. **One
sphere per entity today; a list of them when breakable parts arrive**, which
is planned rather than hypothetical — see below. Growing from one to many is
additive and changes nothing about how a volume is declared or resolved,
which is exactly why the count is safe to defer and the shape is not.

The argument for the shape is that a sphere is **rotation-invariant**, and
that single property removes an enormous amount of machinery. Every
narrow-phase test becomes shape-vs-point-plus-radius: exact, branchless,
closed form. Box-vs-box needs separating-axis tests, and box-vs-box *at a
rewound orientation* needs them per candidate per sample. A sphere at a
rewound position is just a position. None of the alternative buys anything
for a game whose smallest hitbox is a sword swing and largest is a boss slam.

### The case that looks like it needs limb hurtboxes, and does not

Directional parry reactions — "the boss should recover differently depending
on where the parry connected" — read like the first real demand for
per-limb geometry. They are not, and the reason generalises.

**A parry is not a hit on the parried entity's body.** It intercepts that
entity's incoming *attack*. So "where did the parry land" is not a question
about anatomy, and answering it with anatomy gives the wrong answer: a
player standing near a boss's leg who parries its overhead claw swing is
nearest the leg hurtbox, while the thing that must recoil is the claw.

The reaction is a lookup on two values that cost nothing:

| Value | Source |
|---|---|
| which limb or weapon swung | already declared on the attack, beside its category and volume |
| which sector the parrier stood in | one dot product against the attacker's facing, quantised to 4–8 sectors |

Both are already available. Neither is geometry this layer has to produce.

**The general rule this is an instance of:** hurtboxes answer *whose body was
in this space*. Anything asking *what was the attacker doing, and from where*
is attack data plus a relative angle, and routing it through hurtboxes
converts a cheap exact answer into an expensive approximate one.

### PLANNED — breakable parts

Not hypothetical. Breakable parts are wanted, and the design document already
assumed them before this file existed: the Phase Transitions section uses
"destroy the angel boss's wings" as its worked example and explicitly budgets
*unique hitbox per part*. This is scheduled work.

**It costs less than it looks, because the hurtbox list and the part system
are the same object.** The obvious reading is two costs — add a sphere list
for detection, then add per-part damage accounting on top. They are one
component. The spheres that let detection report *which* part was hit are the
same spheres carrying that part's HP pool, its broken flag, and what breaking
it triggers. There is no separate part registry, and nothing has to keep two
representations of "the tail" agreeing with each other.

The whole extension:

| Change | |
|---|---|
| `Spatial` holds a list of spheres rather than one | each with an id, a local offset and a radius |
| `TargetResolution` returns `(entity, partId)` | narrow phase already tests per sphere; it only has to report which one answered |
| `AttackContext` gains `partId` | one field, and it clears Rule 1 — several steps genuinely read it |
| DEFENSE reads it | a part whose armor is broken applies reduced reduction, which is the Monster Hunter loop falling out of machinery that already exists |

Nothing about how volumes are declared, anchored or resolved changes.
Deferred only because no boss is authored yet — not because anything here is
unsettled.

**Armor shedding on an HP threshold is not this layer's problem at all.** It
reads to a player like the same thing, but there is no per-part accounting in
it: a threshold fires and pieces come off. That is a phase transition, and
`Phases` already holds HP thresholds. The two systems are distinguished in
the design document under Phase Transitions.

---

## 8 — HitVolume: The Declarative Half

**Status:** DESIGNED.

Per Part 2, the generic engine is `TargetResolution` and the declarative
configuration is a `HitVolume` — a plain table on a skill definition,
describing a shape and nothing else. Adding a new attack shape to the game
is a data edit. Adding a new *kind* of shape is one entry in the vocabulary
plus one overlap function.

| Shape | Fields | For |
|---|---|---|
| `SPHERE` | `radius` | point-blank AoE, ground markers, explosions |
| `BOX` | `size`, `offset` | cleaves, walls, rectangular zones |
| `ARC` | `radius`, `angle` | the standard melee swing, MapleStory-style sweeps |
| `CAPSULE` | `length`, `radius` | thrusts, beams, dash attacks |

Common to all four:

| Field | Default | Meaning |
|---|---|---|
| `anchor` | `ATTACKER` | `ATTACKER` or `POINT` — a ground-targeted AoE anchors to a location, not a body |
| `activeWindow` | `0` | seconds the hitbox is live; `0` is instantaneous |
| `samples` | `1` | how many times to evaluate across that window |
| `maxTargets` | `nil` | unlimited; a cap makes a skill single-target by data |
| `requiresLineOfSight` | `false` | one raycast per surviving candidate, after narrow phase |
| `aimSource` | `FACING` | `FACING` or `CLIENT_AIM` — see §10 |

**`samples` exists because one instantaneous query can miss.** A wide swing
that is live for 120ms while a mob runs through it will return nothing if
sampled once at the wrong instant. Sampling three times across the window
and unioning the results fixes it.

**Results are deduplicated by entity id before RESOLVE runs.** An entity
caught by all three samples of one swing takes one damage roll — Part 8's
rule, enforced here rather than trusted to the caller.

**Line of sight is deliberately not part of target-finding.** It is a
separate raycast against world geometry, run last, on the few candidates that
already passed. Folding geometry into the overlap tests is how a hitbox
system ends up hitting a wall and walking its ancestry trying to work out
whose body it belongs to.

---

## 9 — TargetResolution: The Engine

**Status:** DESIGNED.

```
TargetResolution.resolve(query) -> { entity }
```

`TargetQuery` mirrors `AttackContext` in spirit — a declared shape, not a
scratch bag, and the same Part 11.1 rule applies: a field goes in only if two
stages genuinely share it.

| Field | |
|---|---|
| `attacker` | the entity swinging; excluded from its own results |
| `volume` | the `HitVolume` table |
| `at` | server timestamp — the one parameter that distinguishes the two directions (§6) |
| `origin` | resolved pose; `nil` means derive it from the attacker |
| `faction` | who may be hit |
| `preferredId` | the client's `targetId` hint, if any (§10) |

### It is not a pipeline, and that is deliberate

`DamageResolution` earns its phases-and-registration machinery because Part
11.1 counts twelve-plus modifier types that will genuinely accumulate: armor,
crit, lifesteal, reflection, execute thresholds, stagger, barriers. Part 2's
Test 3 is "ten or more things sharing real structure," and damage clears it.

Target-finding has five stages and will still have five stages in a year:

```
ORIGIN    where the volume sits — the attacker's rewound pose, or a point
BROAD     squared-distance cull against last-known positions
NARROW    exact overlap, at rewound positions, per sample
FILTER    self, faction, and unattached entities
LIMIT     maxTargets, with preferredId sorted first
```

They do not accumulate, they are not independently authored, and nobody will
ever need to register a sixth from a content file. Part 2 has an explicit
section on not applying this pattern where it does not fit, and this is what
it is describing. An ordered sequence in one readable module, with no
registration API.

### Broadphase

A squared-distance cull against each attached entity's last-known position,
with a conservative margin:

```
cullRadius = volumeReach + entityRadius + (maxEntitySpeed × rewindWindow)
```

The last term is what stops the cull from discarding an entity that has since
run out of range but *was* inside the volume at the rewound moment.

> **GAP — no spatial partitioning.** The broadphase is a linear scan. At the
> scale the design implies — on the order of a hundred mobs in a farm zone —
> a hundred squared-distance comparisons per swing is microseconds, and a
> spatial hash would be machinery bought before it is needed. **The trigger
> for revisiting: broadphase appearing in a profile at all, or attached-entity
> count passing ~500.** Recorded here so that adding one later is a decision
> with a number behind it rather than a reaction.

---

## 10 — The Trust Amendment

**Status:** DESIGNED. This is the one place this document *changes* something
Architecture-Reference already states, rather than extending it.

Part 13's client-report table currently reads:

```
ALLOWED — intent only:      "I pressed attack" / "I clicked enemy ID X"
NEVER — values or state:    "I dealt 450 damage" / "My HP is 80"
```

Two additions:

| | |
|---|---|
| **Add to NEVER** | "I hit these five enemies." The server computes every target set. There is no code path that accepts one. |
| **Add to ALLOWED, conditionally** | "I am facing this direction" — a unit vector, and only for volumes that ask for it. |

### Why a direction is needed at all, and why most attacks do not need it

The volume's *origin* is always the server's own rewound view of the
attacker. Only the *direction* is in question, and for a wide arc the
replicated facing is good enough: at 100ms round trip, a player turning at
180°/s has moved 18° — inside the tolerance of a 90° cleave, and nowhere near
it for a 360° point-blank.

So `aimSource` defaults to `FACING`, and **most attacks introduce no new
trust whatsoever.** Only narrow volumes — a thrust, a beam, a long capsule —
set `CLIENT_AIM`, and those are the ones where 18° actually misses.

What a client gains by lying about direction: it can swing somewhere it was
not facing. It could have achieved the same thing by turning. The exploit is
worth nothing, which is why a generous clamp against replicated facing is
sufficient and a tight one is not worth the false rejections.

### `targetId` is demoted, not removed

It stays on `CombatEvent` for click-target and tab-target attacks, but it
stops being an instruction and becomes a **hint**. The server always computes
the set; `preferredId` only sorts within it, and a `targetId` naming an
entity that is not in the computed set is simply ignored.

The point is that there is **one code path**. A trusted-target fast path
alongside a computed-volume path is two systems that must agree about range,
line of sight, and validity — and the trusted one would be the one exploited,
precisely because it is the one that skips the work.

---

## 11 — The File Map

| Module | Owns | Tree | Status |
|---|---|---|---|
| `components/Spatial.luau` | anchor, hurtbox radius, position ring buffer | `serverShared` | **BUILT** |
| `services/authority/SpatialService.luau` | sampling, rewind, attachment registry | place `server/` | **BUILT** |
| `resolution/TargetResolution.luau` | the five-stage sequence | place `server/` | UNBUILT |
| `resolution/TargetQuery.luau` | the declared query shape | place `server/` | UNBUILT |
| `resolution/targeting/HitVolume.luau` | shape vocabulary, defaults, validation | place `server/` | UNBUILT |
| `resolution/targeting/Overlap.luau` | the four sphere-vs-shape tests. Pure math, no requires. | place `server/` | UNBUILT |

Built alongside them: `boot/Scheduler.luau` gained its 30Hz row,
`boot/PlaceManifest.luau` lists `SpatialService` under `authority`, both
entity types carry a `spatial` component, and `tests/SpatialTests.luau`
holds 24 cases — most of them on the ring buffer's wrap, which is the part
that would fail silently after the first half second of uptime.

`diagnostics/PingProbe.{server,client}.luau` are **temporary** and can be
deleted: the question they existed to answer is answered in §6.

**Everything is server-only, and none of it goes in `src/shared/`.** Per Part
13, `ReplicatedStorage` is a broadcast: putting the volume table there would
publish every skill's exact reach and arc to any client that cares to read
it. The client needs none of it — it plays an animation and waits for a diff.

Changes to files that already exist:

| File | Change |
|---|---|
| `boot/Scheduler.luau` | one row: `{ service = "SpatialService", hz = 30 }` |
| `boot/PlaceManifest.luau` | `SpatialService` under `authority` |
| `entities/PlayerEntity.luau`, `EnemyEntity.luau` | a `spatial` component |
| `services/domain/CombatService/init.luau` | the DETECT phase; `resolveAttack` becomes the inner call of a loop |
| `types/CombatEvent.luau` | an `aim` field, required only by subTypes whose volume asks for it |

---

## 12 — Known Gaps

**Status:** GAP — each named so it is not mistaken for an oversight.

| Gap | Why it is acceptable now | Trigger to fix |
|---|---|---|
| Round trip vs. one way still unseparated | Resolved to be low-stakes: ~12ms of difference against a 100ms constant (§6) | A playtest above ~200ms ping that feels wrong |
| `INTERPOLATION_CONSTANT` is borrowed, not measured | It contributes most of the rewind window at realistic pings, so it is the lever that matters — but 0.1s is two independent implementations' answer | First playtest where hits feel late or retroactive |
| No spatial partitioning | Linear scan is microseconds at design scale | Broadphase appears in a profile, or ~500 attached entities |
| Single-sphere hurtboxes | **Planned, not rejected** — breakable parts are wanted and the extension is purely additive (§7) | The first boss authored with a breakable part |
| No projectiles | A projectile is a volume that moves over time — a different engine, not a shape | The first skill that fires something with travel time |
| Line of sight unimplemented | The flag exists; no map yet has cover that matters | The first arena with pillars |
| Nothing registers with `SpatialService` | `EnemyEntity` is not constructed anywhere in the codebase | Whatever spawns enemies gets written |
| Aim clamp tolerance untuned | The exploit it prevents is worth nothing (§10) | Never, unless a narrow-volume skill proves abusable |

---

## 13 — Rejected Designs, Compressed

**`.Touched`.** Fires on the physics thread, misses fast-moving contacts
entirely, cannot be rewound, and gives no control over when it runs relative
to the drain. It is the default answer in most Roblox tutorials and it is
wrong for anything server-authoritative.

**Hitbox parts parented into the workspace and moved.** Allocation churn per
swing, unwanted physics interaction, and — decisively — you cannot move a
part into the past. Every rewound query would need a different mechanism
anyway, which means two systems.

**Two engines: live `GetPartBoundsInBox` for cheap cases, buffer math for
compensated ones.** Two code paths that must agree and will drift. The
buffer engine subsumes the live one — a rewind of zero is the newest sample —
and it is *more* correct besides: a buffer query can only ever return a
registered entity, so the classic Roblox bug where you hit a part and walk
its ancestry guessing whose body it is cannot occur.

**Client detects, server validates.** Genuinely tempting: it feels sharper
and moves broadphase cost off the server. Rejected because the client would
then report a target list, which is the exact line Part 13 draws — and the
server-side re-check becomes load-bearing rather than a backstop, which is a
much worse place for it to be. Explicitly reconsidered and explicitly
declined.

**`TargetResolution` as a registered-step pipeline.** Symmetry with
`DamageResolution` is not a reason. Five stages that will not grow do not
need a registration API (§9).

**Oriented-box hurtboxes.** Buys limb precision nothing needs, costs
separating-axis tests per candidate per sample (§7).

**A `HitDetectionService`.** This would be a Service wrapping one mechanic,
which is the sprawl Part 11.1 exists to prevent. The engine is a module
called by `CombatService`; the only Service here is `SpatialService`, and it
earns that because it owns state and a rule about who may read it.

---

## 14 — Naming

`TargetResolution`, not `HitboxSystem`, and the reason is Part 11.1's own:
name it after what it *resolves*, not what triggers it. It resolves a volume
into a set of entities. A player swing, a boss slam, a DoT aura tick, and a
future zone hazard all need the identical five stages — `HitboxSystem`
implies attacks own it, and the first hazard would feel like a hack.

The document is called Hit Detection because that is what someone looking for
it will search for.
