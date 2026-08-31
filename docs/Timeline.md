# Timeline — now the Conductor

### Property tracks over time, why nothing in the engine plays them, the module that does, and the editor that authors them

> **THE SYSTEM IS CALLED THE CONDUCTOR AND THE DOCUMENT IT PLAYS IS A SCORE.**
> This file is still named `Timeline.md` and every reference to `Timeline.luau`
> below is stale by that much.
>
> The rename is not cosmetic. `Timeline.play(timeline)` uses one word for the
> engine and the data; **`Conductor.play(score)` reads as a sentence.** And a
> conductor's literal job is keeping an ensemble *in time*, which is the
> requirement this whole document exists for.
>
> The filename is doc debt. The concepts below are current unless a Part says
> otherwise.

> **REVISED 2026-08-23, and two things below were REVERSED.** Read Part 15
> before trusting Parts 9–10:
>
> 1. **The Conductor owns ALL client-side animation**, rig clips included.
>    Part 10.1's "they are separate, and neither reads the other" is overruled.
> 2. **The Score owns the clock.** An implementation that made a clip the master
>    and the Score a follower was built and reversed the same day; it made this
>    document's own headline example — the delayed slash — unexpressible.

> **What this document is.** Roblox ships exactly one animation player. It
> bends joints, and that is the entirety of what it does. Everything else that
> needs to change over time — a beam widening, a light dimming, a camera
> sweeping, a prop sliding open, a particle burst landing on a beat — has no
> engine behind it at all. Not a limited one. None. This document settles what
> fills that gap, what shape the data takes, where the code lives, what
> authors it, and what it is forbidden from doing.
>
> **Status of the system: BUILT 2026-08-23, NEVER RUN.** The engine, the
> triggers and the authoring tool all exist and boot; no Score has been played
> and no slider has been dragged. Part 13 has the file-by-file state.
>
> **Status tags** carry the same meanings as `Architecture-Reference.md`:
> SETTLED, PROVISIONAL, UNBUILT, SUPERSEDED.
>
> **Revision note, 2026-08-19.** The first revision of this document (written
> 2026-08-18) **rejected building an authoring tool** and recorded that
> rejection in Part 12. That rejection has been overturned deliberately, not
> drifted away from. Part 6.2 carries the original argument, what was wrong
> with it, and what replaced it. The correction is left visible because it
> carries more information than clean text would.
>
> **This document exists because the topic was circled for two long
> conversations** around whether a paid Studio plugin was required, and the
> answer moved three times inside the first one. The wrong turns were the
> informative part; they are kept in Part 12 rather than deleted.

---

## Table of Contents

1. Two Kinds Of Animation, And Why Only One Has An Engine
2. Why The Engine Cannot Do It — The Mechanism, Not The Complaint
3. What A Timeline Actually Is — Three Facts And A Loop
4. The Four Things That Are Actually Hard
5. Evidence From A Working Implementation
6. Authoring — Lua Tables, And The Editor Decision
7. The Editor — Document, Preview, Export
8. Where The Effect Objects Come From
9. Where It Lives, And What It Is Forbidden To Do
10. Rig Animation And Timelines — Two Layers, And The Seam Between Them
11. Scaling — What The Twentieth Effect Costs
12. Rejected Designs
13. Current State And The Prototype Plan
14. Open Questions

---

## Part 1 — Two Kinds Of Animation, And Why Only One Has An Engine

**Status:** SETTLED, verified 2026-08-18 against Roblox's current Animation
Editor and Inverse Kinematics documentation.

One word covers two systems that share nothing but a name. Separating them
resolves the entire question this document exists to answer.

| | **Rig animation** | **Property animation** |
|---|---|---|
| What moves | Joints on a jointed model | Any setting on any object |
| Examples | A sword swing, a walk cycle, a boss slam | Beam width, light brightness, camera position, transparency, particle rate |
| Authored in | Studio's Animation Editor (free) | Nothing. There is no editor |
| Stored as | A `KeyframeSequence` uploaded to Roblox's cloud | Nothing. There is no format |
| Played by | `Animator`, built into the engine | **Nothing. This is the gap** |
| Covered by | `Animation.md` | This document |

**The plain-language version, kept because it is the version that survives six
months away.** A jointed model is a puppet. A rig animation is a list of "at
0.3 seconds, bend the shoulder *this* far." Roblox's animation player is a
machine that reads that list and bends joints. Bending joints is its only move.
It has no hand for turning a dial on a lamp, and no concept that a lamp exists.

**A timeline is that second machine.** Same idea — a list of "at this time,
this value" — but the machine reads the list and *assigns settings* instead of
bending joints.

**What "rig" actually means is broader than it sounds, and this matters.** A
rig is anything whose parts are chained with `Motor6D` joints. A sword, a door,
a chest, a non-humanoid creature, a three-claw attack prop — add `Motor6D`s and
the free Animation Editor animates them fine. A rig with no `Humanoid` gets an
`AnimationController` with an `Animator` child, and then it animates like any
character.

**The gap is not "characters versus props." It is "joint transforms versus
everything else."** A claw sliding in and swiping is rig animation. The same
claw fading in and glowing is not.

---

## Part 2 — Why The Engine Cannot Do It — The Mechanism, Not The Complaint

**Status:** SETTLED. This Part is the load-bearing one. Everything after it
follows.

It is tempting to describe this as a file format that is too small, and then go
looking for a way to smuggle data into it. That framing is wrong and it wastes
time. The limitation is on the **playback** side, not the storage side.

### 2.1 — The addressing model

An animation file is this tree, and `Animation.md` Part 2 carries the same
structure for the same reason:

```
KeyframeSequence
└── Keyframe               (Time = 0.25)
    └── Pose               (Name = "RightUpperArm")
        ├── CFrame         ← position + rotation, the only payload
        ├── Weight
        └── EasingStyle / EasingDirection
```

A `Pose` has exactly one way of saying what it applies to: **its `Name`**,
matched at play time against a `Motor6D` or `Bone` of the same name on whatever
rig you play it on.

There is no `Pose` variant that says *instance = the beam in the workspace,
property = `Width`, value = `4`*. That is why "add a track" in the Animation
Editor opens a joint picker and never a property picker. **A track is a joint.**
That is the definition, not a UI shortcut.

### 2.2 — The part that closes the door

`Animator:LoadAnimation` returns an `AnimationTrack`. What the `Animator` does
every frame is, in full:

> for each `Pose` name in the clip → find the joint of that name on this rig →
> write `Motor6D.Transform` (or `Bone.Transform` on a skinned rig)

**`Transform` is the only thing it writes.** So even if a number were smuggled
into the file, nothing on the playback side would ever route it to a `Beam`.

**This is why extending the format is not the move.** Adding property animation
is not a format problem with a clever workaround. It requires a second player.
Writing that second player is the only available action, and Part 3 is how
small it is.

### 2.3 — The two exceptions, named precisely so they do not get re-discovered

Both of these look like counter-examples and neither one is.

| Exception | What it really is | Why it does not help |
|---|---|---|
| **Facial animation** | The newer `CurveAnimation` format holds named `FloatCurve` tracks — plain numbers, not joint rotations — and facial clips use them | The numbers exist, but the `Animator` routes them only to a `FaceControls` instance. There is no way to point a `FloatCurve` at a `Beam` |
| **`KeyframeMarker`** | A name plus a string, delivered by `GetMarkerReachedSignal` during playback | It is a *notification*, not a value track. It can say "now," it cannot say "0.4." It is nonetheless the correct seam between the two systems — Part 10.2 |

The facial case is worth knowing for one reason only: it proves the container
can hold non-joint numbers. The restriction is entirely in the player.

### 2.4 — What replication does, and why it confuses everybody once

**This caused an entire conversation and is written out so it does not
recur.** Both of the following are true at the same time, which is why they
seem contradictory:

**A rig animation started on the server renders on every client.** Confirmed
from Roblox's `Animator` class reference: *"Animator is the main class
responsible for the playback and replication of Animations. All replication of
playing AnimationTracks is handled through the Animator instance,"* and for
non-player rigs, *"its animations must be loaded and started on the server to
replicate."*

**It is not magic, and the mechanism is the whole point.** The keyframe data was
never on the server. It is on Roblox's CDN. The server holds an id. When the
server plays it, Roblox broadcasts *"track 123 started at time T"* and each
client's own `Animator` fetches track 123 itself. **The instruction travels; the
data does not.**

**A timeline run on the server would also be visible — and that is the trap.**
Property changes in `Workspace` replicate continuously, so a server-side
timeline works. But Roblox has no playback state for a beam, so the only thing
that *can* cross the wire is each individual value as it changes:

| | Rig animation on the server | Timeline on the server |
|---|---|---|
| What crosses | `"play track 123 at T"` | `Width0 = 0.4`, `Width0 = 0.8`, `Width0 = 1.2`, … |
| Message count | one | one per property, per change, per client |
| A 0.5s effect, 4 tracks, 60fps | one | ~120 replications × every player |

**So we copy Roblox's own trick by hand.** The choreography lives where every
client already has it — `ReplicatedStorage`, via `src/shared/` — and the server
sends a name and a timestamp, exactly like an animation id.

| | Rig animation | Our timeline |
|---|---|---|
| Where the data lives | Roblox's CDN, fetched per peer | `ReplicatedStorage`, delivered at join |
| What the server sends | `"track 123 at T"` | `"CLAW_ATTACK at T"` |
| Who runs the frames | every peer, locally | every client, locally |

**Nothing ever sends animation or timeline data over `EventTape`.** Only names
and timestamps.

**One trap that falls out of the same documentation:** the `Animator` must be
created on the server — baked into the `.rbxm`, not added by a LocalScript.
*"If an Animator is created locally, then AnimationTracks loaded with that
Animator will not replicate."* Create it client-side and five of six players
see a statue.

### 2.5 — A one-off server property change is fine

The rule is **not** "the server may not touch cosmetic properties." A boss that
glows permanently on entering phase two is one property set, one message, and
every client sees it. That is the simplest correct thing to do.

The rule is: **the server should not be the thing interpolating them.**

---

## Part 3 — What A Timeline Actually Is — Three Facts And A Loop

**Status:** SETTLED as the model. UNBUILT.

The whole system, stated completely:

**Fact 1 — the data is a list of "at this time, this value."**

```lua
{
    target = "Claws.Claw1.Emitter",   -- a PATH, not a reference. Part 7.4
    property = "Rate",
    keys = {
        { t = 0.00, value = 0,   ease = "LINEAR" },
        { t = 0.30, value = 250, ease = "CUBIC_OUT" },
        { t = 0.55, value = 0,   ease = "LINEAR" },
    },
}
```

**Fact 2 — values between keys are filled in by lerp.** Given two keys and how
far you are between them:

```
progress = (now - keyA.t) / (keyB.t - keyA.t)     -- 0 → 1
value    = keyA.value + (keyB.value - keyA.value) * progress
```

That is the entire interpolation idea. Part 4 lists the four places it needs
care; none of them change the shape.

**Fact 3 — the loop is a lookup.** Each frame: work out elapsed time, find which
pair of keys you are between, compute the value, assign it. Advance.

### Worked example, traced all the way through

A beam that grows to width 4 over 0.3s, holds, then collapses by 0.55s. Frame
rate is irrelevant; only elapsed time is read.

| Elapsed | Between | progress | Eased | Assigned `Width0` |
|---|---|---|---|---|
| 0.00 | key 1 → key 2 | 0.00 | 0.00 | 0.0 |
| 0.15 | key 1 → key 2 | 0.50 | 0.875 (cubic out) | 3.5 |
| 0.30 | key 2 exactly | — | — | 4.0 |
| 0.45 | key 2 → key 3 | 0.60 | 0.60 (linear) | 1.6 |
| 0.55 | key 3, end | — | — | 0.0 |

**Nothing in that table is a hard problem.** It is stated here in full because
the instinct that it *must* be harder than it looks is what sent an entire
conversation looking for a plugin.

### 3.1 — How much of this you do not need

**Most VFX work has no time dimension at all**, and forgetting this is how the
system gets over-built.

A `ParticleEmitter` is already an animation engine. It animates its own
particles over their lifetime through `Size`, `Color` and `Transparency`
curves, edited live in the Properties panel with the graph widget Roblox
provides. Beams and Trails do the same. Set once, live, watching it run.

`TweenService` covers the next tier for free: *move this property from A to B
over N seconds with an easing curve*, one line, no module of ours involved. Its
supported types, from Roblox's own reference: number, boolean, `CFrame`,
`Rect`, `Color3`, `UDim`, `UDim2`, `Vector2`, `Vector2int16`, `Vector3`,
`EnumItem`. **`NumberSequence` and `ColorSequence` are absent** — which is
exactly the corner Part 5.4 records the reference implementation punting on.

