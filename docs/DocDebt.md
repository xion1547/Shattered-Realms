# Doc Debt

Known-stale spots in the design docs, recorded instead of fixed so doc churn
does not chase code that is still moving. Pruned whenever a doc pass happens.

**Rule for entries:** each one says what is wrong *and* what it should say.
An entry that would need re-deriving before it could be acted on is not
detailed enough — fix the entry, not just the doc.

Last swept: **2026-08-23** — a full pass over the nine core documents against
the hurtbox rebuild. What that pass found, and the lesson worth keeping:

> **The most dangerous stale text is not a doc that is out of date. It is a
> doc that names fields the code no longer has, or a comment that explains
> away the exact symptom its own diagnostic exists to surface.** Both were
> found on this pass, and both are recorded below rather than only fixed.

`Implementation-Status.md` is the companion to this file: that one says what
works, this one says what the docs get wrong about it. The status doc goes
stale fastest of anything here — its test counts and its "not proven" list are
both true only of the day they were written.

---

## HitDetection.md

**Swept 2026-08-23.** The Part 13 File Map, Part 14 Current State, Part 7's
header, 7.1, 7.5, and Part 15's first gap were all corrected in place — they
described the pre-rebuild code. Remaining known-stale rows:

| Where | Stale | Should say |
|---|---|---|
| Part 13 File Map | `resolution/TargetResolution.luau`, `resolution/TargetQuery.luau`, status UNBUILT | both live under `resolution/targeting/` now, and both are **BUILT** |
| Part 13 prose | "`tests/SpatialTests.luau` holds 24 cases" | the suite is **206 passing**; `tests/targeting/` adds cases across four files. This row goes stale every session and should probably just point at `Implementation-Status.md` instead of carrying a number |
| Part 13 File Map | missing several files | `diagnostics/SwingReport.luau`, `diagnostics/HurtboxDebug.luau`, `diagnostics/DebugConfig.luau`, `diagnostics/DummySpawner.luau` (a module called from `Main.server.luau`, **not** a Script — see the fragility note below), and `client/systems/InputSystem.luau` |
| Part 13 File Map | `CombatService` listed as owing the DETECT phase | DETECT is **BUILT** and verified live; what it still owes is the RESOLVE/COMMIT/ANNOUNCE loop over the hits |
| Part 13 prose | PingProbe described as deletable | it is in `_toDelete/` and **cannot run** — Rojo does not sync that folder. The round-trip-vs-one-way sub-question is still open and this was its only instrument, so restoring it from git is the move if that question ever matters |

### Already edited, awaiting review

§5's buffer section and §6's constants table were rewritten on 2026-08-14 for
the `HISTORY_SECONDS` / `MAX_REWIND` split. Left in rather than reverted,
because reverting would leave the doc describing a buffer length the code no
longer has — actively wrong beats out of date. Worth a read on the next pass.

### Not written down anywhere yet

**`SAMPLE_HZ` is a belief, not a control.** `SpatialService:tick` records
whenever it is called, so the constant does not set the rate — it only sizes
the buffer. The real rate is the Scheduler's row, which is a *second copy* of
the number in `Scheduler.luau`.

If those two disagree, neither existing assert fires: both compare sample
**counts**, and this failure is about **duration**. The buffer ends up
spanning less wall-clock time than `MAX_REWIND` reaches, `poseAt` clamps to
its oldest sample, and every rewound query resolves against the wrong moment
with nothing in a log to say so. Same family as the `PING_TO_ROUND_TRIP` unit
bug.

Only the *fast* direction is dangerous — sampling slower makes each sample
cover more time, so the buffer spans more, never less. A loaded server is not
the risk; a changed Scheduler row is.

Guarded now by `SpatialService:verifySampleRate`, a one-shot check of the
observed span against `MAX_REWIND` once a buffer has filled. §5 should
explain the belief-vs-control distinction, and §12 should carry the gap.

**The split's justification is narrower than it looks.** Storing more than is
reachable does *not* protect against someone raising `MAX_REWIND` — the old
coupled form auto-derived the length and the `attach` assert caught the
mismatch loudly. What it actually buys is headroom against the rate
divergence above: tolerance for the real tick rate went from ≤34Hz to ≤94Hz.
The boot assert exists to close a hazard the split itself introduced. Net
positive, but §5 should not claim more than that.

---

## Architecture-Reference.md

Nothing known stale. Swept 2026-08-14 against the `XComponent` rename and the
removed entity-level `getId()` — every `entity.identity:getId()` reference in
the doc is still the correct path, and the Identity-vs-Entity passage reads
correctly post-rename.

