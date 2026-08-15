# Doc Debt

Known-stale spots in the design docs, recorded instead of fixed so doc churn
does not chase code that is still moving. Pruned whenever a doc pass happens.

**Rule for entries:** each one says what is wrong *and* what it should say.
An entry that would need re-deriving before it could be acted on is not
detailed enough — fix the entry, not just the doc.

Last swept: **2026-08-15**

`Implementation-Status.md` is the companion to this file: that one says what
works, this one says what the docs get wrong about it. The status doc goes
stale fastest of anything here — its test counts and its "not proven" list are
both true only of the day they were written.

---

## HitDetection.md

| Where | Stale | Should say |
|---|---|---|
| §11 File Map | `components/Spatial.luau` | `components/SpatialComponent.luau` — from the `XComponent` rename |
| §11 File Map | `resolution/TargetResolution.luau`, `resolution/TargetQuery.luau`, status UNBUILT | both live under `resolution/targeting/` now, and both are **BUILT** |
| §11 File Map | `HitVolume.luau`, `Overlap.luau` status UNBUILT | **BUILT** |
| §11 prose | "`tests/SpatialTests.luau` holds 24 cases" | still 24, but `tests/targeting/` now adds 27 more across four files |
| §11 prose | PingProbe described as deletable | keep it until the round-trip-vs-one-way sub-question in §6 is closed — it is the only instrument for that. It is now `ENABLED = false` by default |
| §11 File Map | missing three files | `diagnostics/SwingReport.luau`, `diagnostics/DummySpawner.luau` (a module called from `Main.server.luau`, **not** a Script — see the fragility note below), and `client/systems/InputSystem.luau` |
| §11 File Map | `CombatService` listed as owing the DETECT phase | DETECT is **BUILT** and verified live; what it still owes is the RESOLVE/COMMIT/ANNOUNCE loop over the hits |

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
