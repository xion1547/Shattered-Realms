# Implementation Status

What exists, what is proven, and what is not. **Scan the tables — nothing here
needs reading start to finish.**

Last updated: **2026-08-22**. Suite: **206 passed, 0 failed.**

> **The hurtbox rebuild is DONE.** Ten limb-anchored zones per player, per-zone
> history, resolution testing them, the single capsule deleted. Verified live.
> What is left in this layer is the attack-definition restructure — `NextSteps.md`.

> **What to build next lives in `NextSteps.md`**, with the reasoning behind the
> ordering. This file is only what exists and what is proven.

---

## Status words, and what each one is worth

| Word | Means |
|---|---|
| **VERIFIED** | Automated tests **and** a live run whose numbers were checked by hand against expected values |
| **TESTED** | Automated tests pass; never exercised in a running game |
| **BUILT** | Code exists and boots; no dedicated tests |
| **STUB** | Signature exists, body is a TODO. Boots, does nothing |
| **ABSENT** | Designed in a doc, not written |

The gap between TESTED and VERIFIED is the one that matters. A unit test proves
a function does what its author expected; it cannot prove the function is
wired to anything. Everything below marked TESTED could be dead code.

---

## Systems

| System | Status | Tests | Evidence |
|---|---|---|---|
| Signal | TESTED | 12 | Fire, connect, disconnect, destroy, listener errors isolated |
| SignalService | TESTED | 14 | Declare/subscribe vocabulary, boot validation, unknown-name rejection |
| Components | TESTED | 24 | Every component's invariants |
| Spatial (component + service) | **VERIFIED** | 25 | Ring buffer wrap, interpolation, rewind arithmetic — plus live: buffer spanning 1.55s, rewound positions matching live on static targets |
| Overlap — **volume shapes** | **VERIFIED** | 11 | Pure math, plus live arc behaviour hand-checked (below) |
| Overlap — **target shape** | **BUILT** | — | Resolution tests the zone list. The single capsule is deleted; a body with no hurtbox is not hittable, asserted at attach |
| `HurtboxComponent` + `HurtboxDefinitions` | **VERIFIED** | — | Ten limb-anchored zones per player, one per dummy. Drawn, looked at, and confirmed to follow the pose. Resolution tests them |
| Per-zone position history | **BUILT** | 25 | `SpatialComponent` keys rings by `BasePart`. One shared timeline and cursor, one pose array per part |
| Sweep (`sweep` field, travelling blade) | **VERIFIED** | — | 140° over 0.35s in 8 samples. Live-checked: the same swing caught targets on samples 6–8 with 1–5 empty, and on another swing 1–4 with 5–8 empty — **a static fan cannot produce that.** Dedup across the swing confirmed ("2 in volume, 1 new") |
| Stopwatch driver (`CombatService:tick`) | **VERIFIED** | — | Samples fire ~50ms apart at 60Hz; every sample is evaluated at its own moment and rewound normally, so the whole window stays in history — §8.2 |
| Enemy-attack sweeps | **REMOVED 2026-08-21** | — | `EnemyAttackDemo` is in `_toDelete/`. Enemies still spawn and are hittable; they no longer swing. Giving them attacks on the old `SWEEP` model would mean building it twice — they come back after `motion = PATH` |
| Attack cooldowns | **ABSENT — placeholder in place** | — | `_hasSweepInFlight` rejects a second swing from the same attacker. Stops key-spam stacking overlapping blades, each with its own dedup set. `SkillService:isReady` exists and nothing calls it; this belongs in VALIDATE as a real recovery time |
| HitVolume | TESTED | 7 | Defaults, validation, reach per shape |
| TargetResolution | **VERIFIED** | 9 | Five stages, dedup, caps, live swings hand-checked. Now tests the zone list, each zone rewound through its own limb |
| Event / Registry / Schema | TESTED | 36 | Schema parse, required/forbidden fields, unknown-key rejection |
| EventTape / Builder | TESTED | 20 | Fluent build, serialize round trip, tape batching |
| EventRouter | **VERIFIED** | 22 | Routing, rate limit, oversized-tape drop, unroutable rejection — plus a real client event routed live |
| Boot (manifest, loader, validation) | TESTED | 17 | Two-way manifest check, layer ordering, effect coverage |
| EntityService | BUILT | — | register / get / count / deleteEntity. Exercised live by the spawner and by player join |
| InputSystem | **VERIFIED** | — | Click → event → wire, matched by event id on both ends |
| DamageResolution | STUB | — | Pipeline builds; steps are TODOs |
| SkillService | STUB | — | `activate` returns NOT_IMPLEMENTED |
| AIService | STUB | — | Scheduler row exists, no decisions |
| Animation | ABSENT | — | Architecture written (`Animation.md`). **No longer blocked** — the group exists and the experience was transferred to it on 2026-08-22. Next: author one clip, publish, register, play |
| Timeline (non-rig property animation) | ABSENT | — | Engine **and** dev-only editor both designed (`Timeline.md`, rev. 2026-08-19); no code. Prototype planned as the first step of animation work — Part 13 |
| Boss HFSM | ABSENT | — | Designed in `BossAI-HFSM.md` |

