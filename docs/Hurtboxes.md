# Hurtboxes — What They Are And How You Author One

### The working manual for the thing that gets hit

> **Why this document exists.** `HitDetection.md` records *why* hurtboxes are
> shaped the way they are — four revisions, the arguments that killed three of
> them, the cost tables. It is a design record, and it assumes you already know
> the vocabulary.
>
> This is the other half: **what a hurtbox is, in plain terms, and what you
> physically do to make one.** It starts from coordinates, because the sentence
> *"I have no idea what CFrames are"* was said out loud while reading the
> design record, and no amount of good design survives a reader who cannot
> parse the notation.
>
> **The split, so neither document grows the other's job:**
>
> | Document | Answers |
> |---|---|
> | `HitDetection.md` §7 | *why* capsules, *why* layered, what was rejected and what test catches it |
> | **this one** | what a CFrame is, what a hurtbox is, and the steps to author one |
>
> Where they overlap, `HitDetection.md` is authoritative on the *decision* and
> this document is authoritative on the *procedure*.
>
> **Status tags** are the same four `Architecture-Reference.md` uses —
> **SETTLED**, **PROVISIONAL**, **UNBUILT**, **SUPERSEDED**. Read them. Most of
> this document is UNBUILT on purpose: the design is decided and the code is
> one capsule per entity.
>
> **And the same standing rule applies.** Nothing here is an axiom. If a
> concrete decision conflicts with something written here, question the
> document first — the authority is the reasoning, not the text.

---

## Table of Contents

1. The Vocabulary — Studs, Vector3, and CFrame
2. What A Hurtbox Is, And What It Is Not
3. The Capsule — Why This Shape And Not Another
4. Where The Geometry Is Authored — Three Routes
5. Authoring One By Hand, Step By Step
6. The Export Round Trip — Why Nothing Needs Repositioning
7. `HurtboxComponent` — What It Owns, And Why It Is Its Own Thing
8. History And Rewind — The Part That Is Blocked On A Test
9. Rejected Designs
10. Current State

---

## Part 1 — The Vocabulary — Studs, Vector3, and CFrame

**Status:** SETTLED. Platform facts, not decisions.

Everything in this document is built out of three ideas. None of them is hard,
and all three get used without introduction everywhere else in the codebase.

### 1.1 — Studs

Roblox's unit of distance. Not metres, not feet — studs.

The only calibration worth memorising:

| Thing | Size |
|---|---|
| An R15 character | ~**5 studs** tall, ~**2 studs** wide |
| A default character's head | ~1 stud |
| The current player hurtbox | radius 1.5, halfHeight 1.5 → 6 studs tall, 3 wide |
| `BASIC_SWING` reach | 6.5 studs |

**Y is up.** X and Z are the ground plane. This matters constantly and is the
first thing to get backwards.

### 1.2 — `Vector3` — three numbers

```lua
Vector3.new(4, 10, -2)
```

That is the whole type. What it *means* depends entirely on how it is used:

| Used as | Means |
|---|---|
| a **position** | a point in the world: 4 right, 10 up, 2 forward |
| a **direction** | which way something points (usually length 1, a "unit vector") |
| a **size** | how big something is along each axis |
| an **offset** | how far to move from somewhere else |

**The ambiguity is deliberate and it is why the same type appears everywhere.**
A `Vector3` is three numbers; the meaning lives in the variable's name, not in
the type. `part.Size` and `part.Position` are the same type and nothing stops
you from adding them together, which is exactly the mistake that produces a
hurtbox in a strange place.

Useful things it can do:

```lua
(a - b).Magnitude        -- distance between two points
(a - b).Unit             -- the direction from b to a, length 1
a:Dot(b)                 -- how much a and b point the same way
```

**`Magnitude` costs a square root.** That is why `SpatialService`'s broadphase
compares `offset:Dot(offset)` against `limit * limit` instead — the same test
without the square root, run once per attached entity per query.

### 1.3 — `CFrame` — position *and* rotation, together

**CFrame is short for Coordinate Frame.** It is a `Vector3` position plus a
rotation, carried as one value.

