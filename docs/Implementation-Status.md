# Implementation Status

What exists, what is proven, and what is not. **Scan the tables — nothing here
needs reading start to finish.**

Last updated: **2026-08-15**. Suite at that point: **197 passed, 0 failed.**

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
| Overlap (sphere/box/arc/capsule) | **VERIFIED** | 11 | Pure math, plus live arc behaviour hand-checked (below) |
| HitVolume | TESTED | 7 | Defaults, validation, reach per shape |
| TargetResolution | **VERIFIED** | 9 | Five stages, dedup, caps, plus a live swing checked by hand |
| Event / Registry / Schema | TESTED | 36 | Schema parse, required/forbidden fields, unknown-key rejection |
| EventTape / Builder | TESTED | 20 | Fluent build, serialize round trip, tape batching |
| EventRouter | **VERIFIED** | 22 | Routing, rate limit, oversized-tape drop, unroutable rejection — plus a real client event routed live |
| Boot (manifest, loader, validation) | TESTED | 17 | Two-way manifest check, layer ordering, effect coverage |
| EntityService | BUILT | — | register / get / count / deleteEntity. Exercised live by the spawner and by player join |
| InputSystem | **VERIFIED** | — | Click → event → wire, matched by event id on both ends |
| DamageResolution | STUB | — | Pipeline builds; steps are TODOs |
| SkillService | STUB | — | `activate` returns NOT_IMPLEMENTED |
| AIService | STUB | — | Scheduler row exists, no decisions |
| Animation | ABSENT | — | No architecture yet. Next up |
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

---

## Open questions, each with a trigger

| Question | Why it is parked | What answers it |
|---|---|---|
| Is `GetNetworkPing()` a round trip or one way? | Localhost reads 0.0000, so the ratio is meaningless. `PING_TO_ROUND_TRIP` stays at 2, the over-rewinding guess | Run PingProbe (`ENABLED = true`) in a Team Test or published place |
| Is `MAX_REWIND = 0.5` right? | Already 2× the shooter norm; no player data to tune against | Ping distribution from real sessions |
| Does the broadphase need spatial partitioning? | ~100 entities is microseconds of linear scan | It appearing in a profile, or attached count passing ~500 |
| Does single-target need a distance sort? | With `maxTargets = 1` and no client hint, the pick is arbitrary order | The first real single-target skill |

---

## Instruments still on disk

| Tool | State | Use |
|---|---|---|
| `diagnostics/SwingReport.luau` | Present, uncalled | Require it in CombatService and call `report(player, event, query, hits)` for a per-swing breakdown |
| `diagnostics/PingProbe.server.luau` | Present, `ENABLED = false` | Turn on inside Team Test to settle the ping question |
| `diagnostics/DummySpawner.luau` | Called from `Main.server.luau` | Ten anchored dummies. Delete when ZoneService spawns real encounters |

Known traps and stale docs live in `DocDebt.md`.