Part 8's Multi-Hit section is now the canonical home of the
`hitsPerTarget` / `maxTargets` / `samples` / `chainJumps` naming decision
(2026-08-14). `hitCount` was renamed to `hitsPerTarget` throughout this doc
and in Client-Architecture.md — 12 sites, doc-only, no code carried the old
name yet.

---

## HitDetection.md — two additions owed

§7 defines `samples` without saying what it is *not*. It is now one of four
numbers that get called "hits" in conversation, and it is the only one that
does not reach content data. It should point at Architecture Part 8's table
rather than restating it.

Same for `maxTargets`: HitDetection describes what it does mechanically,
Part 8 now describes how it differs from the other three. A cross-reference
in both directions, not a copy.

§4's description of `attach`/`detach` assumes the reader knows the attached
set doubles as the target set. It should say plainly that **the watch list is
the target list** — that one sentence is what makes "forgetting to detach
leaves a hittable ghost" obvious instead of surprising. Architecture Part 7's
new "Two Existences" subsection now carries the Lua-vs-Instance half; this doc
needs the SpatialService half.

---

## A CODE comment that is actively misleading — not doc debt, a trap

`EventRouter.luau` (~line 145) says `receivedAt` is forwarded because
swallowing it "left the latency rewind with nothing to rewind against". A
reader takes that as an instruction to pass it to `SpatialService`.

**It cannot be used that way.** `receivedAt` is stamped with `os.clock()`
(~line 230); every timestamp in the spatial ring buffer comes from
`workspace:GetServerTimeNow()`. Unrelated origins. Subtracting a rewind
window from one and looking it up in the other lands far outside the buffer,
`poseAt` clamps to its oldest sample, and every hit resolves against a
position from seconds ago — silently, with nothing in a log.

`CombatService:OnAttack` names the parameter `_receivedAt` and carries the
explanation, so the next reader hits it before the bug. Two real fixes, both
larger than a comment:

1. Stamp `receivedAt` with `GetServerTimeNow()`. It is monotonic enough for
   the ordering job it currently does, and it would make the parameter mean
   what its comment claims. Touches a working subsystem, so not done blind.
2. Leave it as `os.clock()` and rewrite the comment to say **ordering only**.

Until one of those happens, DETECT uses `viewTimeFor(player)` with the
current server time and under-compensates by at most one frame.

---

## A latent test fragility, found the hard way

`TargetResolutionTests` resolves volumes against **live `SpatialService`
state** and asserts on total hit counts (`#hits == 1`). It only ever cleans up
what it spawned, so anything else attached at that moment silently joins the
result set.

`DummySpawner` triggered this as a Script — Roblox does not order independent
Scripts, so on some runs ten dummies were attached before `RunTests` ran, and
a 20-stud sphere at the origin caught six of them. The symptom was
`expected: 1, actual: 7` in a **dedup** test with nothing wrong with dedup,
and it passed or failed depending on start order.

Fixed by ordering — the spawner is a module now, called from
`Main.server.luau` after boot. **The fragility itself is untouched.** The
robust fix is for those tests to pass a `filter` predicate matching their own
`TEST_` ids, so the assertions hold no matter what else is in the world.
About nine cases to update; deferred because ordering unblocks it and the
filter mechanism already exists for exactly this kind of scoping.

---

## Client-Architecture.md

The Damage Number System reads `event.hitsPerTarget` as of the rename above.
Nothing else known stale — not swept in full.

### Not written down anywhere yet — how an entityId becomes an Instance

**The client is handed ids and needs objects, and no document says how the
conversion happens.** §6.2's own Presenter example calls
`VFX.playHit(event.targetId, …)` and `Telegraph.show(event.entityId, …)`.
Both take an id. Both must end up touching a Model in `Workspace`. The step
between them exists in no doc and in no code.

`Timeline.md` now owes it too — Part 9.3 plays timelines on an entity's own
body, which needs the same lookup. Effect prefabs escape it, because the
client clones those itself and holds the reference directly (Part 8.1).

**What it should say:** the server sets an `entityId` **attribute** on the
model when it spawns it, and the client keeps one `entityId → Instance` map
maintained by whatever handles entities appearing and leaving. An attribute
rather than the instance name, because names are not unique and get changed
for cosmetic reasons. One shared map rather than each playback module
searching `Workspace`, because every one of them needs the same answer.

**The trap that makes this urgent rather than tidy:**
`diagnostics/DummySpawner.luau` already does `part.Name = tostring(id)`, and
its own comment says that is for reading the Explorer, not for lookup. Any
client code written today can find entities by name and appear to work — until
a spawner names something differently, at which point playback silently
targets nothing. This is a decision, not a discovery; make it before the first
playback module ships.

---

## Resolved on 2026-08-23 — do not re-derive