**Why they are one type rather than two.** Almost nothing needs a position
without also needing to know which way the thing is facing. A sword swing
starts at your hands *and* goes the way you are looking. A capsule stands up
along its body's own up direction, not the world's. Splitting them would mean
passing two arguments everywhere and, eventually, passing them out of sync.

What it holds:

```
position     a Vector3           where it is
rotation     three unit vectors  which way its own X, Y and Z point
```

Twelve numbers in total — three for position, nine for the rotation. You will
never type those twelve numbers. You read them back through named properties:

```lua
cf.Position       -- Vector3: where it is
cf.LookVector     -- Vector3: the direction it faces
cf.UpVector       -- Vector3: its own "up"
cf.RightVector    -- Vector3: its own "right"
```

> **THE GOTCHA THAT COSTS EVERYONE A DAY: `LookVector` is NEGATIVE Z.**
>
> A part faces along its own **-Z** axis. So a Block whose `Size.Z` is its
> longest dimension is "long in the direction it faces," and
> `CFrame.new(0, 0, -length)` moves something *forward*, not backward. Every
> piece of code in this repo that builds a blade or a volume runs along -Z for
> this reason, and each one says so in a comment because it reads wrong.

### 1.4 — The one operation that makes hurtboxes work

```lua
cf * Vector3.new(0, 2, 0)
```

Read it as: **"start at `cf`, then move 2 studs along `cf`'s OWN up direction,
and tell me where that lands in the world."**

Compare it against the thing it is easy to write instead:

| Expression | Means | When the body tilts |
|---|---|---|
| `cf * Vector3.new(0, 2, 0)` | 2 studs along the **part's** up | **the offset tilts with it** ✓ |
| `cf.Position + Vector3.new(0, 2, 0)` | 2 studs along the **world's** up | the offset stays stubbornly vertical ✗ |

**That single difference is why a hurtbox leans when its body leans.** It is
also an error you cannot see until something falls over, gets knocked down, or
plays an animation that tips it — which is to say, exactly the moments hit
detection is being watched.

This is the line that does it, and it is the entire geometric content of a
capsule hurtbox:

```lua
-- SpatialComponent:endpoints
local offset = Vector3.new(0, half, 0)
return cf * offset, cf * -offset
```

Two other forms worth recognising:

```lua
cfA * cfB                       -- compose: "cfB's frame, expressed relative to cfA"
cf:PointToObjectSpace(world)    -- the reverse: a world point, in cf's local terms
CFrame.lookAt(from, to)         -- build a CFrame at `from`, facing `to`
CFrame.new(4, 10, -2)           -- a position with no rotation
```

`CFrame.lookAt` is what `HurtboxDebug` uses to lay the shaft of a capsule
between its two endpoints.

### 1.5 — World space and local space

Two ways of saying where something is, and the words appear constantly:

| Term | Means |
|---|---|
| **world space** | coordinates relative to the world's origin. What `part.Position` reports |
| **local space** / **object space** | coordinates relative to *some other thing's* frame — "2 studs above the arm's centre, in the arm's own terms" |

`cf * offset` converts local → world. `cf:PointToObjectSpace(p)` converts
world → local.

**A hurtbox is authored in local space and tested in world space.** You place a
part relative to an arm; the overlap maths needs world coordinates. The `*`
operator is the whole conversion, and it is why nothing has to be recomputed
when the arm moves — the local offset never changed.

---

## Part 2 — What A Hurtbox Is, And What It Is Not

**Status:** SETTLED 2026-08-20.

### 2.1 — The definition

**A hurtbox is the volume that can be hit.** Not the model, not the mesh, not
the collision shape the physics engine uses. A separate, simpler shape that
exists only to answer one question: *did that attack land on this body?*

### 2.2 — It is not an Instance, and this is the important part

There is no hurtbox object. Nothing is parented anywhere. It does not
replicate, does not render, and does not have a position that could fall out of
step with the body it belongs to.

It is **a pointer and two numbers**:

```lua
spatial.anchor       -- a BasePart in the world
spatial.radius       -- a number
spatial.halfHeight   -- a number
```

plus one function that turns them into a shape at the moment somebody asks:

```lua
function SpatialComponent:endpoints(cf)   -- cf * (0, ±halfHeight, 0)
```

**Nothing is stored between calls.** No update step that could run late, no
cached copy that could go stale, no second position to keep in sync. Ask where
the hurtbox is and you get the anchor's `CFrame` transformed, computed on the
spot.

### 2.3 — The consequences of that, which are the whole reason it is built this way

| Because it is derived, not stored | Consequence |
|---|---|
| there is no stored position | **it cannot desync from the rig.** Ever. On any entity. There is no sync step to get wrong |
| it moves because the part moves | animating the body animates the hurtbox, for free, with no extra system |
| it costs nothing at rest | no per-frame work for a body nobody is attacking |
| it has no visual | **if you want to see it, something must draw it** — see 2.5 |

### 2.4 — Hurtbox versus hitbox

The two words get used interchangeably everywhere on the internet and they are
not the same kind of thing here.

| | Hurtbox | Hitbox |
|---|---|---|
| Belongs to | a **body** — the thing being attacked | an **attack** |
| Exists | continuously, as long as the body does | for the duration of one swing |
| Is | **observed state** — "where was that arm 100ms ago" is a real question | **generated data** — computed on demand from the attacker's pose |
| Needs history | **yes**, that is what the ring buffer is for | no. It is created, used, and discarded |
| In code | `SpatialComponent` (→ `HurtboxComponent`) | `HitVolume` on a skill definition |

**A hurtbox is remembered. A hitbox is calculated.** That asymmetry is why one
of them has a 47-slot ring buffer and the other is a plain table.

### 2.5 — The overlay is a picture of a hurtbox, not a hurtbox

`DebugHurtboxes` draws three parts per capsule — a ball at each end and a block
spanning them — because Roblox has no capsule to draw (Part 3). Those parts are
a *drawing*. Destroying them does not remove the hurtbox; nothing in targeting
can see them.

**This distinction produced a real bug report.** An earlier version of the
overlay teleported server-owned parts to the server's copy of your body, so it
trailed you by a full network round trip and read as "my hurtbox is lagging."
Nothing was lagging except the picture. `HitDetection.md` §7.11 has the full
account; the overlay is now welded to the body and cannot trail it.

---

## Part 3 — The Capsule — Why This Shape And Not Another

**Status:** SETTLED. The full argument, with its rejected alternatives, is
`HitDetection.md` §7.0–§7.3. This is the summary you need to author against.

### 3.1 — What a capsule is

**A segment, thickened by a radius.** A line with a round tube around it and a
hemisphere on each end — a pill.

```
   ___
  /   \     ← hemisphere cap        radius   how thick
 |     |                            segment  from one endpoint to the other
 |     |    ← the straight part
 |     |
  \___/     ← hemisphere cap
```

In code it is exactly the two endpoints and the radius:

```lua
local capA, capB = spatial:endpoints(pose)   -- the segment, in world space
local radius     = spatial.radius
```

Total height is `2 * halfHeight + 2 * radius` — the straight part, plus a
hemisphere at each end. **That is the arithmetic people get wrong when a
hurtbox comes out too tall.**

### 3.2 — A sphere is a capsule with a zero-length segment

When `halfHeight` is `0`, both endpoints land on the same point and the capsule
collapses to a ball.

**This is a real generalisation, not a compromise.** Every overlap function
takes `(a, b, radius)`; a sphere passes `a == b` and the same maths produces
the right answer. There is no branch, no second family of functions to keep in
agreement, and no "is this a sphere?" check anywhere in the codebase.

### 3.3 — Roblox has no capsule, and it does not need one

`Enum.PartType` is exactly five things:

| | |
|---|---|
| `Ball` | a sphere |
| `Block` | a rectangular prism |
| `Cylinder` | a cylinder — **circular faces on X**, which is why one inserted in Studio arrives lying on its side |
| `Wedge` | a triangular prism |
| `CornerWedge` | a corner wedge |