| What you want | Needs a timeline? |
|---|---|
| Tune how particles look and behave | **No.** Properties panel, live. The emitter animates itself |
| Burst particles at the impact frame | **No.** One moment — an animation marker (Part 10.2) |
| Emitter on at 0.2, off at 0.5 | **No.** Two moments |
| One property, A → B, with a curve | **No.** `TweenService`, one line |
| Beam grows → holds → collapses across a swing | **Yes** |
| Glow ramping in lockstep with a wind-up | **Yes** |

**`Timeline.luau` earns its keep only for several properties, several
keyframes, in sync.** Everything above that line is already solved and free.

---

## Part 4 — The Four Things That Are Actually Hard

**Status:** SETTLED as the list. Every one of these is tedium rather than
difficulty, and each is written down because each is a specific, findable bug
rather than a vague worry.

### 4.1 — Not every value interpolates the same way

| Value kind | How it interpolates | The trap |
|---|---|---|
| Number | `a + (b - a) * t` | none |
| `Vector3`, `Color3`, `UDim2`, `Vector2` | Roblox provides `:Lerp` on each; use it | writing a component-wise version by hand and getting a subtle case wrong for free |
| Rotation and position together | **Store a `CFrame` and use `CFrame:Lerp`** | **This is the real trap.** Store rotation as three separate angle numbers and 350° → 10° interpolates *backwards through 340°* instead of forwards through 20°. `CFrame:Lerp` takes the short way around; three loose numbers cannot |
| `NumberSequence`, `ColorSequence` | **Snap at the key, no interpolation** (decided — Part 14) | pretending they lerp |
| Booleans, enums, `Material`, asset ids | **Cannot interpolate. Snap at the key** | silently lerping them produces garbage or an error, depending on the type |

**The rule that falls out: store the richest type the engine gives you and lerp
that, rather than decomposing into numbers and lerping the pieces.**
Decomposition is where the rotation bug lives.

### 4.2 — Straight-line motion looks robotic

Linear interpolation from A to B moves at a constant speed, which reads as
mechanical. Real motion accelerates, decelerates, overshoots, or settles.

The fix is one line: **bend `progress` through a curve before using it.**

```
eased = curve(progress)                          -- both still 0 → 1
value = a + (b - a) * eased
```

One curve is a couple of lines of arithmetic. There are roughly thirteen
standard families — Back, Bounce, Circ, Cubic, Elastic, Expo, Linear, Quad,
Quart, Quint, Sextic, Sine, Constant — each with In / Out / InOut / OutIn
variants, some carrying extra parameters (overshoot, amplitude, period).
Writing all of them is pure grunt work and it is the single largest chunk of
code in the system. Part 5.2 has the measured size.

**Do not write all thirteen up front.** Roblox already exposes
`Enum.EasingStyle` through `TweenService`; the first version needs Linear and
Cubic and grows on demand. Writing the full set before any content needs it is
the same mistake as building an engine for three cases.

**A full graph editor — dragging bezier handles on the curve between two keys —
is explicitly out of scope.** Named easing styles cover essentially all combat
VFX, and the graph editor is where a homemade tool turns into a project.

### 4.3 — Some entries are triggers, not values

"Emit 30 particles," "play a sound," "start a screen shake" are not values that
slide. They are one-shot events at a moment.

They need a separate path in the engine, and the specific bug they cause is
worth stating outright: **a trigger must fire exactly once.** A naive "is now
past this key?" test fires it again on every frame that follows. The engine
tracks the last processed time and fires only triggers falling inside
`(lastTime, nowTime]`.

### 4.4 — Track time, never frames

Frame rate wobbles, and it differs between machines. Counting frames makes an
effect run at different speeds on different hardware.

**The engine holds an elapsed-time accumulator and derives position from it.**
Frame indices, if they appear at all, are a display convenience in authored data
and are converted to seconds at load.

This also sets up the one thing this system must inherit from
`Client-Architecture.md` Part 9.1: anything two players must see identically
starts from a server-clock anchor via `Playback.scheduleAt(anchor, fn)`, never
from local receipt time. A timeline is exactly such a thing.

---

## Part 5 — Evidence From A Working Implementation

**Status:** SETTLED as evidence. Read directly from source on 2026-08-18, not
inferred from documentation or forum claims.

The paid plugin's runtime half has an open-source equivalent — **Moonlite**, by
MaximumADHD, which plays back saves produced by Moon Animator. It is the only
public, complete, working implementation of precisely the engine this document
describes, which makes it the best available estimate of the real cost. It was
read rather than trusted.

### 5.1 — What the save format actually is

The claim that a save is an opaque compressed blob is **false**. Moonlite's
loader calls `HttpService:JSONDecode(save.Value)`. Plain, uncompressed JSON, and
it holds only the index:

```
Items:       [ { Path = { ItemType, InstanceTypes, InstanceNames } } ]
Information: { FPS, Length, Looped, Created, Modified, ExportedPriority }
```

The keyframes themselves are **child Instances** of that `StringValue`, named
`"1"`, `"2"`, `"3"` matching item index — each containing a `Rig` folder of
`_joint` entries (a dotted joint path, a base CFrame, a keyframe container) and
a `MarkerTrack`.

So: a JSON header plus a tree of value objects. Nothing clever, nothing hidden.
**Note what `Path` is** — names, not references. Part 7.4 adopts the same
approach for the same reason.

### 5.2 — Measured size

| File | Size | What is in it |
|---|---|---|
| `init.lua` | 945 lines | parsing, compiling, and the playback loop |
| `EaseFuncs.lua` | 13.5 KB | thirteen curve families × four directions |
| `Specials.lua` | 611 lines | properties that are not plain assignment |
| `Types.lua` | 2.3 KB | the schema |

Roughly 50 KB total, by one developer, still labelled work-in-progress at
version 0.9.0 three years after first release.

### 5.3 — The architectural finding worth stealing

**Moonlite precomputes.** At load it walks the whole timeline and bakes a
buffer:

```
buffer[instance][frameIndex] = { propertyName = value }
```

Playback then does no interpolation at all. Its step function — about fifty
lines — computes the current frame index, looks up that table, assigns the
properties, fires any markers, advances time.

