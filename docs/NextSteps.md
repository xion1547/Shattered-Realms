# Next Steps

### The work queue, with the reasoning behind each item's position

> **Why this document exists.** `Implementation-Status.md` records what is
> built. `HitDetection.md` records what was decided. Neither says **what to do
> next, in what order, and why that order** — which is the thing that
> evaporates between sessions and gets re-derived from scratch.
>
> Every item carries the argument that put it where it is, so the ordering can
> be attacked on its merits rather than trusted because it is written down
> (`WorkingAgreement.md`).
>
> **Revised 2026-08-23.** Items 1 and 3 are done. The queue now runs through
> the animation workflow — see `AnimationWorkflow.md` for the step order.

---

## Where things stand

| | |
|---|---|
| Hurtboxes | **DONE.** Ten limb-anchored zones per player, per-zone history, resolution testing them |
| Attack definitions | **DONE 2026-08-23.** Content walks a folder; `CombatService` holds no volumes |
| The Conductor | **BUILT 2026-08-23**, never run. Property + clip tracks, one transport |
| The authoring tool | **BUILT 2026-08-23**, never run |
| Suite | **206 passed, 0 failed** |
| Blocking everything downstream | **one uploaded animation.** Art time, not code |

---

## 0 — The first clip, end to end

**Status:** the only thing actually blocking. **`AnimationWorkflow.md` is the
step-by-step**; this is why it is first.

Every remaining item is easier to judge once a swing exists on screen, and two
of them cannot be *validated* without one — the Conductor's tandem behaviour and
the tool's clip track both need a real `AnimationTrack` to act on.

**It is art time, not code time.** Build the prefab, author the swing, publish
under the group, paste one id. Nothing in the repo blocks it.

---

## ~~1 — Attack definitions out of `CombatService`~~ — DONE 2026-08-23

**What landed:** `serverShared/definitions/enemies/` and `skills/`, one file
per thing, walked at boot by `boot/DefinitionLoader.luau`. `EnemyTemplates` is
deleted. `CombatService` lost 95 lines and holds no volumes.

**Three decisions inside it worth not re-deriving:**

**Skills are FLAT, not grouped by class.** `skills/Warrior.luau` was built and
reversed the same day. `Gameplay-Design.md`'s mitigation table keys availability
on *weapon weight* (`"parryable only by a heavy weapon"`) **and** on class
(`"only the Mage's redirect"`) — so availability is already many-to-many across
two axes, and a folder encodes exactly one. Every grouping axis fails: by class
breaks on a sword-mage, by weapon on a magic sword, by mechanic on a skill that
parries and redirects. **The id is the only stable key**, and who may use a
skill is a separate list on whatever owns that relationship.

**A volume in a definition is a PLAIN TABLE**, not a `HitVolume.resolve` call.
`serverShared` maps to every place; `HitVolume` exists in one. A require upward
would fail *on load* in the Hub and take the whole definitions tree with it. The
loader resolves them, because the loader is place code.

**Content loads in `ServerManager`, before services boot.** `ServiceLoader`
pcalls each boot and reports `'CombatService': <error>` — loading content there
would name the wrong file for a typo in a definition.

**What is still temporary:** `SKILL_BY_SUBTYPE`, three debug keybinds mapping to
three skill ids. The event will eventually name its own skill and VALIDATE will
check the attacker owns it. That is the skill system, deliberately not built.

---

## ~~3 — The Conductor~~ — BUILT 2026-08-23, NEVER RUN

Four files in `client/playback/conductor/`. `Timeline.md` Part 13 has the
state, Part 12 has the two reversals. The authoring tool is
`client/diagnostics/conductorTool/`, gated on `DebugConductorTool`.

**Validating it is item 0.** Everything about it is argued and unvalidated.


---

## The animation workflow — moved out

**`AnimationWorkflow.md` owns the step order** — build the prefab, animate,
upload, author the effects in the tool, capture the hitbox, write the row. It
did not exist when this queue was written, and two items here were a worse copy
of it.

**One thing worth keeping here, because it lives nowhere else:** Moon Animator
is a tool preference with **no architectural consequence for the rig half** —
its joint export is a normal `KeyframeSequence` that publishes like any other.
Its *property* half is what the Conductor replaces.

---

## 4 — `motion = PATH`, the hitbox side

**Status:** DESIGNED (`HitDetection.md` Part 9), UNBUILT. The Conductor exists
now, so what this waits on is a real swing to record a path off — item 0.