---

## The live proof, 2026-08-15

One swing, hand-checked rather than assumed. Attacker at `(-11.9, 4.7)` facing
`(-1.0, -0.1)`; volume ARC, radius 12, 120° (±60°).

| Dummy | Position | Distance | Angle off facing | Result |
|---|---|---|---|---|
| ENEMY_4 | (−9, 10) | **6.0** | ~124° | **missed** |
| ENEMY_3 | (−15, 10) | 6.1 | ~65°, → ~41° after hurtbox width | hit |
| ENEMY_2 | (−21, 10) | **10.5** | ~36° | **hit** |

**The nearest target was missed and one nearly twice as far was hit.** No
distance check produces that ordering — only a real angular test does. This is
the single most convincing line in this document.

ENEMY_3 is the subtle case: its centre sits *outside* the 60° cone and it is
included only because its 2.5-stud hurtbox subtends `asin(2.5 / 6.14) ≈ 24°`.
That is the angular-half-width subtraction in `Overlap.arc`, which is the step
naive implementations skip.

Also confirmed in the same run:

| Reading | Value | What it proves |
|---|---|---|
| `rewind` | 0.1002s | The ping term is small but **non-zero** and flowing through — the whole arithmetic chain, not just the constant |
| `broadphase` | 10 of 11, 8 of 11 | The cull rejects; it is not passing everything through |
| buffer span vs rewind | 1.55s vs 0.10s | 15× headroom. `poseAt` is not clamping |
| `preferred` | sorted first, both swings | The client's hint reorders without adding — in one swing it put a farther target ahead of a nearer one |
| event id | identical client and server | The wire, specifically |

---

## Hit detection — the live test, 2026-08-16

**Verdict: the detection layer works.** Below is exactly what was exercised and
exactly what it proves, because "it seemed fine" is not a record anyone can
act on in six months.

### What was tested

| # | Test | What it proves |
|---|---|---|
| 1 | **Vertical discrimination.** Jumped so the attack volume sat above the target's hurtbox. It missed | The capsule's **height** participates. A system comparing horizontal distance only would have hit — this is the single cheapest proof that hurtboxes are 3D volumes and not circles on a map |
| 2 | **Angular discrimination.** An earlier swing missed a dummy at 6.0 studs and hit one at 10.5 | Only a real angular test produces that ordering. No distance check can |
| 3 | **The angular half-width term.** A dummy whose centre sat outside the cone was hit because its body reached in | `asin(radius / distance)` is applied. This is the step naive implementations skip |
| 4 | **Three volume shapes, three keybinds.** ARC, BOX (offset forward), CAPSULE, each catching a visibly different set from the same standing position | The shapes are genuinely different maths, not one shape wearing three names |
| 5 | **`offset` is applied.** The BOX cleave resolved four studs forward of the attacker | Caught a real bug — `offset` was declared, validated and reach-accounted since `HitVolume` was written, and silently ignored by `Overlap` |
| 6 | **Dedup across a swing.** `2 in volume, 1 new` on consecutive samples | A body the blade passes through repeatedly is counted once (§8.0) |
| 7 | **Directional sweeps.** One swing caught targets on samples 6–8 with 1–5 empty; another on 1–4 with 5–8 empty | The blade genuinely travels. A static fan tests the same geometry every time and can only return the same answer |
| 8 | **Enemy → player.** Ten dummies swinging on a timer, damage applied, HP pushed to the client | The other direction of combat resolves, and `at = now` with no rewind behaves |
| 9 | **The outbound wire.** Server and client HP agreed on every single push across dozens of hits, including death and reset | The push path is sound end to end |
| 10 | **Concurrent-attacker stacking.** Three enemies landing within one millisecond took 60 HP | Not a bug — correct independent resolution. It surfaced a **missing gameplay rule**: no invulnerability window |

### Measured, not assumed

| Reading | Value |
|---|---|
| Server → client push latency, Play Solo | consistently **31–33ms** — about two replication ticks, and the floor with zero network |
| Buffer span vs rewind window | 1.55s vs 0.10s — 15× headroom, `poseAt` never clamped |
| Broadphase cull | rejected 3–4 of 11 attached on typical swings; not passing everything through |

### What this does NOT prove