**All the interpolation happens once, at load.** That is a good trade for short
cosmetic effects and it is the shape to copy: the per-frame path becomes a
dictionary lookup and cannot be a performance problem.

**The cost of that trade, stated so it is not discovered later:** a precomputed
buffer cannot be retimed or speed-adjusted at runtime without recompiling, and
its memory grows with `duration × frameRate × trackCount`. For half-second
combat effects this is nothing. For a thirty-second cutscene across twenty
objects it is worth measuring before assuming.

**It also constrains the editor.** A precomputed buffer must be rebuilt on every
edit, so the editor cannot use the baked path for live scrubbing — see Part 7.5.

### 5.4 — The two corners it did not solve

Recorded because we will meet both.

- **`Specials.lua` exists at all.** Camera, Humanoid, ParticleEmitter and Sound
  carry entries that are actions rather than values — `Emit`, `Play`,
  `ChangeState`, `AttachToPart`. It even stores state in attributes
  (`__moonlite_*`) because some of these have no property to read back. This is
  Part 4.3 in the wild, and it is 611 lines **for four classes**, which is the
  measure of how mechanical the work is.
- **Sequence interpolation is a stub.** Its `NumberSequence` and `ColorSequence`
  interpolators read only the **first keypoint** and return a single-keypoint
  sequence, discarding the rest. Part 4.1 sidesteps this by deciding sequences
  snap rather than interpolate.

### 5.5 — What this evidence establishes

**The player is small. The editor is the expensive half.** The paid plugin ships
140 scripts; the runtime equivalent is 50 KB. The difference is the authoring
application. That difference is real, and Part 6.2 is the decision about what to
do with it.

**There is no secret knowledge in any of it.** The engine is generic — it stores
`{ instance, propertyName, value }` and performs `instance[propertyName] =
value`. It has no idea what a `ParticleEmitter` is. The only exceptions are the
four classes above, where the thing wanted is an action rather than a value.

---

## Part 6 — Authoring — Lua Tables, And The Editor Decision

**Status:** SETTLED. 6.2 was reversed on 2026-08-19; both positions are kept.

**Timelines are authored as declarative Lua tables in
`src/shared/definitions/Timelines/`, committed to git as text.** No binary
save, no third-party runtime.

This is `Architecture-Reference.md` Part 2 applied without modification: the
engine is generic and stable, the timelines are configuration that grows with
the content. It is the same division `Animation.md` Part 5 uses for its
manifest and `HitDetection.md` uses for `HitVolume` — a new effect is data, and
only a new *kind* of behaviour is code.

### 6.1 — Why not adopt the plugin's save format

Not on principle, and not on price. On three specific costs:

| Cost | Detail |
|---|---|
| **It ships in the DataModel** | A save is a `StringValue` with a subtree of value objects. `Animation.md` Part 1 establishes that a rig animation ships *nothing* — the game holds a number and the peer fetches the data. A timeline save is the opposite: real content living in the tree, needing its own row in `AssetPipeline.md`'s replication table |
| **It does not diff** | `AssetPipeline.md` Part 6 exists specifically to get authored content into git as reviewable files. A nested tree of value objects wrapped around a JSON string is technically in git and practically unreadable in a diff. A Lua table diffs one line per changed key |
| **It needs a third-party runtime** | Playing those saves means depending on a work-in-progress module for a cosmetic system. The dependency is not large, but it is permanent, and it buys a format we did not choose |

**The test that catches this:** if a change to one keyframe cannot be read as a
one-line diff, the format is wrong for this repository.

### 6.2 — The editor: rejected 2026-08-18, and why that was wrong

**The original rejection, kept verbatim in substance:** building a visual
editor is the expensive half of the problem, it is a discipline unrelated to
every other system here, and — decisively — it would be an authoring tool built
before the content it authors, which is `Architecture-Reference.md` Part 2's
Test 3 failing in the most direct way available. Count the cases; today it is
zero.

**Why that was wrong.** Test 3 governs whether a **generic engine that ships**
is worth building instead of writing N cases explicitly. It is a runtime-cost
and complexity-of-shipped-code argument. **The editor does not ship.** It has:

- no runtime cost, because it never runs in a live game
- no security surface, because no player ever touches it
- no correctness requirement in the sense the rest of the repository means —
  if it is wrong, you see it on screen immediately and fix it

Applying a shipped-engine test to a development tool was a category error. The
case-counting argument still correctly governs `Timeline.luau` itself.

**The decision, 2026-08-19: the editor gets built, as a prototype first.**
Part 7 designs it. The reasons are recorded because "I want to" is a legitimate
input that gets forgotten:

- Full control of the format, which the rest of this document depends on
- Nothing to teach a future collaborator that is not already in this repo
- It is genuinely smaller than the systems already built here — a timeline
  editor is data entry with a time axis, against an HFSM that carries real
  transition and re-entrancy semantics

**What stays true from the rejection, and is the actual risk:** timeline editors
are long-tailed. A playhead and some rows is a weekend. Then snapping, then
multi-select, then copy-paste, then undo touching everything already written.
None of it hard, all of it *more*. **The mitigation is Part 7's scope: no undo,
no graph editor, no auto-key.** Every one of those is cut on purpose, and each
cut is a decision recorded here rather than an omission.

### 6.3 — What authoring looks like before the editor exists

Numbers get tuned by editing the table and re-running. That has one property a
scrubber does not: the tuned result is already in its final, committed,
reviewable form, with no export step to forget.

This remains the fallback if the editor prototype is abandoned, and it is why
the format is designed to be hand-writable in the first place.

---

## Part 7 — The Editor — Document, Preview, Export

**Status:** SETTLED as the design. UNBUILT — prototype planned, Part 13.

Three things sit on top of each other and get conflated. Separating them is the
entire design.

```
THE DOCUMENT     one table, in memory. The thing being edited.
                 Identical in shape to what ships.

THE PREVIEW      a pure read. (document, time) → write values to live objects.
                 Produces no data. Ever.

THE EXPORT       serialize the document to a .luau file on disk.
                 On a button press, never automatically.
```

### 7.1 — What happens per interaction

**Scrubbing does not create data.** This is the point people get wrong, and it
is where the perceived complexity comes from.