**This is `AnimationWorkflow.md`'s Phase 4.2 gap.** Until the recorder exists, a
skill's volume stays hand-tuned against `DebugHitboxes`, which is the same
authoring-by-looking with a coarser instrument.

The hitbox becomes its own object with its own authored motion — a volume
travelling a path placed by hand in the Conductor, anchored to the attacker's
root, evaluated by the server from local data.

**Two details that are easy to get wrong:**

**Store the pivot, not the blade tip.** Interpolating two *positions* gives a
straight line; a blade travels an arc. Storing the pivot's frame and letting
`CFrame:Lerp` interpolate the rotation spherically makes the arc exact at any
key density. Tip positions work on a dense recording and fail badly on a sparse
hand-authored one — the case nobody would think to check.

**Run the driver at 60Hz, not the sampler's 30Hz.** A blade tip covers ~45
studs/second. Tunneling is impossible while the hitbox moves less than the
smallest hurtbox radius per tick; at 30Hz that is 1.5 studs against a 1.5-radius
body, exactly at the limit. **And the hitzone list makes it worse** — a
0.3-radius limb capsule is narrower than the gap 60Hz leaves.

---

## 5 — Then: give attacks back to the enemies

They currently do not attack at all. `EnemyAttackDemo` is in `_toDelete/`,
removed deliberately so the old `SWEEP` model would not be built twice.

Enemy attacks resolve at `at = now` with **no rewind** — the telegraph windup
*is* the compensation, and rewinding on top of it would retroactively hit a
player who visibly dodged.

---

## Gaps that will bite a fast boss

Neither is urgent. Both are cheap. Both produce symptoms that cannot be
diagnosed from inside the game.

**`MAX_ENTITY_SPEED = 120`** in `TargetResolution` is the broadphase margin. **A
boss that flies faster gets silently culled from its own hit test** — no error,
swings just return nothing, and it looks like broken overlap math.

For scale: default walkspeed is 16 studs/sec, so 120 is **7.5× walking**. Most
bosses will not come near it; a diving flyer might.

**Ping is sampled fresh per swing and never smoothed**, and
`INTERPOLATION_CONSTANT = 0.1s` is borrowed rather than measured. Both convert
into positional error linearly with target speed:

```
error = target speed x timing error

  20 studs/sec, 30ms off  ->  0.6 studs   fine
  60 studs/sec, 30ms off  ->  1.8 studs   eating the margin
 120 studs/sec, 30ms off  ->  3.6 studs   misses a 3-stud body
```

**If something genuinely outruns the rewind, deferring to the client's report
for that case is reasonable** — better than confidently-wrong server geometry.
Noted as an option, not built.

---

## Settled — do not re-argue these

Each consumed real time and reached a conclusion with a reason. Attack them with
a better argument if there is one, but not from scratch.

| Settled | Because |
|---|---|
| **Server-authoritative.** Client-detects-server-validates stays rejected | stated preference, repeatedly. The client-tells-server pattern is disliked outright |
| **Ownership decides the hitbox model.** Server-animated rig → `LIVE`; client-animated → `PATH` | bone-attached colliders require synchronised skeletal animation on both machines. `LimbProbe` measured we do not have it for client rigs (~0.104s) and do for server rigs |
| **Hitboxes are never real parts at test time** | a part only exists *now*, and this layer answers about the past. Recording a part's motion at dev time is fine; testing against one is not |
| **Rewind stays** | dropping it allows Roblox's built-in queries and deletes a lot of code, at the cost of a 120ms player missing shots that visibly connected |
| **Capsules, not exact mesh geometry** | curves do not survive export, and it would make every art change a balance change |
| **Zones ride their own limb, including for players** | the error is `limb speed × 0.104s` — 0.30 studs at walking speed against an arm capsule of radius 0.28, under its own thickness |
| **Per-limb history lives in `SpatialComponent`, not a child** | the `PetRoster` → `Equipment` precedent: same bookkeeping, so it keys in rather than duplicating every invariant |
| **Skills and attacks are one concept** | same shape, different fields populated |

---

## Related

| Document | |
|---|---|
| `WorkingAgreement.md` | how decisions get justified here. **Read before proposing changes** |
| `HitDetection.md` | Part 0 is the orientation. Part 9 is the motion model |
| `Hurtboxes.md` | the authoring manual — studs, `CFrame`, placing a capsule by hand |
| `Animation.md` | clips, upload, ownership, the manifest |
| `Timeline.md` | the Conductor and the Score |
| `Implementation-Status.md` | what is built and what is actually proven |
| `DocDebt.md` | stale spots, code traps, resolved-do-not-re-derive |