**No capsule.** There is no capsule mesh and no capsule model either.

**And nothing needs one**, because a capsule here is never instantiated. It is
a segment and a number that `Overlap` computes a distance against. There is
nothing to create.

### 3.4 — Why a capsule rather than a box

Two reasons, and the second is the durable one.

**It fits a limb.** Arms, legs, tails, necks and horns are cylinders. A box
around a cylinder over-covers the corners — a square circumscribing a circle
has about **27% more area** than the circle, and that surplus is space where
attacks connect with nothing.

**It keeps the maths closed-form.** Everything reduces to *distance between two
simple sets, then compare against summed radii*:

| Target shape | vs `SPHERE` | vs `CAPSULE` | vs `BOX` | vs `ARC` |
|---|---|---|---|---|
| **capsule** | closed form | closed form | iterative | exact radially, 3 candidates |
| **oriented box** | closed form | iterative | SAT, 15 axes | approximate, 9 candidates |

A box has no radius to sum, so half the matrix loses its exact answer.

### 3.5 — It is a default, not a mandate

`shape = "BOX"` and `shape = "SPHERE"` are supported per hitzone. **A torso
genuinely is a box.** Use it there.

The cost of `BOX` is the table above; the cost of `SPHERE` is nothing at all,
because it is the degenerate capsule.

### 3.6 — Complexity is absorbed by COUNT, not by the primitive

The most important sentence in this document for authoring purposes.

**A curved horn is not one clever capsule. It is three simple ones.**
`HB_Horn_1`, `HB_Horn_2`, `HB_Horn_3`, laid along the curve, each fitting its
own stretch. A crescent wing is three for the same reason.

**The primitive stays dumb; the count goes up.** There is no cap on hitzone
count, and each extra one costs a segment-distance calculation — nanoseconds,
and only on candidates that already survived the broadphase.

This is also the reason hand-authoring suits the design better than deriving
does: **layering is a drag operation.** A derivation gives you exactly one
capsule per part and no way to say "that curve needs three."

---

## Part 4 — Where The Geometry Is Authored — Three Routes

**Status:** SETTLED 2026-08-20. Full argument in `HitDetection.md` §7.2.3.

### 4.1 — The rule that governs all three

> **Hurtbox geometry must live in the model, not in a table that has to be kept
> in agreement with the model by hand.**

The failure being avoided is a **parallel skeleton** — geometry defined
somewhere else that silently goes stale when the rig changes. That is what
killed the rejected sphere-list design (Part 9).

**Hand-authoring is not the failure.** A hurtbox part inside the rig *is* in
the model.

### 4.2 — The three routes

| | Geometry lives in | Authored with | Diffable | Goes stale when |
|---|---|---|---|---|
| **A — derive** `{ part = "Tail" }` | the visual part's `Size` | nothing | n/a | never |
| **B — declare** `{ part = "Tail", radius = 1.1 }` | a Lua table, keyed to a part | typed numbers | **yes** | the mesh is resized and the number is not |
| **C — author** `{ part = "HB_Tail" }` | a real part inside the rig | **a mouse, in Studio** | no | the mesh is reshaped and the hurtbox part is not |

**All three end as the same thing: an anchor part, a radius, a halfHeight.**
Whether the anchor is called `Tail` or `HB_Tail` is a string. Whether the
radius came from `capsuleFromSize` or a typed field is one `or`.

**There is no branch, no mode, and no cost to mixing them per hitzone on the
same model.** This is a workflow choice, not an architecture choice, and it
never has to be made once for the whole game.

### 4.3 — What each is for

**A — derive.** Standard limbs that are honestly cylindrical and square to
their own axes. Free, cannot drift. Use it and move on.

**B — declare.** A one-number correction to an otherwise-fine derivation. Bad
as a primary workflow: you eyeball in one window and type in another.

**C — author.** Bosses, anything with anatomy worth reading, and every case
where `Part.Size` lies. **The feedback loop is instant and visual, which is why
it wins** — hitbox feel is judged by looking, and this is the only route where
looking and changing happen in the same window.

