# Next Steps

### The work queue for hit detection and animation, with the reasoning behind each item

> **Why this document exists.** `Implementation-Status.md` records what is
> built. `HitDetection.md` records what was decided. Neither says **what to do
> next, in what order, and why that order** — which is the thing that
> evaporates between sessions and gets re-derived from scratch.
>
> Written 2026-08-22, after a day that reversed seven decisions. Every item
> below carries the argument that put it where it is, so the ordering can be
> attacked on its merits rather than trusted because it is written down
> (`WorkingAgreement.md`).

---

## Where things stand

**Hurtboxes are mid-rebuild and the new half is visible but inert.**

| | |
|---|---|
| `HurtboxComponent` + `HurtboxDefinitions` | **BUILT.** Ten limb-anchored capsules for a player, one for a dummy |
| `HurtboxDebug` | **BUILT.** Draws them welded per-limb; `DebugHurtboxLog` prints per-zone positions |
| Checked by eye | **Yes.** Confirmed to sit correctly on the body and follow the pose |
| Resolution | **still tests the OLD single capsule** |

**Two shapes currently describe one body.** That is a deliberate, labelled
transitional state — the zone numbers were eyeballed, so they got drawn and
looked at before anything hit with them. It is not a state to leave standing.

---

## 1 — Per-zone history

**Status:** UNBUILT. **This blocks everything else.**

### What

Each zone needs its own ring buffer, rather than one buffer per body.

### Why it blocks

Resolution rewinds. Asking "where was this body 100ms ago" is currently one
lookup against one buffer — and **one buffer cannot serve ten zones that are in
ten different places at ten different moments.** A wing and a torso do not share
a position, so they cannot share a history.

Until this exists, resolution physically cannot test zones, which is why the
overlay is drawing something the game does not use.

### Cost, measured rather than guessed

```
10 zones x 47 slots x a CFrame   ~=  30KB per body
20 bodies                        ~=  0.6MB
sampling                              10 CFrame reads per body at 30Hz
```

Affordable. The single-buffer design was chosen to avoid depending on whether a
server script can observe animated limbs — `LimbProbe` answered that (it can),
and the simplification outlived its reason.

### Watch for

The buffer is preallocated and never grows, deliberately: this is written by a
30Hz tick for every entity forever, and a buffer that reallocated would be the
one piece of the combat path producing garbage on a fixed schedule. Ten of them
per body must keep that property.

---

## 2 — `TargetResolution` loops zones

**Status:** UNBUILT. Depends on step 1.

### What

The narrow phase becomes per-zone: for each candidate, for each zone, test.

### The trap, and it is the one that will cost hours

> **The broadphase cull must switch to `boundingRadius()`.**

With a zone list, an entity's real extent is **its furthest zone**, not its
body. Cull against the torso's radius and you silently drop a body whose
outstretched arm genuinely *was* inside the volume.

**That failure looks identical to broken overlap math and is far harder to
find, because the exact test never runs to be debugged.** `HurtboxComponent`
already computes `boundingRadius()` for exactly this and nothing calls it yet.

### What does not change

Dedup. The `seen` set already guarantees once-per-activation, so a body caught
on two zones is still one hit and one damage roll.

---

## 3 — Delete the single capsule

**Status:** blocked on 2.

`SpatialService:attach` loses its `radius` and `halfHeight` parameters.
`SpatialComponent` loses its capsule fields. `HurtboxDebug` loses its fallback
path, and its boot message loses the note saying the zones are not what hits.

**Do not skip this and leave both.** Two shapes describing one body is exactly
the drift this codebase keeps closing elsewhere.

---

## 4 — Tests

Three cases carry the whole change:

| Test | Proves |
|---|---|
| A shot passing **between** two zones misses | the gaps are real — this is the bug the rebuild exists to fix |
| A shot into one zone hits | the zones are wired to resolution at all |
| A body overlapping **two** zones produces exactly **one** hit | dedup survived the loop |

The first one is the important one. One enveloping capsule made the space
between a large enemy's limbs hittable; if that test does not pass, nothing was
actually gained.

---

## 5 — The hitbox side: `motion = PATH`

**Status:** UNBUILT, designed in `HitDetection.md` Part 9.

### What

A hitbox is its own object with its own authored motion — a volume travelling a
path placed by hand, anchored to the attacker's root, evaluated by the server
from local data.

### The ordering argument