**`Hurtboxes.md` was swept in full and was the worst offender in the repo.**
Written 2026-08-20 against code that was replaced two days later, it defined a
hurtbox as `spatial.anchor` + `spatial.radius` + `spatial.halfHeight` with
`SpatialComponent:endpoints(cf)` — **four names that no longer exist**. It also
carried a Part whose status was "blocked on a test" the `LimbProbe` had already
answered, and closed with *"next physical step: run Part 8's test."*

**Naming deleted fields is a distinct failure from being out of date**, and it
is the one worth recognising: a doc that is merely behind describes something
real, just older. A doc naming removed identifiers sends a reader hunting for
code that is not there, and they will assume they are the ones who are lost.

Its Part 7 also *argued for* the design that was reversed — per-limb history in
`HurtboxComponent` rather than keyed into `SpatialComponent`. Both positions are
now kept in 7.4 with the argument that beat it (compare the bookkeeping;
`PetRoster` → `Equipment`), per `WorkingAgreement.md`'s corollary.

**Also corrected in the same pass:** `AssetPipeline.md`'s closing line ("the
group does not exist yet"), `Architecture-Reference.md`'s component registry
(`Spatial` still listed as holding a hurtbox radius, `Hurtbox` absent
entirely), and `Implementation-Status.md`'s claim that `SwingReport` was
present-but-uncalled.

---

## Resolved on 2026-08-16 — do not re-derive

**`HitDetection.md` §7 was rewritten twice in one session** and now says
hurtboxes are the model's own parts (oriented boxes), not spheres. Both earlier
positions are preserved in §7.0 with the argument that collapsed. **The
separating-axis cost argument against boxes was wrong** — the ring buffer
stores CFrames, so rewinding a box is free. Do not resurrect it.

**`docs/AssetPipeline.md` was created** and owns the DataModel / replication /
cloud-asset / Rojo vocabulary. `Animation.md` and `HitDetection.md` §7 both
depend on it. The five-round confusion about "does a model live on the server
or in the workspace" is Part 1 of that document; it is settled and should not
be re-argued.

**`docs/Animation.md` was rewritten in full** in Architecture-Reference style —
17 Parts, rejected designs, open questions. Supersedes the shorter version
written earlier the same day.

---

## Animation — two files that disagree with the doc

Two pieces of code predate `Animation.md` and conflict; neither is
load-bearing, both are referenced only by tests.

| File | Problem | Should be |
|---|---|---|
| `shared/eventTape/event/animation/AnimationRegistry.luau` | Content-Layer data filed under the transport layer, with two placeholder ids | `shared/definitions/AnimationManifest.luau`, with `priority` / `fadeTime` / `loadFor` per row |
| `shared/eventTape/event/types/AnimationEvent.luau` | `withId` + `withSpeed` + `withLooped` is the "play animation X at rate Y" command shape that Client-Architecture's PLAYBACK section and `Animation.md`'s rejected-designs table both reject | Either deleted, or reshaped once a real case appears for one client rendering another entity's action — and the doc's answer for that is a COMBAT/SKILL fact carrying `skillId` + `serverTime`, not an animation id on the wire |

Its own header already says animation is a client rendering concern and that
`ANIMATION` is correctly absent from `EventRoutingRegistry`. The file agrees
with the design in prose and disagrees with it in its schema.

**Do not delete either until the manifest and client player exist** — the
EventTape tests use `AnimationEvent` as their round-trip fixture, so removing
it drops real coverage of an unrelated system. Replace the fixture first.

### ~~Not a doc problem, a decision that blocks work~~ — CLOSED

**The animation asset owner was chosen on 2026-08-16 (a GROUP), and the group
was created on 2026-08-22 with the experience transferred to it.** Nothing is
blocked. `AssetPipeline.md` Part 9 and `NextSteps.md` item 2 both say so now;
this entry stood stale through both halves of the decision.

**Every upload from here goes under the group, meshes included.** The cost of
getting that wrong is not a setting to change later — a personal-account asset
does not transfer, it gets re-uploaded, and every id referencing one changes.

---

## Spatial vs Hurtbox — settled, and now written down

**Decided 2026-08-22 in conversation. WRITTEN 2026-08-23** into
`Architecture-Reference.md` Part 7's component registry, `Hurtboxes.md` Part 7
(including the reversed half, 7.4), and both component headers. Kept here as
the compressed version, and because the *reasoning* is the reusable part.

The question was whether per-limb position history should be a child component
of `SpatialComponent`, since `SpatialComponent` was conceived as "the entity as
a whole" and its header still says so.

**Answer: it collapses into `SpatialComponent`, keyed by part.** The reasoning
is the `PetRoster` → `Equipment` precedent in Architecture Part 7: *compare the
bookkeeping.* A per-limb ring buffer needs a preallocated ring that never
grows, ordered samples, interpolated lookup by timestamp, and clearing on
rebind — **which is `SpatialComponent` exactly, with an explicit key instead of
an implicit one.** A child would duplicate every one of those invariants.