### 4.4 — When deriving lies

`MeshPart.Size` is the **axis-aligned bounding box in the part's own local
axes**. Tight only when the geometry is authored square to those axes.

| Case | What goes wrong |
|---|---|
| A limb modelled on a diagonal | the box is far larger than the limb; the radius inflates to cover empty corner |
| A curved horn, tusk or claw | the box spans the chord of the curve; the capsule fills the hollow side |
| One outlying spike or spur | a single vertex drags a dimension out and fattens everything |
| A flat plate — wing, blade, shield | the shortest axis sets the radius, so it becomes a thin rod through the middle and the plate is uncovered |
| A pivot that is not the centroid | the segment centres on the part's centre, not on where the mass is |

**That list is most of what makes a boss interesting to look at.** Derive
limbs; author anything with character.

---

## Part 5 — Authoring One By Hand, Step By Step

**Status:** PROVISIONAL — the shape is decided, and no rigged model has been
authored yet. Expect this Part to gain detail the first time it is used for
real.

### 5.1 — The steps

```
1. Open the rigged model in Studio
2. Insert a Part.  Shape = Block.  Name it HB_<Zone>  (HB_Head, HB_Tail…)
3. Position, rotate and size it over the limb it covers, by eye
4. Add a WeldConstraint:  Part0 = the limb,  Part1 = your HB_ part
5. Set Transparency = 1, CanCollide / CanQuery / CanTouch = false, Massless = true
6. Repeat. Use SEVERAL for anything curved (3.6)
7. Right-click the Model → Save to File → assets/models/Golem.rbxm
8. Add the names to the hitzone list in the Content Layer
```

Step 8 is names only:

```lua
GOLEM = { hitzones = { "HB_Head", "HB_Torso", "HB_LeftClaw", "HB_Tail" } }
```

**No offsets. No sizes. No coordinates.** The geometry is in the `.rbxm`, which
is the point of route C.

### 5.2 — Why `Block` and not `Cylinder`

Not a style preference. `Part.Shape = Cylinder` runs along **X**, while the
legacy `CylinderMesh` runs along **Y**. Two axes for one word, and the failure
is a hurtbox pointing sideways with nothing in a diff to explain it.

**A `Block`'s `Size` means the same thing in every orientation.** The
derivation reads its longest local axis and there are no surprises.

### 5.3 — Why `WeldConstraint` and not `Motor6D`

A **Motor6D** exists so two parts can move *relative to each other*. That is
what an animated joint needs, and it is what the Animator writes to.

A hurtbox part does not move relative to its limb — **it rides rigidly on one
that is already animated.** A `WeldConstraint` to that limb is the whole
attachment, and adding a Motor6D would create a joint the Animator does not
know about.

### 5.4 — The gotcha while eyeballing

**A capsule inscribed in a Block is smaller than the Block** — the corners get
cut. The box you draw is not what you get; the capsule inside it is.

This is the same mismatch that made the first debug dummies disagree with their
own hurtboxes, and it is precisely why `HurtboxDebug` draws the **capsule**
rather than the Block. **You author against the thing you are shipping.**

**If a part is genuinely boxy, `shape = "BOX"` makes the Block you drew exactly
what you get** — no inscription, perfect WYSIWYG. Reach for it on a torso or a
shield. Do not reach for it to avoid thinking about a capsule.

### 5.5 — Checking your work

Turn on `DebugHurtboxes` (a Workspace attribute, editable while the game runs)
and look. A badly-fitting capsule is obvious in one second and invisible
forever otherwise.

`DebugHurtboxServerView` is a *different* instrument — it draws the same shapes
in amber from the server's copy, deliberately lagging, to show how far behind
the server is. It is a latency measurement, not a shape check.

---

## Part 6 — The Export Round Trip — Why Nothing Needs Repositioning

**Status:** SETTLED. Written because the question *"how do I put the part back
where it's supposed to be?"* is the natural one to ask and rests on a wrong
premise.

### 6.1 — An `.rbxm` is not geometry, it is an instance tree