| Action | Document changes? | What happens |
|---|---|---|
| Drag the playhead to 0.4 | **No** | Read the document, compute values at 0.4, assign to live objects |
| Move a claw while at 0.4 | **Yes — one key** | Read the claw's current `CFrame`, write `{ t = 0.4, value = … }` into that track |
| Drag a key from 0.4 to 0.5 | **Yes — one field** | `key.t = 0.5` |
| Delete a key | **Yes — one removal** | |
| Press Export | No | Serialize to `src/shared/definitions/Timelines/ClawAttack.luau` |

**One document, mutated in place, with small local edits.** Not new tables per
attempt, not a rewrite on every frame. The only thing happening continuously is
*reading*.

### 7.2 — No undo, on purpose

**Decided: the editor has no undo stack.**

Undo exists in commercial editors because the document lives in a proprietary
binary and the user has no other recovery path. That does not apply here:

- the document is a Lua table that can also be opened and hand-edited
- it exports to a text file under `src/shared/`
- **git is the undo**, at exactly the granularity that matters — per save, with
  a readable diff

This removes the single largest subsystem of a typical editor, and the one that
touches every other feature. If it is ever wanted, the cheap version is
snapshot-the-whole-document-per-edit, because these documents are small.

### 7.3 — No auto-key

**Decided: a keyframe is only ever created by an explicit gesture, at the
playhead time.**

The tempting alternative — watch for property changes and record them
automatically — litters keys every time the camera moves or something is
nudged, and it makes it impossible to tell an intentional edit from an
incidental one.

**This also resolves the scrub-versus-edit conflict**, which is otherwise a real
design problem. The rule is: **scrubbing always writes, editing always keys.**
Scrub to 0.4 and the tool writes the interpolated pose; drag the claw from there
and that is an edit at 0.4, creating or overwriting a key. You were adjusting
*from* the interpolated pose, which is what was wanted.

**Overwrite is silent**, keyed by time per track. A key at a time that already
has one replaces it. This is what every animation tool does and any other choice
surprises the user.

### 7.4 — Targets are paths, never references

**A track cannot store an `Instance` reference.** The document is text in git,
and it will be played on a boss that does not exist yet, then on the next one,
and the next.

```lua
{ target = "Claws.Claw1.Emitter", property = "Rate", keys = { … } }
```

`Timeline.play(def, rootInstance)` resolves those paths against the root it is
handed. Same document, every spawned instance. This is why Moonlite's format
stores `InstanceNames` rather than references (Part 5.1) — same constraint, same
answer.

**The cost, stated so it is not a surprise: the timeline is coupled to a
hierarchy shape.** Rename a part inside the prefab and the effect breaks
**silently** — the path resolves to nothing, the track animates nothing, and no
error is raised. Part 8.2 is the mitigation.

### 7.5 — The editor uses the shipping engine, and this is not negotiable

**The preview must call `Timeline.luau`, not a second implementation.** The
editor asks for "evaluate at exactly T and apply" where the game asks for "run
from 0."

Write a separate preview path and what you see while tuning is not what plays.
You will tune against the wrong thing and never be able to trust the tool again.
**This is the mistake that kills homemade editors — not difficulty, divergence.**

Note the interaction with Part 5.3: the baked-buffer strategy is a load-time
optimisation for playback. The editor needs an evaluate-at-arbitrary-T path that
does not require a rebuild per scrub. **The engine therefore exposes both** — a
direct evaluator, and a bake step that uses it. The evaluator is the shared
truth; the bake is an optimisation over it.

### 7.6 — The trap that costs a place file

**Preview writes to real objects in the real place.** Scrub to 0.4 and that claw
genuinely is at 0.4 in the workspace.

Close the editor mid-scrub and those objects stay frozen mid-animation — and in
a plugin context, **that state is saved into the place file.** You return the
next day to a boss with a claw at a strange angle and no record of why.

**The editor captures every touched property's baseline before its first preview
write, and restores unconditionally on exit.** Same rule as the runtime engine
(Part 9.3), but it bites harder here because the mistake persists into a saved
file rather than vanishing on respawn.

### 7.7 — What ships and what does not

| Piece | Ships | Role |
|---|---|---|
| `Timeline.luau` | **Yes** | Generic engine. Takes a document and a root, plays it. Knows nothing about claws |
| `Timelines/*.luau` | **Yes** | Declarative config. One file per effect |
| The editor | **No — development only** | Mutates a document, calls the engine to preview, writes the config file |

The editor is the only piece with no runtime presence, and the only piece whose
bugs are self-announcing.

---

## Part 8 — Where The Effect Objects Come From

**Status:** SETTLED. UNBUILT.

**A timeline animates objects. It does not create them.** A smite needs its beam
and emitter to exist before anything can drive their properties, and nothing in
Parts 3 through 7 produces them.

### 8.1 — The prefab, and why it is the existing pattern

**Effect objects are authored in Studio, committed as `.rbxm`, cloned at play
time, and destroyed when the timeline finishes.**

```
assets/models/effects/ClawAttack.rbxm     (git, synced by Rojo)
  → ReplicatedStorage.Effects.ClawAttack  (replicated at join, never touched)
  → local fx = template:Clone()           (client, at play time)
  → fx.Parent = workspace
  → Timeline.play(ClawAttackTimeline, fx)
  → fx:Destroy()
```

This is `AssetPipeline.md`'s enemy-model lifecycle with the peers swapped —
structure in git, cloned at runtime — and it is deliberately the same shape so
there is one pattern to remember rather than two. The difference is that effect
prefabs live in `ReplicatedStorage` rather than `ServerStorage`, because the
client is the peer that clones them.

**The editor never generates the prefab.** It outputs timelines only. A spawn
recipe reverse-engineered from whatever happened to be in the workspace at
export time would be exactly the "generated code nobody can review" problem that
Part 6.1 rejects the plugin save format over.

### 8.2 — Boot validation, because path breakage is silent

`Animation.md` Part 10 validates animation ids at boot for precisely this class
of failure. Timelines get the same treatment:

**At boot, walk every timeline's target paths against its declared prefab and
fail loudly if one does not resolve.**

Without it, renaming a part inside a prefab breaks the effect with no error, no
warning, and no visible cause — the same silent-mismatch family as the
hand-authored timing mismatch `Animation.md` Part 11 warns about. The check is
cheap, runs once, and is the only defence Part 7.4's path-based targeting has.

---

## Part 9 — Where It Lives, And What It Is Forbidden To Do

**Status:** SETTLED by inheritance. Every rule below is an existing rule from
another document applied to this system; none of it is new policy.

### 9.1 — Placement

