# Animation Workflow

### How an attack gets made, in order, from nothing to content

> **Why this document exists.** The order was got wrong three times in one
> session, always the same way: proposing that the skill definition be written
> first and animated to afterwards.
>
> **It is the reverse.** A skill's numbers are the *output* of this workflow.
> You cannot write them first because nobody knows them until the thing has
> been watched running.
>
> `Animation.md` owns clips, upload and the manifest. `Timeline.md` owns the
> Conductor and the Score. `HitDetection.md` owns hit volumes. **This document
> owns the order they happen in**, and links rather than restating.
>
> **Status: PARTIAL.** Phases 1–3 are built and runnable. Phase 4 has two real
> gaps, named where they fall.

---

## The rule the whole document is an application of

> **You author by looking. Numbers come out at the end, not in at the start.**

Every step below is arranged so that the next thing you have to judge is
visible on screen when you judge it. `Brightness = 3.0` cannot be judged by
reading it. Neither can `sweep = 160`, or `activeWindow = 0.4`.

**The corollary, and the thing that keeps getting violated:** a definition file
is a *record of a decision already made by eye*. If you are typing a number
into one and you have not seen it yet, you are guessing at the output of a step
you have not run.

---

## Phase 0 — Already settled, do not re-decide

| | | |
|---|---|---|
| Asset owner | **the GROUP** | Done 2026-08-22. Every upload, meshes included. A personal asset does not transfer — it gets re-uploaded |
| Rig | **R15** | Already baked into `HurtboxDefinitions.PLAYER_R15`, which uses R15 part names |
| Who plays a player's clip | **the client** | Network ownership. Server-started would cost a round trip to do what this machine can do this frame |
| Who plays an NPC's clip | **the server** | Client-started never replicates — five of six players see a statue |

---

## Phase 1 — Build the thing you are going to animate

**Nothing before this step is possible.** A Score animates properties of
instances; if the instances do not exist there is nothing to author against.

### 1.1 — Build the weapon

Studio parts or a Blender mesh. Either is fine for a prototype.

### 1.1a — How a stacked effect is actually built

