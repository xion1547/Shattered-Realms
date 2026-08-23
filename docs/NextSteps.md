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
> **Revised 2026-08-22.** The hurtbox rebuild is finished; the next phase is
> animation.

---

## Where things stand

**Hit detection is done except for one refactor.**

| | |
|---|---|
| Hurtboxes | **DONE.** Ten limb-anchored zones per player, per-zone history, resolution testing them. Single capsule deleted |
| Suite | **206 passed, 0 failed** |
| Verified live | swings resolve, AOE resolves, zones follow the pose |
| Left in this layer | the attack-definition restructure, item 1 below |

**Animation is the next layer, and everything downstream waits on it.** The
hitbox side of hit detection (`motion = PATH`) cannot be authored without a
Conductor, and a Conductor is animation work.

---

## 1 — Attack definitions out of `CombatService`

**Status:** UNBUILT. Small, independent, and the last hit-detection item.

### The finding that forces it

```lua
[CombatEvent.SubType.MELEE] = BASIC_SWING,
```

**That map is keyed by which button was pressed, not by who is swinging.** A
goblin, a giant, a player with a dagger and a player with a greatsword all
melee with the identical 6.5-stud capsule. The volume *cannot* vary by
attacker — there is no path for it to.

### What is actually wrong

The engine is fine. `HitVolume` already **is** the declarative half — shape
vocabulary, defaults, validation, wedge derivation. **The configuration is
squatting in code.** Three volumes are typed as locals inside a domain Service,
so adding an attack means editing `CombatService`, which fails the
architecture's own test: *adding content should be a data edit.*

### Skills and attacks are one concept

Compare the bookkeeping, the way `PetRoster` was compared to `Equipment`:

| | Basic attack | Skill |
|---|---|---|
| volume, `activeWindow`, animation | ✓ | ✓ |
| cooldown | short | longer |
| cost, unlock | none | some |

Same shape, different fields populated. **A basic attack is a skill with no cost
and no unlock.** Two parallel systems would mean two lookups, two validators,
and two places to add a field forever. The vocabulary already exists —
`skillId`, `SkillService:isUnlocked`, `isReady`.

### The shape

```
serverShared/definitions/
    enemies/          walked at boot -- drop a file in, it exists
        Goblin.luau       stats, hp, loot, AND its skills, inline
        Archer.luau
    skills/           walked at boot
        Warrior.luau      player skills by class
    Hurtboxes.luau
    Resources.luau
```

**The loader is the load-bearing part.** Rojo turns a folder into an Instance,
so boot walks `GetChildren()` and requires each. Adding an enemy is then **one
new file and zero code edits.** An index file listing the modules would be the
same problem in more files — which is the thing this is meant to fix.

**Skills live inline in an entity's file** until a second entity actually wants
one, then move to `skills/Shared.luau` and get referenced by id. Not
preemptively.

**`EnemyTemplates` becomes `definitions/enemies/`.** Architecture Part 3 names
the role — *"Definition: owns the idea, not the instance"* — and `Template` is a
synonym that costs a mental translation on every read.

### Scope caution

**Do not let this become the skill system.** `SkillService`, cooldowns, damage
numbers and unlocks all stay stubs. Those are a different job, and dragging them
in is how a config move becomes a week.

---

## 2 — Animation: the first clip, end to end

**Status:** UNBUILT. **This is the next phase.**

### Blocked before anything else: the Roblox group must exist

An animation asset must be owned by the same account or group that owns the
experience. Group role permissions are documented as **not working properly for
animations**, and a personal-account asset does not transfer — it gets
re-uploaded.

**It is the only irreversible step in the entire pipeline**, and the decision
(GROUP) was made on 2026-08-16. Create it before the first upload.

### Then, in order

1. **Insert an R15 rig, author one swing, set priority to `Action` at author
   time.** A swing authored at `Core` is silently overpowered by the default
   walk cycle and looks exactly like a failed asset load — the standard first
   bug.
2. **Publish it. Record the id.**
3. **`Clips.luau`** — name → assetId, priority, fadeTime.
4. **`Rig.luau`** — builds and caches `AnimationTrack`s, rebinds on respawn.
   Death produces a new rig with a new `Animator`; every cached track from the
   old body is dead, and the same code path must handle both respawn and
   loadout change or one of them will rot.
5. **One line in `InputSystem`** to play it.

**That loop validates ownership, upload, the manifest, track caching and
rebinding** — none of which anything else in the repo exercises.

### What is settled about animation

| | |
|---|---|
| Ownership | **GROUP.** Must hold from the first upload |
| Rig | **R15** |
| Who plays a player's clip | **the client**, optimistically, before sending. The server round trip is the whole feel of the weapon |
| Who plays an NPC's clip | **the server.** Client-started never replicates |
| The animation never crosses the wire | client sends the skill; the server validates the skill and returns the damage. The clip is a private rendering decision |
| Markers never drive damage | client-side, on the wrong clock |

**Moon Animator is a tool preference with no architectural consequence for the
rig half** — its joint export is a normal `KeyframeSequence` that publishes like
any other. Its *property* half is what `Timeline.md` replaces.

---

## 3 — The Conductor

**Status:** DESIGNED (`Timeline.md`), UNBUILT. Gated on item 2.

Plays a **Score**: property tracks, action tracks, and clip tracks on one
transport. `Conductor` is the engine, `Score` is the document.

**The requirement is *tandem*, not interpolation.** Interpolating a number is
`a + (b - a) * t`. Staying locked to the swing is the part that actually fails,
and it fails by giving the effect its own stopwatch.

**The clock is a parameter**, and that is the one real abstraction:

| Clock source | For |
|---|---|
| follow an `AnimationTrack` | anything in tandem with a rig |
| free-running | standalone effects |
| anchored to a server timestamp | anything two players must see identically |

**A Score is a span of time with things scheduled in it. Silence is legal.** An
anime-style delayed slash is a 0.4s clip, an 800ms gap where nothing plays, and
a VFX burst at 1.2s. The transport keeps running because it is the Conductor's,
not a clip's.

---

## 4 — `motion = PATH`, the hitbox side

**Status:** DESIGNED (`HitDetection.md` Part 9), UNBUILT. Gated on item 3.

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