- **Nothing was tested with two players, or with real latency.** Every reading
  is a solo localhost session where ping reads 0.0000. The rewind arithmetic
  *runs* and is *harmless*; it has never been shown *correct*.
- **Nothing was tested against a moving target.** Every dummy is anchored, so
  the rewound position always equalled the live one. `drift 0.00` on every
  line of every trace.
- **The wedge rewrite (§8.3) is UNTESTED, and its first run was broken.** The
  verified session above ran the discrete-sample build (its logs read
  `sample 8/8`). The first wedge build shipped with a dangling `fraction`
  reference left over from the rename — every sweep threw on its first wedge,
  and because the counter advanced *after* the evaluation, the swing retried
  the same wedge sixty times a second forever. The attacker never cleared
  `_hasSweepInFlight`, so every subsequent attack was refused
  `SWING_IN_PROGRESS`. Fixed, plus the counter now advances first so a failing
  wedge is skipped rather than repeated. **Still not played.**

  Two lessons kept because both cost real time: a `pcall` that swallows an
  error still needs to say *where* it came from — `[Scheduler] tick failed`
  named none of five scheduled services — and any retry loop must advance its
  counter before doing the work that can fail.
- **Nothing takes real damage.** The 20-per-hit HP is a diagnostic's own
  number, not `.resources["HP"]`. `DamageResolution` is still a stub.

---

## What is NOT proven, and should not be assumed

- **Nothing takes damage.** DETECT finds bodies; `resolveAttack` is never
  called. RESOLVE, COMMIT and ANNOUNCE are all unwritten.
- **Nothing has been tested with two players**, or with real latency. Every
  reading above is a solo localhost session where ping is ~0.
- **Nothing has been tested with a moving target.** Every dummy is anchored, so
  the rewound position always equalled the live one. Rewind is *running* and
  *harmless*; it has never been shown to be *correct* on something in motion.
- **No enemy has ever attacked.** The enemy-side path (`at = now`, telegraph as
  the compensation) has tests but no live run.
- **Nothing persists.** DataService is a stub.
- ~~**Hurtboxes are a known-wrong placeholder.**~~ **CLOSED 2026-08-22.** Ten
  limb-anchored zones per player, per-zone history, resolution testing them,
  the single capsule deleted.

---

## The hurtbox rebuild, 2026-08-22

Four commits, and two bugs only a live run could have found.

| | |
|---|---|
| Per-zone history | `SpatialComponent` keys rings by `BasePart`. **One shared timeline and cursor, N pose arrays** — every part is sampled on the same tick, so per-part counters would be numbers that must never diverge |
| Zones ride their own limb | `anchor` is a part NAME resolved per body in `bind`, re-resolved on every respawn. A missing part falls back to the root and warns |
| Resolution loops zones | returns on the first zone that connects; dedup would discard the rest anyway |
| The single capsule | deleted, with `capsuleFromSize` (zero callers since written, and in the wrong file regardless) |

### Two bugs the live run caught and nothing else would have

**`boundingRadius` measured the wrong distance.** A zone's offset is relative
to ITS LIMB, so summing offset + halfHeight + radius answered *"how far does
this capsule reach from its own arm"* — **1.45 studs** for a player, when the
real reach from the root is ~3.3. The broadphase culls **from the root**, so the
cull was tight. It never surfaced because the volume's own reach (7.5)
dominated the sum, so nothing near the edge of range had been tested.

Now measured in `bind` as (limb from root) + (zone from limb), padded 2×
because that is a rest-pose reading and limbs move. Reads **6.67** now.

**`idsOf` was a local declared after its first use**, so the instantaneous path
threw `attempt to call a nil value` the first time anyone pressed the AOE key.
Pre-existing, on a path nothing had exercised.

### And a design that was built, drawn, and reversed

Zones hanging off the body's **root** produced a rigid arrangement of capsules
ignoring the pose — a mannequin riding the player. The reasoning was that a
client-animated limb reaches the server ~0.104s stale, worth 4.7 studs at full
swing speed. Real number, wrong one to design around:

| Limb doing | Error | Arm capsule radius |
|---|---|---|
| walking | **0.30 studs** | **0.28** |
| mid-swing | 4.68 studs | 0.28 |

At the speeds a body spends nearly all its time at, the error is **under the
capsule's own thickness.** *The test that catches it is: draw it and look.* It
survived an hour of argument and died the instant it was rendered.

---

## Open questions, each with a trigger