```
src/client/playback/Timeline.luau           the engine
src/shared/definitions/Timelines/           the authored documents
assets/models/effects/*.rbxm                the prefabs
(dev only, outside the game tree)           the editor
```

`Client-Architecture.md` Part 10.1 already names `src/client/playback/` as the
home for Animation, VFX, Sound and Camera. A timeline is the mechanism those
modules use to change values over time; it is a peer of them, not a layer above
them.

Presenters call it. It subscribes to nothing and decides nothing.

### 9.2 — The prohibitions

| Forbidden | Why | Where the rule comes from |
|---|---|---|
| Driving damage, hit windows, or any gameplay outcome from a timeline trigger | Client-authoritative timing on a server-authoritative system, on the wrong clock | `Animation.md` Part 11, unchanged |
| Running the engine on the server for authority | A timeline holds cosmetic values and no gameplay data. There is nothing in it to be authoritative about | `Animation.md` Part 2 and Part 12 |
| A `TimelineService` in the server registry | Playback is a client rendering concern. `ANIMATION` is deliberately absent from `EventRoutingRegistry` and this is the same category | `Animation.md` Part 15 |
| Server events shaped as "play timeline X for Y seconds" | The command shape. Facts, not commands | `Client-Architecture.md` PLAYBACK |
| Anchoring a hurtbox to a part a timeline moves | The one carve-out is for parts the **server** controls. A client-driven timeline moving a part would let a client reshape its own hittable volume | `Animation.md` Part 13 |
| The editor existing in a shipped place | It is a development tool with write access to everything | Part 7.7 |

**The consequence stated loudly:** a timeline that stalls, errors, or is never
played must not change a single gameplay outcome. If deleting the entire
`Timeline.luau` module would alter who takes damage, the design is wrong and
this Part is the thing it violated.

### 9.3 — Restore is mandatory and unconditional

A timeline writes to live objects. If it stops early — cancelled, errored,
entity destroyed mid-play — the properties it touched are left mid-flight: a
beam frozen at width 3, a light stuck dim.

**Every timeline records the value of each property before it first writes to
it, and restores those values when it stops, by any means.** This mirrors
`Client-Architecture.md` Part 9.2's rule that camera restore must be
unconditional and bounded, and it exists for the same reason: a cosmetic system
that fails must fail invisibly, not leave debris.

For prefab-cloned effects the restore is usually moot — the clone is destroyed —
but it is not optional, because timelines are also played on objects that
outlive them, such as a boss's own body.

---

## Part 10 — Rig Animation And Timelines — Two Layers, And The Seam Between Them

**Status:** SETTLED.

### 10.1 — They are separate, and neither reads the other

A single attack plays a rig animation (the claws sliding and swiping) and a
timeline (the fade, the glow, the particle burst) at once.

| Piece of a three-claw attack | System | Authored in | Played by |
|---|---|---|---|
| Claws sliding in, swiping | **Rig animation** | Studio's free Animation Editor | **Server.** Replicates to everyone (Part 2.4) |
| Claws fading in and out | Timeline | Lua document | Each client, locally |
| Glow pulse, colour shift | Timeline | Lua document | Each client |
| Particle burst on impact | Timeline trigger | Lua document | Each client |

```
Skill activates
   ├── Animation.play("BOSS_CLAW_ATTACK")     rig animation, joints
   ├── Timeline.play("BOSS_CLAW_ATTACK_VFX")  properties
   └── (server, independently)  activeWindow from the skill definition
```

The third line is the one that matters. `Animation.md` Part 8 establishes that
what plays and what is calculated are two timelines that never meet — hit timing
comes from hand-authored numbers on the skill definition, not from either
cosmetic layer. **A timeline is a third thing on the cosmetic side of that line,
and adding it does not move the line.**

**Why they are not merged**, since the question is obvious: rig animation has an
engine, a cloud asset, an upload step and an ownership constraint
(`Animation.md` Part 4); a timeline has none of those and is a local Lua
document. They share the word "animation" and no mechanism. Merging them means
the merged thing carries an upload pipeline for effects that never upload.

### 10.2 — Markers are the seam, and they are free

The two layers must line up: the burst fires when the claw actually lands. The
naive approach is to read the impact frame off the Animation Editor and type
`0.467` into the timeline — **a number maintained in two places, where retiming
the swipe silently desynchronises the effect and nothing errors.**

**The mechanism instead:** place an animation event marker named `impact` on the
impact frame in the free Animation Editor, and have the client start the
timeline from it.

```lua
track:GetMarkerReachedSignal("impact"):Connect(function()
    Timeline.play(ClawImpact, fx)
end)
```

Retime the swipe and the marker moves with it. **There is no number to keep in
sync.**

`Animation.md` Part 11 permits exactly this in the same breath as forbidding the
dangerous version: *"Markers are worth using for cosmetics only. Footstep
sounds, weapon trails, screen shake, dust."* Damage never touches markers;
cosmetics are what they are for.

**What markers do not cover:** continuous effects that ramp *against* the motion
— a glow rising in lockstep with a whole wind-up. Those need a timeline running
alongside the animation, anchored at its start. Markers handle moments; the
timeline handles spans.

---

## Part 11 — Scaling — What The Twentieth Effect Costs

**Status:** SETTLED as the design target, in the same shape as `Animation.md`
Part 14.

| Piece | Cost of one more effect |
|---|---|
| Timeline document | 1 file |
| Prefab | 1 `.rbxm` |
| `Timeline.luau` | **0 lines** |
| The editor | **0 lines** |
| Presenter | **0 lines** |
| Networking | **0 lines** |
| Server | **0 lines** |

**Two authored artefacts, no code.** The engine changes only when a new *kind*
of thing appears — a value type nobody has interpolated before, or a trigger the
engine does not know how to fire. Those are the two categories, and they are the
only two.

---

## Part 12 — Rejected Designs

**Status:** SETTLED. Each kept with the test that catches it, not the story of
who said what.

> **Two entries below are REVERSALS of things this document previously
> asserted**, marked inline. Both were built before being caught.

**~~The Conductor plays property tracks; rig animation is a separate system
neither reads.~~ OVERRULED 2026-08-23.** Part 10.1 argued they share the word
"animation" and no mechanism. True of the *assets* — a clip has an upload step,
a cloud id and an ownership constraint; a Score has none of those. **False of
the transport**, which is the thing that actually matters.