Saving a Model to a file serialises **every descendant, every property, every
CFrame, and every joint**. `HB_Tail` goes into the file as a child of the
model, at the exact position you left it, with its `WeldConstraint` intact.

### 6.2 — So there is nothing to put back

```lua
local golem = ServerStorage.Models.Golem:Clone()
golem:PivotTo(spawnCFrame)
golem.Parent = workspace
```

Three lines, and every hurtbox part is exactly where you authored it, because
**a weld is a rigid relationship stored in the file**, not something
reconstructed at runtime. `PivotTo` moves the whole assembled rig as one.

**No code that positions hurtboxes. No offsets to fidget with. No baked data
points.** The positions *are* the file.

### 6.3 — The precedent already running

`DummySpawner` builds a three-part body in Lua and the pieces stay put forever
without anything maintaining them. The only difference with a real model is
that you author by dragging instead of by typing.

### 6.4 — What this means for `.gitignore`

The `.rbxm` is the artefact that matters and it belongs in git. `AssetPipeline.md`
Part 6 covers the whole path — including the one thing that is easy to get
wrong, which is that **Rojo syncs one way** and a model you built in Studio is
not in the repo until you explicitly `Save to File`.

---

## Part 7 — `HurtboxComponent` — What It Owns, And Why It Is Its Own Thing

**Status:** UNBUILT. Designed in `HitDetection.md` §7.7.

### 7.1 — What it is not for

**It does not connect parts to models.** Nothing needs connecting — Part 6.
The parts arrive welded because the file says they are welded.

### 7.2 — What it actually owns

| Owns | Why |
|---|---|
| **the hitzone list** | N entries of `(partId, anchor, radius, halfHeight, shape)` instead of `SpatialComponent`'s single set |
| **per-limb history** | rewind must answer *"where was the claw 100ms ago"*, and limbs move independently — see Part 8 |
| **a cached bounding radius** | so broadphase stays **one** cheap sphere test per entity and only survivors pay for all six capsules |

### 7.3 — Why it is separate from `SpatialComponent`

**Honestly: it does not have to be.** `SpatialComponent` could grow a list and
the game would work. Two arguments for splitting, in order of strength.

**The practical one.** Growing `SpatialComponent` means rewriting `record`,
`poseAt`, `getCFrame` and `endpoints` to be list-shaped, and changing every
existing caller with them. Leave it as *"where one thing is, and where it
was"* — which is built and tested — and let `HurtboxComponent` hold N of them.

**The tidiness one.** Plenty of things need a position without a hurtbox:
ground markers, spawn points, AI waypoints, a projectile's origin. Almost
nothing needs a hurtbox without position. **Position is the general fact; the
hurtbox is a specialisation bolted onto it**, and `Architecture-Reference.md`
Part 3 wants a Component's truth checkable by looking at itself alone.

| Component | Owns |
|---|---|
| `SpatialComponent` | anchor, pose ring buffer, `poseAt` |
| `HurtboxComponent` | the hitzone list, and the bounding radius derived from it |

**Split when the list lands, not as a later cleanup** — otherwise the anatomy
arrives in `Spatial` by inertia and nobody pays to move it.

---

## Part 8 — History And Rewind — The Part That Is Blocked On A Test

**Status:** OPEN. This is the one genuine unknown in the whole design.

### 8.1 — Why history exists at all

A player attacks what they see, and what they see is old — the server's
snapshot took time to arrive and their client interpolates on top of it. So the
server rewinds every *target* to where it was when that player pressed the
button. `SpatialService` stores 1.5 seconds of poses in a ring buffer and
reaches back at most 0.5.

**Only targets are rewound. The attacker is not.**

### 8.2 — Multi-capsule makes it a buffer per limb

One ring buffer on the root can answer *"where was this body"*. It cannot
answer *"where was this claw"*, because limbs move independently — that is what
animation is.

Cost, if it is needed: five hitzones × 47 samples ≈ **21KB per boss**, and
sampling goes from one `CFrame` read per tick to five.

### 8.3 — The test that decides it