**Researched 2026-08-23, because the design depends on it.** Moon Animator is
[documented by its own users as poorly suited to gameplay effects](https://devforum.roblox.com/t/is-it-possible-to-script-animated-effectsmoon-animator-2/3223497)
— it is a cutscene tool. The accepted community workaround is *"a VFX Root, and
attachments placed in custom CFrames, emitted based on animation events."*

**That workaround is what the Conductor is.** So the shape is:

```
one Score
  ├── clip track      the rig swing
  ├── property tracks a beam widening, a trail fading, a light pulsing
  └── triggers        each emitter's burst, at its own moment
```

**Stacking is COUNT, not complexity.** A convincing slash is not one clever
emitter — it is four, each with its own trigger at its own moment. The same
principle as a curved horn being three capsules rather than one clever shape.

### The rule that keeps a Score small

> **The Conductor controls timing. The asset controls behaviour.**

**The test: does this describe how one particle behaves, or when the effect
happens?**

| The ASSET owns — set once in Studio | The SCORE owns |
|---|---|
| `Lifetime`, `Speed`, `SpreadAngle`, `Drag` | `Enabled` — when it produces |
| the `Size` / `Color` / `Transparency` **curves** | `Emit(n)` — a burst |
| Texture, `Squash`, `Rotation` | a Beam's `Width0`, a light's `Brightness` |

**A ParticleEmitter is already an animation engine** — it animates its own
particles over their lifetime through those curves, with a graph widget in the
Properties panel. Keying `Rate` and `Speed` frame by frame on the timeline
re-implements that badly.

**This is not "never key a property."** A beam widening and a light dimming are
exactly what property tracks are for.

### Attachment or Part? Both, and picking wrong is silent

Common advice is "always use an Attachment." **Conditional** — `Aura.luau`
records why from earlier research:

| Parent | Emits from | Use for |
|---|---|---|
| **Attachment** | a **point** | an impact spark, a precise burst |
| **BasePart** | a **shape sized by the part** | a wall of wind, a column — anything using `Shape` |

Sphere and Cylinder shapes *"will not display correctly"* on an Attachment —
and the failure is silent. The emitter runs, particles fly, and a column quietly
becomes a fountain from one spot, which reads as a badly tuned effect rather
than a structural mistake.

### A span is two keys

"The emitter runs from 0.4 to 1.3" looks like it needs a start-and-end concept.
It does not — the relevant properties are booleans:

```lua
{ target = "Blade.Sparks", property = "Enabled",
  keys = { { t = 0.4, v = true }, { t = 1.3, v = false } } }
```

`Sound.Playing` works the same way. **Triggers are only for genuine one-shots**
— `Emit(n)`, which has no property to hold.

**And letting an effect linger past the animation needs nothing:** extend the
Score's `duration` past the clip, and already-emitted particles survive on their
own `Lifetime` after the emitter stops.

**And "one particle, emit once, disappear" is specifically a trigger:**

```lua
emitter.Rate = 0        -- never emits on its own, ever
emitter:Emit(1)         -- the Score decides every burst
```

Leave `Rate` at zero permanently and let the timeline own emission. Keying
`Rate` 0 → 60 → 0 across one frame is the obvious alternative and it is
frame-rate dependent garbage — you get zero particles or a dozen depending on
that frame's `dt`.

### 1.2 — Add the effect children NOW, not later

This is the step that is easy to skip and expensive to skip. **A Score's
`target` is a path into this hierarchy**, so the shape you build here *is* the
vocabulary you get to animate:

```
Sword                    <- the root you will hand the Conductor
├── Blade                   a MeshPart
│   └── Trail               a Trail
└── Glow                    a PointLight
```

Add a `Trail`, a `PointLight`, a `ParticleEmitter` — whatever the attack might
want. An empty prefab gives you nothing to drag.

**Renaming any of these later silently breaks the Score.** The path resolves to
nothing, the track animates nothing, and no error is raised.

### 1.3 — Weld it to the hand

A `WeldConstraint` to `RightHand`. It then rides the arm through the
character's own `Animator` for free — no second rig, no `AnimationController`,
nothing extra.

> **Only weld.** Do not add a `Motor6D` unless you want the sword to move
> *independently of the hand* — that makes it a joint in the rig and a thing the
> Animation Editor has to animate. Start welded.

### 1.4 — Save to File

`Right-click the Model → Save to File → assets/models/`

**Rojo syncs one way.** Anything built by clicking in Studio is invisible to
git until you explicitly export it. Skip this and the sword exists on one
machine and nowhere else.

---

## Phase 2 — Animate the rig

### 2.1 — Author the swing

Studio's Animation Editor, on an R15 rig.

### 2.2 — Set priority to `Action` AT AUTHOR TIME

**The single most common first-day bug.** A swing left at `Core` is silently
overpowered by the default walk cycle and does not appear to play — which looks
*identical* to a failed asset load, and neither one errors.

`Action` outranks `Movement`, which is also what lets an upper-body swing play
over a walk cycle without this system doing anything.

### 2.3 — Publish under the GROUP

Not your account. This is the only irreversible step in the pipeline.

### 2.4 — Paste the id into the manifest

`src/shared/definitions/AnimationManifest.luau`:

```lua
WARRIOR_SWING_1 = {
    assetId = "rbxassetid://123456789",   -- was NOT_UPLOADED
    priority = Enum.AnimationPriority.Action,
    fadeTime = 0.1,
    loadFor = { "WARRIOR" },
}
```

**Milestone: click now plays the swing.** `InputSystem` already calls
`rig:play("WARRIOR_SWING_1")`.

### 2.5 — If nothing animates

| Symptom | Cause |
|---|---|
| `[Rig] 1 animation(s) not uploaded yet` | the id is still `NOT_UPLOADED` |
| Warn after ~10s: *"still report Length 0 … animate NOTHING"* | **wrong owner.** `AnimationTrack.Length` stays 0 forever when an asset fails to resolve, and that is the only symptom the ownership trap produces |
| No message, no movement | priority. Authored at `Core`, losing to the walk cycle |

---

## Phase 3 — Author the effects, in the dev tool

**Turn it on:** select `Workspace` in the Explorer **with the game running** →
Properties → tick `DebugConductorTool`.

Not the command bar — that runs as the *client* during a play test, and
attributes do not replicate upward.

### 3.0 — The layout

```
┌─ Conductor Dev ─────────────────────────────────┐  ← drag by the header
│ root [Workspace.Sword        ] [Set]            │
│ duration ─────────●────────────  1.40           │
│                                                 │
│ TIMELINE — click a lane to edit, ruler to scrub │
│  0.00     0.28     0.56     0.84    1.12   1.40 │  ← click to scrub
│  clip WARRIOR_SWING_1  ▐████████████████▌       │
│  Blade.Trail.Transp      ●═══════●────●         │  ← bar = span, tick = key
│  Glow.Brightness       ●══════════════●         │
│  EMIT Blade.Sparks              ◆               │  ← a point, not a span
│                            ┃                    │  ← playhead
│                                                 │
│ [Blade.Trail][Transparency]         [+ Track]   │
│ [WARRIOR_SWING_1     ][at]          [+ Clip]    │
│ [Blade.Sparks][EMIT][at][n]         [+ Trigger] │
│                                                 │
│ scrub ────────●──────────────  0.42             │
│ [Play][Stop][Revert]  [Fissure  ][Export]       │
│                                                 │
│ SELECTED                                        │
│  Blade.Trail . Transparency  (number)           │
│  value ──────────●─────────  0.35               │
│  range [0    ] [1    ]                          │
│  ease  [CUBIC_OUT   ]  arriving at the key      │
│  keys  0.08 0.20 0.50      [Key] [Clear]        │
│  [Remove track]                                 │
└───────────────────────────────────────────────◢─┘  ← resize
```

**Why a select-to-edit pane rather than controls on every lane:** inline
controls are fine for two tracks and unusable at ten — four emitters, a beam
and a clip is six lanes of widgets, and the timeline gets pushed off the bottom
of the panel by the things meant to edit it.

**Why the timeline exists at all**, when the numbers were already editable: the
question an animator actually asks is *"does the burst land ON the impact
frame, or just after it?"* That is a question about two things **relative to
each other**, and no column of numbers answers it at a glance.

### 3.1 — What each control is, and why it exists

| Control | Does | Why it is there |
|---|---|---|
| **root** | the Instance every path resolves against | A Score is text in git and plays on *every* clone of a prefab. An Instance reference cannot be serialised, so targets are paths and the root is supplied at play time |
| **duration** | how long the Score runs | **Authored, not derived from the last key.** A delayed slash is a 0.4s flourish, 800ms of nothing, a burst at 1.2s — derive duration from the last key and that gap becomes unexpressible |
| **+ Track** (target, property) | adds a property track | It **reads the current value** to pick the control. You never declare a type, so there is nothing to disagree with the instance. **Nothing is rejected** — number, boolean and Color3 get an inline widget; every other type is keyed by capture |
| **slider** | drag to set the value | **The reason the tool exists.** The property is written live, so you are looking at the real thing while you choose the number |
| **range min / max** | slider bounds | Without them a slider is useless for anything not 0–1. `Transparency` is 0–1; `Brightness` runs to 100; a `ParticleEmitter`'s `Rate` to hundreds |
| **Key** | commits the **staged** value — what the slider is showing | **Only ever an explicit gesture.** Auto-keying from property changes litters keys on every nudge and makes an intentional edit indistinguishable from an accident |
| **Key current** | commits whatever is **on the instance right now** | **The only gesture that works for every type.** Move a prop with Studio's move tool, or type a Vector3 into the Properties panel — however the value got there, this captures it. It is what makes `CFrame` and `Vector3` authorable without six sliders, and it is the better gesture even where a slider exists |
| **Clear** | drops a track's keys | |
| **X** | removes a track and restores the property | |
| **+ Clip** (name, at) | schedules a rig animation inside the Score | `at` is a moment in the **Score's** time. This is what makes a wind-up *before* the swing expressible |
| **+ Trigger** (target, action, at, n) | a one-shot at a moment — `EMIT` or `SOUND` | **A particle burst is `Emit(n)`, a method, not a property.** There is no value to interpolate toward, so no property track expresses it at any key density |
| **Test** (on a trigger) | fires it now, ignoring the transport | Scrubbing deliberately does not fire triggers — dragging a playhead across t=0.3 would emit every time it crossed. This is how you see one without watching the whole Score |
| **scrub** | evaluates the Score at one moment | Calls `Conductor.evaluate` — **the same function the game runs.** A separate preview path means tuning against something the game will not reproduce, which is what kills homemade editors. Not difficulty. Divergence |
| **Play** | runs the whole transport | Fires clips too. Scrubbing does not — a clip is an *event*, not a value at a moment, so there is no half-started animation to show |
| **Stop** | cancels | Stops clips it started, even ones marked `letFinish` |
| **Revert** | restores every property the tool touched | |
| **Export** | prints paste-ready Lua to the output | |

> **Editor and engine cover the same types, and that was a real defect until
> 2026-08-23.** The editor accepted three while `Evaluate.lerpValue` handles
> seven, so an animated beam offset or a moving prop — both ordinary — could
> only be authored by hand-editing the exported file.
>
> **The fix is capture, not more sliders**, and it is what `Timeline.md` Part
> 7.1 described from the start: *"move the claw while at 0.4 → read its current
> `CFrame` → write a key."* Six sliders for a CFrame would have been strictly
> worse than the move tool Studio already ships.

### 3.2 — The loop

```
1. set root            Workspace.Sword
2. + Track             Blade.Trail  /  Transparency
3. DRAG                until it looks right
4. set scrub time, Key
5. move scrub, drag again, Key
6. + Clip              WARRIOR_SWING_1 @ 0.0
7. Play                watch the whole thing
8. repeat 3-7
9. Export
```

**Steps 3 and 7 are the whole point.** Everything else is bookkeeping around
being able to look at the thing while you decide.

### 3.3 — Why Export prints instead of writing the file

A running game cannot write to the repo. **Rojo syncs one way** — filesystem to
Studio — and nothing in a live session can reach back.

So copy from the output window into
`src/shared/definitions/scores/<Name>.luau`. Same manual commit point as
`Save to File` for models. A plugin with filesystem access could close it, and
that is a much larger tool.

---

## Phase 4 — Turn it into content

### 4.1 — The Score

Paste the export. Done — it is already a valid `.luau` file body.

### 4.2 — The hitbox — **GAP, NOT BUILT**

The design is a `PATH` track: sample the weapon's `CFrame` relative to the root
each frame while the swing plays, and write the list into the skill definition.

> **STORE THE PIVOT, NOT THE BLADE TIP.** Interpolating two positions gives a
> straight line and a blade travels an arc. `CFrame:Lerp` slerps rotation, so a
> pivot-relative path traces the true arc at any key density. Tip positions work
> on a dense recording and fail badly on a sparse hand-authored one — the case
> nobody thinks to check. `HitDetection.md` 9.4.0.

**The recorder does not exist.** Until it does, a skill's volume stays
hand-tuned against `DebugHitboxes` — which is authoring by looking, just with a
coarser instrument.

### 4.3 — The skill definition

`src/serverShared/definitions/skills/<Name>.luau`. Drop `planned = true` and
fill in what the previous steps produced:

```lua
return {
    id = "FISSURE",
    displayName = "Fissure",
    volume = { ... },        -- captured in 4.2
    clip  = "WARRIOR_SWING_1",
    score = "FISSURE",
}
```

**Filename → id:** `BasicSwing.luau` → `BASIC_SWING`. An `_` before every
capital that follows a lowercase or digit, then uppercased. A mismatch is a boot
failure naming the expected id. Acronym-led names do not split
(`AOEBlast` → `AOEBLAST`).

### 4.4 — Wiring skill → clip + score — **GAP, NOT BUILT**

Nothing reads `clip` or `score` off a skill yet. `InputSystem` names its clip
literally and no Score is played on attack.

What it becomes: the client resolves the skill's `clip` and `score` and hands
both to the Conductor as one Score with a clip track. **One name crosses the
wire; everything cosmetic is a local lookup.**

---

## What is built and what is not

| Phase | State |
|---|---|
| 1 — build the prefab | **manual, ready** |
| 2 — animate, upload, manifest | **ready.** One blank to fill |
| 3 — author effects in the tool | **BUILT, never run** |
| 4.1 — paste the Score | ready |
| 4.2 — capture the hitbox | **NOT BUILT.** Hand-tune against `DebugHitboxes` |
| 4.3 — write the skill row | ready |
| 4.4 — skill drives clip + score | **NOT BUILT** |

**Nothing in Phase 3 has ever run.** Every line is written and unvalidated;
expect the first session to surface something.

---

## Related

| Document | |
|---|---|
| `Animation.md` | clips, upload, ownership, the manifest, why a marker never drives damage |
| `Timeline.md` | the Conductor and the Score — the engine this workflow authors for |
| `HitDetection.md` | hit volumes, `motion = PATH`, and why the hitbox is never a real part |
| `AssetPipeline.md` | where things live, what replicates, and the Rojo art path |
| `NextSteps.md` | what to build next, and why in that order |