**The Conductor is now the single door for all client-side animation.** It does
not reimplement the `Animator` — it *drives* it. A clip track says "start this
clip at t=0.2" and the Animator still does the joint work. What that buys:
**the clip's clock and the property tracks' clock are the same clock by
construction**, rather than by two systems agreeing to stay in step.

A bare clip becomes the degenerate case — a Score with one clip track and no
property tracks — the same trick as a sphere being a zero-length capsule.
Nothing downstream learns the simple case exists.

*The test that catches the old position: two systems that must agree about time
are two clocks. How do you prove they have not drifted?*

---

**~~The Score follows a clip's clock, reading `AnimationTrack.TimePosition`.~~
REVERSED 2026-08-23, on the day it was built.**

It was justified as making drift impossible: with only one clock there is
nothing to diverge. That is true and it broke three things:

| Broken | How |
|---|---|
| **The delayed slash** | 0.4s clip, 800ms silence, burst at 1.2s — **this document's own headline example.** If the clip is the clock, the clock ends at 0.4s and the burst never fires |
| **Two clips** | no answer for which one to read the clock from |
| **Anything before the clip** | a wind-up at t=0.1 has no moment to exist at |

**And the drift argument dissolved once the Conductor started the clip itself.**
It sets the rate and knows the start moment, so there is nothing to diverge
*from*. Drift only existed *because* something else owned the clock — the
justification was an artifact of the design it was justifying.

*The test: can the Score outlive its clip? If not, the clip is the clock and
silence after it is unexpressible.*

---

**~~Each Playback captures and restores its own baseline.~~ REPLACED
2026-08-23 with refcounted ownership.**

Correct for one Score at a time and quietly destructive the moment two overlap,
because `captureBaseline` reads the CURRENT value — which is the other Score's
in-flight one:

```
A starts    baseline = red       correct, nothing has written
A runs      value is now ORANGE  mid-fade
B starts    baseline = ORANGE    <- reads A's in-flight value
B finishes  restores ORANGE      <- stuck at a mid-animation value, forever
```

So the mechanism that exists to prevent permanent debris **created** permanent
debris — and the trigger is spam-clicking one attack, not some exotic overlap.

**The rule now: the first Score to touch a property captures the original; the
last one to let go puts it back.** Refcounted in `conductor/Baseline.luau`.

A simpler "one owner per property, starting a second stops the first" was
considered and rejected as too coarse: a hit-flash and a swing on the same blade
touch *different* properties and are legitimately concurrent.

*The test: start the same Score twice, overlapping. Does the property end up
where it started?*

**Buy the plugin because the free editor lacks IK.** False premise. Studio's
Animation Editor has a **Manage IK** window, documented in Roblox's current
Animation Editor reference. The claim traces to SEO content farms, and it
survived two rounds of a conversation before being checked. *The test: a claim
about engine capability is not settled until it is found in Roblox's own
documentation or in source.*

**Extend the animation format to carry property tracks.** There is no way to
address a non-joint from a `Pose`, and the `Animator` writes only
`Motor6D.Transform` regardless (Part 2.2). *The test: ask what code would read
the new field. If the answer is "nothing," it is not a format problem.*

**Smuggle property values through `KeyframeMarker` strings.** Markers are
notifications, not tracks — they say "now," not "0.4." *The test: a marker fires
at a moment; a track holds a value between moments.* Markers still have a
correct job, which is Part 10.2.

**Read authored values back with `GetAnimationClipAsync` at runtime.** A
yielding webcall that can fail, for cosmetic data that could simply be a local
table. `Animation.md` Part 10 rejected the same call for timing. *The test: it is
a webcall for data we authored ourselves.*

**Run the timeline on the server so every client sees it.** It would work, and
that is the trap. Roblox replicates one instruction for a rig animation and one
message per property change for a timeline (Part 2.4). *The test: count the
messages a half-second effect sends to every player.*

**Adopt Moon Animator saves plus a third-party runtime.** Ships content in the
DataModel, produces diffs nobody can review, and takes a permanent dependency
for a cosmetic system (Part 6.1). *The test: a one-keyframe change must be a
one-line diff.*

**~~Build a Studio plugin timeline editor.~~ OVERTURNED 2026-08-19.** The
original argument applied a shipped-engine test to a tool that does not ship.
Part 6.2 carries both positions and the reasoning; Part 7 is the design. *The
test that replaced it: does the thing being case-counted run in a live game?*

**Build the engine now, before any content needs it.** Still stands for the
engine itself, and is why Part 13 describes a prototype against one real effect
rather than a build. `Architecture-Reference.md` Part 2, Test 3. *The test: name
the effect it would play.*

**Store rotation as three angle numbers and lerp each.** Interpolates the long
way around at the 0°/360° boundary. *The test: animate a rotation from 350° to
10° and watch it travel 340° backwards.* Store a `CFrame`, use `CFrame:Lerp`.

**Drive the loop by counting frames.** Runs at different speeds on different
hardware and desynchronises between clients. *The test: cap the frame rate and
see whether the effect takes longer.* Accumulate time (Part 4.4).

**A `TimelineService` on the server.** Playback is a client rendering concern,
and this is the same proposal `Animation.md` Part 15 rejected for animation,
wearing a different noun. *The test: name the gameplay decision it would make.
There isn't one.*

**Auto-keying in the editor.** Records keys from incidental movement and makes
intentional edits indistinguishable from accidents. *The test: nudge the camera
and count the keys created.* Part 7.3.

**A graph editor for per-keyframe curves.** The feature that turns a weekend
tool into a project, for a fidelity named easing styles already provide.
*The test: name the effect that a bezier handle achieves and `CUBIC_OUT` does
not.* Part 4.2.

**Reverse-engineering a spawn recipe at export time.** Would emit generated
setup code nobody reviews, which is the objection to the plugin save format
wearing our own logo. *The test: could a reviewer read the diff and know what
will exist at runtime?* Part 8.1.

---

## Part 13 — Current State And The Prototype Plan

**Status:** as of **2026-08-23**. Steps 1 and 2 of the plan below are BUILT.