**Does the server see animated limb positions at all?**

`Motor6D.Transform` is written by the Animator every frame and **is not
replicated**. The working assumption is that parts replicate even though joint
transforms do not, so the peer running the Animator has live part CFrames.
Published sources conflict and this has never been checked here.

**How to run it, and it does not need the asset group:** give a dummy a
`Humanoid` and let it walk. An NPC's `Animate` script runs on the *server*, so
it is already playing animations server-side. Print a hand part's `CFrame`
every 0.2s from a server Script and watch whether the numbers move.

| Result | What `HurtboxComponent` becomes |
|---|---|
| limb CFrames **move** | the full design — list + a ring buffer per hitzone |
| limb CFrames are **frozen** | much smaller — list + fixed offsets from the root, no per-limb buffers. Anatomy still resolves correctly at rest; limbs just do not swing independently |

**Run this before building `HurtboxComponent`.** It changes how much component
there is to build.

---

## Part 9 — Rejected Designs

**Status:** SETTLED. Each kept with the test that catches it, per
`Architecture-Reference.md`'s pattern.

**One enveloping sphere per body.** What ships today, and a placeholder rather
than a stage. A sphere large enough to cover a boss covers **the space between
its limbs** — under a raised arm, between the legs, past the side of the head.
Already wrong for players: 2.5 radius on a 2-stud-wide body.
*Test that catches it: turn on the overlay and look at any body that is not a ball.*

**A list of spheres with offsets in a Lua table.** Right about the count, wrong
twice over — a sphere fits a limb badly in the long direction, and the offsets
are a **parallel skeleton** that goes stale the moment the model changes.
*Test that catches it: resize a limb in Blender and see whether anything in the diff mentions the hurtbox.*

**The visual part IS the hurtbox — an oriented box from `part.Size`.** Zero
authoring, and it throws away the angular half-width trick and pays nine
candidate points for an approximation in every direction.
*Test that catches it: ask what `asin(radius/distance)` needs, and notice a box has no radius.*

**Use the model's real mesh geometry.** The equations do not survive the export
— a curve becomes triangles — and Roblox's own `CollisionFidelity` has five
modes, **none of which uses the exact render mesh**, including the one named
"Precise." The decisive reason is not cost though: if the hurtbox is the mesh,
**every art change is a balance change**, silently, with nothing in the diff.
*Test that catches it: would tweaking a silhouette in Blender rebalance a fight?*

**Deriving from `Part.Size` as the whole workflow.** Correct for cylindrical
limbs and wrong for most of what makes a model interesting (4.4). It is the
default, not the policy.
*Test that catches it: is the part square to its own axes?*

**Making the primitive smarter instead of using more of them.** A curved horn
does not want a cleverer capsule; it wants three (3.6).
*Test that catches it: could two more capsules fix this for less effort than a new shape?*

---

## Part 10 — Current State

**Status:** as of 2026-08-20.

| Piece | State |
|---|---|
| `SpatialComponent` — anchor, radius, halfHeight, ring buffer | **BUILT** |
| `SpatialComponent:endpoints` — the capsule | **BUILT** |
| `SpatialComponent.capsuleFromSize` — the derivation | **BUILT**, and has **zero callers**, including in tests |
| One capsule per entity | **BUILT** — a placeholder, and already too fat on a player |
| `HurtboxComponent`, the hitzone list | **UNBUILT** |
| Per-limb history | **UNBUILT**, and blocked on Part 8's test |
| `shape` overrides — `BOX`, `SPHERE` | **UNBUILT** |
| `partId` on `AttackContext` | **UNBUILT** |
| `DebugHurtboxes` overlay | **BUILT**, welded, on by default |
| Any hand-authored `HB_` part | **none yet** — no rigged model exists |

**The thing worth noticing about this table:** the shape decisions are settled
and almost none of them are built. That is deliberate, and it is why a
challenge to the design costs nothing right now and would cost a migration
later.

**Next physical step:** run Part 8's test. It is five minutes, needs no
uploaded assets, and decides the size of the next component.