It also gets the lifecycle for free rather than by wiring: one `clearHistory`
clears every ring, one `setAnchor` rebuilds them all, and there is no teardown
to keep in sync because there is one owner.

**The distinction that should be stated explicitly in both files' headers, and
currently is not:**

| | `HurtboxComponent` | `SpatialComponent` |
|---|---|---|
| Holds | **shape** — a capsule of radius r, offset from a named limb | **position over time** — where that limb was, at t |
| True | regardless of where the body is, or when | only at a specific moment |
| Written | once, at attach, then frozen | 30 times a second, forever |

> **The test that separates them: does it change while the game runs?** Shape
> does not. Position does.

That is also why `endpoints(index, pose)` takes the pose as a parameter rather
than reading it — the hurtbox deliberately has no position, which is exactly
what makes it rewindable.

**Rejected in the same conversation: grouping capsules under a "limb" layer.**
The case that looked like it would demand one was Monster Hunter-style
breakable parts — "this horn is broken" being a property of a limb rather than
of one capsule. It does not demand one: breaking a horn is *shrink or remove
the capsules and swap the model*, which the flat list already expresses. Add a
limb layer only if something needs per-limb state that capsules cannot carry.

**Done 2026-08-23:** `HitDetection.md` Part 4 carried the old shape
("`radius`, `halfHeight` — the capsule") and an `attach(entity, anchor, radius,
halfHeight)` signature that no longer exists. Both corrected, and the Part now
carries the shape-vs-position split plus the two invariants that were only in
code comments — one shared timeline across tracked parts, and why the anchor's
poses stay a plain field rather than a map entry.


---

## The Studio command bar runs as the CLIENT during a play test

**Cost an evening on 2026-08-22.** Every `Debug*` flag is a Workspace
attribute, and the documented way to flip one mid-session is:

    workspace:SetAttribute("DebugSwingReport", true)

Typed into the command bar during a play test, **that sets it on the CLIENT's
DataModel.** Attributes do not replicate upward, so the server never sees it and
the flag stays off — silently, with the command reporting success and the
diagnostic looking broken.

**The fix: switch the command bar to Server context** (the dropdown beside it),
or select `Workspace` in the Explorer while running and edit the attribute in
the Properties panel.

`DebugConfig`'s boot hint now names the Server context explicitly. **Amended.**

---

## Two comments that explained away their own diagnostic — FIXED 2026-08-23

**The same family as the `EventRouter` trap above, and worse in one specific
way: these were the documentation of a debugging tool, telling a reader that
the symptom the tool exists to surface was working as designed.**

`DebugConfig.luau`'s `HurtboxLog` entry and `HurtboxDebug.luau`'s logging
header both said:

> *"REL ROOT stays fixed → zones are anchored to the root ... Limbs animating
> do not move them, and that is not a bug."*

That was true for about six hours on 2026-08-22, under the root-anchored design
that was built and reversed the same day. Zones ride their own limbs now, so a
zone whose rel-root drift stays `0.00` through an animation **is** a bug — it
fell back to the root, which means its limb name is not on that rig.

Anyone debugging a genuinely broken anchor would have read that comment and
stopped looking. `Implementation-Status.md` said the opposite and was correct;
the two disagreed for a day.

*The lesson, and it generalises past this instance:* **when a design is
reversed, grep the diagnostics for it before grepping the docs.** A stale
design doc misleads someone reading about the system. A stale diagnostic
comment misleads someone actively debugging it, at the moment they are most
likely to trust it.

---

## A comment asserting a safety property the code does not have — FIXED 2026-08-23

`HurtboxDefinitions.luau` claimed that a client's ability to displace its own
hurtbox zones was:

> *"Bounded rather than banned (HitDetection 7.4) by a clamp on how far a zone
> may sit from the root."*

**There is no such clamp.** Not in that file, not in `HurtboxComponent`, not in
`SpatialService`, not anywhere — `grep -rn "clamp" src/` finds only floating
point guards in `Overlap` and unrelated resource clamping. HitDetection 7.4 says
"a bound, not a ban" as a *design position*; nothing implemented it.

The comment has been replaced with what is actually true (the displacement is
accepted, not bounded), why that is acceptable today (an arm capsule is radius
0.28, on the defensive side, where "defense is generous" already errs the
player's way), and the trigger that would make it worth building.

*The lesson:* **a comment asserting a security or safety property is a claim
about code, and claims about code get grepped.** This one had never been —
which is exactly how it survived. Worse than an absent comment, because it
stops the next person from checking too.