| Piece | Status | Note |
|---|---|---|
| `client/playback/conductor/` | **BUILT 2026-08-23** | Four files: `init` (the door), `Evaluate` (stateless), `Baseline` (ownership), `Playback` (one running Score) |
| `shared/types/Score.luau` | **BUILT** | The shape. Outside `definitions/scores/` so a loader walking that folder cannot mistake a type module for content |
| Property tracks, both clocks, restore | **BUILT** | Numbers, booleans, Color3, Vector2/3, UDim, UDim2, CFrame. Linear + Cubic only |
| Clip tracks | **BUILT** | A `ClipPlayer` is injected, so the engine still knows nothing about Animators or manifests |
| The editor | **BUILT 2026-08-23** | `client/diagnostics/conductorTool/`. Sliders, key, scrub, play, export-to-console. Gated on `DebugConductorTool` |
| `shared/definitions/scores/` | **EMPTY** | Deliberately. A Score is authored by looking, and there is nothing to look at yet |
| Triggers | **BUILT 2026-08-23** | `conductor/Actions.luau`. Two actions — `EMIT`, `SOUND` — dispatched by label. **Deferred at first and that was wrong**: a particle burst is `Emit(n)`, a *method*, and no property track expresses it at any key density |
| Server-anchored clock | ABSENT | `elapsed = GetServerTimeNow() - anchor`. One line, and nothing needs it until a combo or cutscene exists |
| Boot path validation | ABSENT | The only defence against a renamed part silently animating nothing |
| **A timeline VIEW in the editor** | **BUILT 2026-08-23** | Every clip, track and trigger as a bar on one shared axis, with a playhead. Click a lane to select it, click the ruler to scrub. The panel drags by its header and resizes from a corner grip |
| Select-to-edit inspector | **BUILT 2026-08-23** | One thing at a time. The flat version put every track's controls inline, which is fine for two tracks and pushes the timeline off the bottom of the panel at ten |
| Baking / precompute | ABSENT | Part 5.3's trade. Real for a long Score, overhead for a half-second one |
| `assets/models/effects/` | ABSENT | `assets/effects/` is mapped and empty |
| Ease library | **BUILT, four entries** | Linear, Cubic In/Out/InOut, hand-written rather than via `Enum.EasingStyle` |

> **NOTHING HERE HAS EVER RUN.** Every line was written and unvalidated as of
> 2026-08-23. Treat the first live session as the prototype this Part describes,
> not as a regression hunt.

### The plan, in order

**This is a prototype, not a build.** The distinction is
`Architecture-Reference.md`'s: *a design argued three times and built zero times
is not settled, it is unvalidated.* Everything in Parts 3 through 8 has been
argued and never run.

1. **The engine, minimum viable.** Evaluate-at-T over a hand-written document.
   Numbers and `CFrame` only, Linear and Cubic only, no triggers.
2. **The editor, minimum viable.** Playhead, one track list, explicit key
   creation, export to file. No undo, no auto-key, no graph editor.
3. **One real effect, end to end** — a particle emitter, authored in the editor,
   exported, played from a skill. This is the validation step, and it is
   deliberately the smallest thing that exercises the whole path: prefab →
   clone → timeline → restore → destroy.

**Timing: when animation work starts.** It is the first thing in that block
rather than a detour from it, because the rig half and the effects half are
authored against each other (Part 10.2) and building the effects tooling
afterwards means retiming everything twice.

**The thing to watch for is scope, not difficulty.** Part 6.2 names the risk and
Part 7's four explicit cuts — no undo, no auto-key, no graph editor, no
generated prefabs — are the mitigation. Each is a decision, not an omission, and
re-adding one is a change to this document.

---

## Part 14 — Open Questions

Questions closed since the first revision are listed first, because the reason
they closed is the useful part.

### Closed

| Question | Answer | Why |
|---|---|---|
| How does a track reference its target across export and reuse? | **Paths, resolved against a root at play time** | An `Instance` reference cannot be serialised, and the same document plays on every spawned copy. Part 7.4 |
| Linear only, or easing per keyframe? | **Named easing styles from `Enum.EasingStyle`, Linear and Cubic first** | Covers essentially all combat VFX; a graph editor does not. Parts 4.2, 12 |
| Does scrubbing fight manual edits? | **No — scrubbing writes, editing keys, keys only on explicit gesture** | Part 7.3 |
| Duplicate keys at the same time on a track? | **Silent overwrite, keyed by time** | What every animation tool does; anything else surprises. Part 7.3 |
| Are `NumberSequence` / `ColorSequence` keyframeable? | **Yes, snapped whole at a key. No interpolation** | "Switch to this whole colour sequence at 0.3" is the actual use. Sidesteps the corner Moonlite punted on. Parts 4.1, 5.4 |
| Does the editor emit prefabs as well as timelines? | **No. Timelines only** | Generated setup code is the thing Part 6.1 rejects the plugin format over. Part 8.1 |
| Is an undo stack needed? | **No. Git is the undo** | The document is text in the repo. Part 7.2 |

### Still open

| Question | Why it matters | What answers it |
|---|---|---|
| Precomputed buffer, or evaluate live at playback? | Part 5.3 records the trade: lookup-cheap but memory-linear and not retimable. The editor needs a live evaluator regardless (Part 7.5), so the question is only whether playback also bakes | Measure at the first cutscene-length timeline. For sub-second combat effects, bake |
| Does the editor author against the prefab itself, or a clone of it? | Authoring against the prefab risks Part 7.6 persisting a broken template. Authoring against a clone means the export has to map paths back | The prototype. It will be obvious within an hour |
| One timeline per beat, or one long one, for cutscenes? | Decides whether the engine needs sequencing and chaining, or only parallel playback | The first cutscene prototype |
| Does a timeline ever need to blend out on interrupt rather than restore instantly? | Part 9.3 settles restore-on-stop. Blending out is a different, larger feature | A cancelled skill whose instant VFX snap-back looks wrong on screen |
| Does anything need to play a timeline on the server? | Part 9.2 forbids it for authority; Part 2.5 permits one-off property sets | A gameplay-relevant moving object appearing that is not a rig |

---

## Related Documents

| Document | What it covers that this one does not |
|---|---|
| `Animation.md` | Rig animation end to end — the manifest, upload, ownership, priority, markers, and why animation is not a security surface. Every prohibition in Part 9.2 originates there |
| `Client-Architecture.md` | The Playback layer, Presenters, and server-clock anchoring |
| `AssetPipeline.md` | Where content lives, what replicates, and the Rojo art path that Part 8.1 extends |
| `Architecture-Reference.md` | Part 2's generic-engine test, and the Test 3 category error corrected in Part 6.2 |
| `Gameplay-Design.md` | The interactive cutscene sequences that are this system's eventual heavy customer |