`PATH` needs the Conductor to author paths, and the Conductor needs animation
work started. Hurtboxes need none of that. **So hurtboxes finish first**, and
they are also where the known bug is.

### Two details that are easy to get wrong

**Store the pivot, not the blade tip.** Interpolating two *positions* gives a
straight line; a blade travels an arc. Storing the pivot's frame and letting
`CFrame:Lerp` interpolate the rotation spherically makes the arc exact at any
key density. Storing tip positions works on a dense recording and fails badly
on a hand-authored sparse one — the case nobody would think to check.

**Run the driver at 60Hz, not the sampler's 30Hz.** A blade tip covers ~45
studs/second. Tunneling is impossible while the hitbox moves less than the
smallest hurtbox radius per tick, and at 30Hz that is 1.5 studs against a
1.5-radius body — exactly at the limit. **And the hitzone list makes this
worse**: a 0.3-radius limb capsule is narrower than the gap 60Hz leaves.

---

## 6 — Then: Conductor, first animation, enemies

In order, and each one gated on the last:

1. **The Conductor** — plays a `Score`. Property tracks, action tracks, and clip
   tracks on one transport. `Timeline.md` has the design.
2. **The first real attack** — animate it, author its hitbox path against it,
   play it, swing it at a dummy.
3. **Give it to enemies.** They currently do not attack at all; that path was
   removed deliberately so the old `SWEEP` model would not be built twice.

**Blocked before any of this: the Roblox group must exist.** An animation asset
must be owned by the same account or group that owns the experience, group role
permissions are documented as not working properly for animations, and a
personal-account asset does not transfer — it gets re-uploaded. It is the only
irreversible step in the whole pipeline.

---

## Two gaps that will bite a fast boss

Neither is urgent. Both are cheap. Both produce symptoms that are impossible to
diagnose from inside the game.

**`MAX_ENTITY_SPEED = 120`** in `TargetResolution` is the broadphase margin —
how far anything could have travelled during the rewind window. **A boss that
flies faster than that gets silently culled from its own hit test.** No error,
no warning; swings just return nothing, and it looks like broken overlap math.

**Ping is sampled fresh per swing and never smoothed**, and
`INTERPOLATION_CONSTANT = 0.1s` is borrowed rather than measured. Both convert
into positional error linearly with target speed:

```
positional error = target speed x timing error

  20 studs/sec, 30ms off  ->  0.6 studs   fine
  60 studs/sec, 30ms off  ->  1.8 studs   eating the margin
 120 studs/sec, 30ms off  ->  3.6 studs   misses a 3-stud body
```

A slow boss is robust to this. A fast one is only as accurate as the ping
estimate.

---

## Settled — do not re-argue these

Each of these consumed real time and reached a conclusion with a reason. Attack
them with a better argument if there is one, but not from scratch.

| Settled | Because |
|---|---|
| **Server-authoritative.** Client-detects-server-validates stays rejected | stated preference, repeatedly: the client-tells-server pattern is disliked outright |
| **Ownership decides the hitbox model.** Server-animated rig → `LIVE`; client-animated → `PATH` | bone-attached colliders require synchronised skeletal animation on both machines. `LimbProbe` measured that we do not have it for client rigs (~0.104s) and do for server rigs |
| **Hitboxes are never real parts at test time** | a part only exists *now*, and this layer's job is answering about the past. Recording a part's motion at dev time is fine; testing against one is not |
| **Rewind stays** | dropping it would allow Roblox's built-in queries and delete a lot of code, at the cost of a player on 120ms ping missing shots that visibly connected |
| **Capsules, not exact mesh geometry** | curves do not survive export, and it would make every art change a balance change |
| **Zones ride their own limb, including for players** | the error is `limb speed x 0.104s`, which at walking speed is 0.30 studs against an arm capsule of radius 0.28 — under its own thickness. Root-anchoring bought exactness on zones that were never inaccurate and paid with a body matching nothing visible |

---

## Related

| Document | |
|---|---|
| `WorkingAgreement.md` | how decisions get justified here. **Read before proposing changes** |
| `HitDetection.md` | the design and the rejected alternatives. Part 0 is the orientation |
| `Hurtboxes.md` | the authoring manual — studs, `CFrame`, placing a capsule by hand |
| `Implementation-Status.md` | what is built and what is actually proven |
| `Timeline.md` | the Conductor and the Score |
| `Animation.md` | clips, upload, ownership, the manifest |