| Question | Why it is parked | What answers it |
|---|---|---|
| ~~Does a server script see a client-animated limb move?~~ | **CLOSED 2026-08-21.** Yes — trailing by ~0.104s, which is `INTERPOLATION_CONSTANT` behaving exactly as specified. Measured by `LimbProbe`, since retired | — |
| ~~Derive hurtboxes from part sizes, or hand-place them?~~ | **CLOSED 2026-08-22.** Both, per body. Players are typed in `HurtboxDefinitions` because they wear a stock rig; bosses get parts placed by eye and read at spawn | — |
| Is `GetNetworkPing()` a round trip or one way? | The **unit** is settled (seconds, measured). The ratio is not, and is low-stakes: ~12ms against a 0.1s constant. `PING_TO_ROUND_TRIP` stays at 2, the over-rewinding guess | A playtest above ~200ms ping that feels wrong |
| Does `MAX_ENTITY_SPEED = 120` need raising? | Nothing in the world moves near it. **A boss that flies faster gets silently culled from its own hit test** | The first fast boss. `NextSteps.md` |
| Is `MAX_REWIND = 0.5` right? | Already 2× the shooter norm; no player data to tune against | Ping distribution from real sessions |
| Does the broadphase need spatial partitioning? | ~100 entities is microseconds of linear scan | It appearing in a profile, or attached count passing ~500 |
| Does single-target need a distance sort? | With `maxTargets = 1` and no client hint, the pick is arbitrary order | The first real single-target skill |
| Derive hurtboxes from part sizes, or hand-place them in the rig? | **Not a fork** — HitDetection §7.2.3 settles that both routes reduce to an anchor plus two numbers, mixable per hitzone. `capsuleFromSize` exists with **zero callers**, so nothing is committed either way | The first rigged model. Derive the plain limbs, hand-place anything whose `Part.Size` lies, and check both with `DebugHurtboxes` |

---

## Instruments still on disk

| Tool | State | Use |
|---|---|---|
| `diagnostics/SwingReport.luau` | Present, uncalled | Require it in CombatService and call `report(player, event, query, hits)` for a per-swing breakdown |
| `_toDelete/` at the repo root | **retired, outside `src/`** | `LimbProbe`, `PingProbe`, `SweepTrace`, `EnemyAttackDemo`. Rojo does not sync that folder, so none of it can run. Each answered its question and the answer is recorded elsewhere; git has them if any is wanted back |
| `diagnostics/DummySpawner.luau` | Called from `Main.server.luau` | Ten anchored dummies. Delete when ZoneService spawns real encounters |
| `diagnostics/HurtboxDebug.luau` | flag `DebugHurtboxes`, **on** | Draws every zone as a cyan capsule, **welded to its own limb** so it follows the pose and cannot trail the body. **Turn this on for every model-authoring session** — it is the only way to see whether a zone list actually covers a rig |
| ↳ `DebugHurtboxLog` | **off** | Per-zone positions, and which limb each zone resolved to. `rel drift` non-zero while moving means a zone is tracking its limb; `ROOT (unbound)` means that limb name does not exist on this rig and it fell back |
| ↳ `DebugHurtboxServerView` | **off** | Same overlay in amber, drawn from the **server's** copy and teleported instead of welded. The gap it opens behind your character is `2L + I` — the round trip rewind exists to undo. A measurement, not a shape check (HitDetection §7.11) |
| `diagnostics/AttackDebug.luau` | flag `DebugHitboxes`, **on** | Draws the volume the server actually resolved, plus a red marker on everything it caught. Amber for your swings, red for incoming |
| `diagnostics/DebugConfig.luau` | — | **The switchboard.** Every flag above is a Workspace attribute, editable in the Properties panel **while the game runs** |

**The two logs that default on are a pair:** `DebugAttackLog` (one line per
attack you make, and what it caught) and `DebugDamageLog` (one line per hit you
take). Turning off either alone leaves the combat log lying by omission — the
first build of the switchboard shipped with only the second, and combat read as
"everything hits me and nothing I do lands."

**Removed 2026-08-20: `SwordDebug.luau` and `DebugSword`.** A steel blade
welded to every player, sized from `BASIC_SWING` so the model could not drift
from the hitbox. It made its point — the swing volume stopped being a cone and
became a sword-shaped capsule — and then had nothing left to do: it could not
swing, because animating it would have meant authoring the swing animation the
placeholder existed to defer. `AttackDebug` already draws the volume as it
travels, which is the same information from the source of truth.
`CombatService.swingVolume()`, which existed only to feed it, went with it.

### Turning things on and off

Select `Workspace` in the Explorer with the game running and edit the `Debug*`
attributes. No restart, no rebuild. Or from the command bar:

```lua
workspace:SetAttribute("DebugSwingReport", true)
```

**Visuals default on, logs default off.** A coloured volume costs a glance; a
line printed once per wedge costs the whole output window. They are different
kinds of thing and do not share a switch.

Known traps and stale docs live in `DocDebt.md`.
