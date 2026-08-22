# Asset Pipeline — Where Everything Actually Lives

### DataModel containers, replication, cloud assets, and the Rojo art path

> **Why this document exists.** The question *"where does a model live —
> the server or the workspace?"* was asked and answered wrongly, in slightly
> different words, across five separate exchanges. Every time, the answer was
> loose because three genuinely different concepts were being carried by one
> word. This document names all three, then traces every kind of asset from
> authoring to runtime.
>
> Read this before `Animation.md` or `HitDetection.md` §7. Both depend on it.

> **Status:** the platform facts are **SETTLED** and were verified against
> Roblox documentation on 2026-08-16, with sources cited inline. The Rojo art
> path is **PROVISIONAL** — the shape is decided, nothing is built, and no
> mesh has been imported yet.

---

## Table of Contents

1. The Three Concepts That Kept Getting Confused
2. The DataModel — One Tree, Several Copies
3. The Replication Table — What Clients Get
4. Cloud Assets — The Third Location Nobody Mentions
5. Every Asset Kind, Traced End to End
6. The Rojo Path — Getting Studio And Blender Into Git
7. Why Not Just Put Everything In ServerStorage
8. Rejected Designs
9. Current State and What Is Missing

---

## Part 1 — The Three Concepts That Kept Getting Confused

**Status:** SETTLED. This Part is the whole reason the document exists.

Three independent questions were repeatedly answered as though they were one.
They are not on the same axis and no single phrase covers them.

| # | Question | Answer is | Decides |
|---|---|---|---|
| 1 | **Which container is it parented under?** | `Workspace`, `ServerStorage`, `ReplicatedStorage`, … | whether clients receive it at all |
| 2 | **Which machine's copy are we talking about?** | the server's, or one client's | nothing — both exist for anything replicated |
| 3 | **Who owns its physics?** | network ownership: server by default, the client for its own character | whose simulation is authoritative for movement |

**The phrases that caused the damage, and what each actually meant:**

| Phrase used | Which concept it meant | Which it sounded like |
|---|---|---|
| "the boss lives on the server" | #1 — parented under `ServerStorage` | #2 — clients have no boss |
| "server-owned part" | #3 — network ownership | #1 — stored server-side |
| "server-animated" | who calls `:Play()` | clients cannot see it |

**Never say "lives on the server" again.** Say *"is parented under
ServerStorage"* (#1), or *"the server's copy"* (#2), or *"the server has
network ownership"* (#3). The three are independent: a part can be in
`Workspace` (replicated to everyone), present in six DataModels at once, and
owned by exactly one machine's physics.

---

## Part 2 — The DataModel — One Tree, Several Copies

**Status:** SETTLED.

### There are not two file trees

The most damaging version of the confusion was the belief that *"Workspace"*
and *"the server"* are two separate trees you move things between.

**There is one tree shape — the DataModel, rooted at `game`.** `Workspace` is
a service inside it, a sibling of `ServerStorage` and `ReplicatedStorage`.
It is a folder, not a location opposite the server.

```
game  (the DataModel)
├── Workspace              ← the 3D world. Rendered.
├── ReplicatedStorage      ← storage, replicated to all clients
├── ServerStorage          ← storage, server only
├── ServerScriptService    ← server code
├── StarterPlayer
├── Lighting
└── ...
```

### And the server and every client each hold a complete copy of it

Separate processes. Separate machines. Separate memory. A six-player session
has **seven DataModels** — one server, six clients.

Replication is the machinery that keeps the *replicated portions* of the
clients' trees matching the server's. It is not sharing; it is copying, with
the server as the origin.

```
        SERVER's DataModel                 EACH CLIENT's DataModel
        ─────────────────                  ───────────────────────
        Workspace ..................  →    Workspace          (mirrored)
        ReplicatedStorage ..........  →    ReplicatedStorage  (mirrored)
        ServerStorage                      ServerStorage      (EMPTY)
        ServerScriptService                ServerScriptService (EMPTY)
```

### The consequence that resolves the "move it to the server" question

> *"When I create a part in Studio it lives in Workspace. Move it to the
> server and it's gone."*

It is not gone. It is in `ServerStorage`, which is **not rendered** — the
Explorer shows the tree, the viewport shows only `Workspace`. Studio is
editing the server's DataModel.

Moving something out of `Workspace` does not make it more authoritative. It
makes it **invisible and unspawned**. Authority is concept #3 and #1 has no
bearing on it.

---

## Part 3 — The Replication Table — What Clients Get

**Status:** SETTLED. This restates `Architecture-Reference.md` Part 13's
replication boundary from the *asset* side rather than the *code* side; that
Part remains authoritative where they overlap.

| Container | Replicated to clients | Use for |
|---|---|---|
| `Workspace` | **Yes**, continuously | anything visible or physical, right now |
| `ReplicatedStorage` | **Yes**, at join | code the client executes, UI templates, the animation manifest |
| `ServerStorage` | **No** | unspawned model templates, server-only data |
| `ServerScriptService` | **No** | services, entities, routing, resolution |

**`ReplicatedStorage` is a broadcast, not a shared folder.** Everything in it
replicates to every client at join, and an exploiter can read and decompile
any ModuleScript there **whether or not a LocalScript ever requires it.** The
default is `ServerStorage`; moving something into `ReplicatedStorage` is a
deliberate disclosure. Architecture Part 13 carries the full threat model.

**The mapping in `dungeon.project.json`:**

| Repo path | Container |
|---|---|
| `src/shared/` | `ReplicatedStorage` |
| `src/serverShared/` | `ServerStorage.Shared` |
| `src/gameModes/dungeon/server/` | `ServerScriptService.Server` |
| `src/gameModes/dungeon/client/` | `StarterPlayer.StarterPlayerScripts.Client` |

---

## Part 4 — Cloud Assets — The Third Location Nobody Mentions

**Status:** SETTLED, verified 2026-08-16.

Parts 2 and 3 describe *your* game's tree. Some content is not in it at all.

**Mesh geometry and animation keyframes live on Roblox's servers**, addressed
by an id. Your game holds a string. The peer that needs the data fetches it
from Roblox's CDN directly — it never travels through your server.

| Content | Held in your game as | Actual data |
|---|---|---|
| A mesh | `MeshPart.MeshId = "rbxassetid://…"` | Roblox's CDN |
| An animation | `Animation.AnimationId = "rbxassetid://…"` | Roblox's CDN |
| An image/decal | `ImageLabel.Image = "rbxassetid://…"` | Roblox's CDN |

### Why this cannot be avoided

There is a real file layer beneath both. An animation is a `KeyframeSequence`
before upload; a mesh is triangles. Both are serialisable and can sit in the
repo as `.rbxm`.

**Neither can be played or rendered from local data at runtime.**
`KeyframeSequenceProvider:RegisterKeyframeSequence` and its successor
`AnimationClipProvider:RegisterAnimationClip` both document:

> "The asset ID generated by this function is temporary and cannot be used
> outside of Studio."

Re-verified 2026-08-16 specifically looking for a change: the restriction
carried over unchanged when `KeyframeSequenceProvider` was deprecated in
favour of `AnimationClipProvider`. A [feature request asking for exactly
this](https://devforum.roblox.com/t/create-animations-from-keyframesequences-in-live-games/2222384)
has been open since March 2023 with no staff reply.

**The upload is not a packaging step that could be skipped. It is the only way
to obtain an id the engine accepts.**

### What CAN be read back at runtime

`AnimationClipProvider:GetAnimationClipAsync(assetId)` downloads keyframe data
in a live game, on the server or the client. It is a yielding webcall that can
fail and must be wrapped in `pcall`. Suitable for boot-time validation
(`Animation.md` §10), never for a per-swing dependency.

---

## Part 5 — Every Asset Kind, Traced End to End

**Status:** SETTLED for the platform facts; the *repo* column is PROVISIONAL
until the first import happens.

| Asset | Authored in | Stored where | Referenced by | In git? |
|---|---|---|---|---|
| **Lua code** | editor | `src/…` | `require` | yes |
| **Model structure** — which parts, names, sizes, Motor6D joints | Studio | `assets/models/*.rbxm` → `ServerStorage.Models` | `:Clone()` | **yes** |
| **Mesh geometry** | Blender → uploaded | Roblox CDN | `MeshPart.MeshId` | no — **the id is**, inside the `.rbxm` |
| **Animation keyframes** | Studio's editor → uploaded | Roblox CDN | `Animation.AnimationId` | no — **the id is**, inside the manifest |
| **Textures / images** | any tool → uploaded | Roblox CDN | `"rbxassetid://…"` | no — the id is |
| **VFX templates** — emitters, beams, lights and their tuned curves | **Studio**, by hand | `assets/effects/*.rbxm` → `ReplicatedStorage.Effects` | `:Clone()`, on the **client** — §6.3 | **yes** |
| **The spawned Model** | — | `Workspace`, at runtime | an entity's `model` field | n/a — created by code |

### The pattern worth noticing

**Structure is checked in; bulk data is a cloud id.** It is the same shape
three times — the animation manifest holds `AnimationId`s, a `.rbxm` holds
`MeshId`s, and both are small text-ish references to large remote blobs.

Understanding one explains the others, and this is the sentence that would
have prevented most of the confusion this document records.

### The runtime lifecycle of a spawned enemy

```
1.  assets/models/Golem.rbxm         (git, synced by Rojo)
2.  → ServerStorage.Models.Golem     (server's DataModel, not replicated,
                                       invisible, never touched at runtime)
3.  local golem = ServerStorage.Models.Golem:Clone()
4.  golem.Parent = workspace          ← becomes visible to every client here
5.  → replicated into all six DataModels' Workspace
6.  EntityService:register(entity)     the Lua half (Architecture Part 7)
7.  SpatialService:attach(entity, golem.PrimaryPart, …)
```

Steps 1–5 are the physical half; 6–7 are the mental half. Architecture Part 7's
"Two Existences" governs their teardown.

---

## Part 6 — The Rojo Path — Getting Studio And Blender Into Git

**Status:** PROVISIONAL. Nothing built; no mesh has been imported yet. The
Rojo platform facts in §6.1 are SETTLED, verified 2026-08-20.

### The gap this closes

> *"If I create something in Blender and import it, it doesn't turn into
> code, it doesn't live in my GitHub, it doesn't live in my Rojo. It lives
> inside the Roblox experience."*

Correct as of today, and worse than it sounds: `.gitignore` contains
`/Shattered-Realms.rbxlx`. **The place file is not version controlled.**
Anything built in Studio right now exists in exactly one file on one machine,
outside git, and is not reproducible from the repo.

### 6.1 — Rojo syncs ONE WAY, and this is the fact everything else follows from

> *"When I make a part with cool particles in Studio, how do I bring it to the
> server? Does Rojo automatically sync it for me?"*

**No. Rojo's live sync runs filesystem → Studio, and only that direction.**

```
        repo  ─────────────── Rojo serve ──────────────►  Studio
                          (automatic, continuous)

        repo  ◄───────── you, by hand, once per save ───  Studio
                        (Save to File → .rbxm)
```

Everything you build by clicking in Studio is invisible to git until **you
explicitly export it**. There is no watcher for it, and nothing warns you. A
Studio session's work survives in the `.rbxlx` on one machine and nowhere else.

**Two partial exceptions exist and neither changes the answer:**

| Mechanism | What it actually does | Use it here? |
|---|---|---|
| Studio plugin **two-way sync** | an opt-in setting that pushes *supported* Studio edits back to disk — in practice `Script.Source`, so you can edit a script in Studio and have the file change | **No.** Code is authored in the editor. It covers the one thing that does not need covering. |
| **`rojo syncback`** | a CLI command that reads a `.rbxl`/`.rbxlx`/`.rbxm`/`.rbxmx` and writes its instances into the project tree, driven by `syncbackRules` in the project file | **Not routinely.** Worth knowing as a one-shot rescue for a place file that has drifted; it prunes and rewrites broadly, which is the wrong tool for "I made one nice emitter." |

So: **`Save to File` is the pipeline.** It is a deliberate, manual commit
point, and that is a feature — an automatic reverse sync would mean every
throwaway part you dragged into the viewport to test something ended up as a
repo diff.

### 6.2 — The workflow, both directions

**Geometry, from Blender:**

```
1. Model in Blender, export .fbx
2. Import into Studio  → MeshParts whose MeshIds point at Roblox's CDN
3. Rig and name in Studio → Motor6D joints, hitzone part names (HitDetection §7.2)
4. Right-click the Model → Save to File → assets/models/Golem.rbxm
5. Rojo maps assets/models/ into ServerStorage.Models
6. git add assets/models/Golem.rbxm
```

**Effects, authored entirely in Studio** — a Part or Attachment carrying
ParticleEmitters, Beams, PointLights, tuned by dragging curves in the property
editor:

```
1. Build it in Workspace, where you can see it
2. Tune it live -- this is the part Studio is genuinely better at than code
3. Right-click → Save to File → assets/effects/SuperSaiyanAura.rbxm
4. Rojo maps assets/effects/ into ReplicatedStorage.Effects
5. Runtime clones the template and parents it to a character
6. DELETE THE ONE IN WORKSPACE
```

**Step 6 is not housekeeping, it is correctness.** A leftover copy sitting in
`Workspace` is in the `.rbxlx` and not in the repo, so it exists for you and
for nobody who clones the project — and it will keep the effect looking like it
works long after the template has been broken or deleted. The template lives in
storage; the instance in the world is always a clone made by code.

Rojo accepts `.rbxm` (binary) and `.rbxmx` (XML) as `$path` targets. Rojo
7.5.0, April 2025, specifically improved `.rbxm` parsing performance.

### 6.3 — Effects go in ReplicatedStorage, and models do not

The container rule from Part 3 gives different answers for the two, and the
difference is not arbitrary:

| | Template lives in | Cloned by | Why |
|---|---|---|---|
| Enemy / boss models | `ServerStorage.Models` | the **server**, into `Workspace` | the server decides what exists; replication carries it down |
| VFX templates | `ReplicatedStorage.Effects` | **each client**, locally | a hit spark is cosmetic and per-viewer |

**An effect that must be seen is not an effect that must be authoritative.**
Cloning a 40-emitter aura on the server means replicating every emitter to
every client and paying for a networked instance for something that changes no
game state. Cloning it on the client is one local `:Clone()` triggered by a
Fact the server already broadcasts.

That puts VFX templates in `ReplicatedStorage`, which Part 3 correctly calls a
**deliberate disclosure** — every client downloads every effect at join and can
read it. Accepted without hesitation: the spoiler value of a particle texture
is nil, and there is nothing in an emitter to exploit.

**The existing code-built auras are not superseded by this.** `AuraDefinitions`
+ `Aura.luau` is a generic engine reading declarative configuration, which is
the right shape (`Architecture-Reference.md` Part 2). What changes with a real
template is *where the numbers come from*: a definition stops inlining thirty
properties and names a template instead.

```lua
SUPER_SAIYAN = { template = "SuperSaiyanAura", scale = 1.2, tint = ... }
```

Still declarative, still one engine, and the fields nobody wants to type by
hand — `NumberSequence` curves, `ColorSequence` gradients — get authored with a
mouse instead. **The engine does not change. The configuration gets a new kind
of field.**

### 6.4 — The project file change

**BUILT 2026-08-20.** `dungeon.project.json` now reads:

```json
"globIgnorePaths": ["**/.gitkeep"],

"ReplicatedStorage": {
  "$path": "src/shared",
  "Effects": { "$path": "assets/effects" }
},
"ServerStorage": {
  "Shared": { "$path": "src/serverShared" },
  "Models": { "$path": "assets/models" }
}
```

Note the shape of the `ReplicatedStorage` entry: `$path` and named children
coexist, so `src/shared` keeps mapping to the root while `Effects` is added
beside it. (Rojo project format: *"all other fields in an Instance Description
are turned into instances whose name is the key."*)

**`globIgnorePaths` is there because git cannot track an empty directory.**
Both folders hold a `.gitkeep` so they survive a clone, and Rojo would
otherwise try to make an instance out of it. Wired up *before* there is
anything to put in them, deliberately — the cost of an empty folder is nothing,
and the cost of not having one is that the first model you export has nowhere
to go and ends up in the place file instead, which is the exact failure Part 6
exists to prevent.

### The cost, stated honestly

**`.rbxm` is binary. Git versions it but cannot diff or merge it.** Each save
stores a fresh copy of the whole model, so the repo grows with revisions.

This is a real cost and the reason many teams keep visual instances in the
place file instead — an artist works directly in Studio, and a diff was never
going to be readable anyway. **That tradeoff does not apply here:** it is
about multiple people editing art concurrently. Solo, nothing is ever merged,
and reproducibility is worth more than diffability.

`.rbxmx` (XML) is the alternative — it diffs, badly, at several times the
size, and still cannot be meaningfully merged. Not worth it.

### The payoff

Once art arrives through Rojo, **the `.rbxlx` becomes a disposable build
artifact.** `rojo build` regenerates it from the repo. Keeping it gitignored
stops being a hole and becomes correct — which is the state to aim for, and
the reason to set up `assets/models/` before there is anything in it to lose.

---

## Part 7 — Why Not Just Put Everything In ServerStorage

**Status:** SETTLED. Asked five times in different forms; answered here once,
completely.

The proposal: keep models, animations and parts under `ServerStorage`, then
parent to `Workspace` when needed. *"That's true authority from the server."*

**For models this is exactly right and is the recommended pattern.** Parts 5
and 6 describe it. Templates in `ServerStorage`, clones into `Workspace`.

**For animations and meshes it is not possible** — Part 4. The data is not
yours to hold; you hold an id.

**And here is the part that matters: nothing is lost by that.**

### An animation contains no gameplay data

This is the misconception the whole five-round argument rested on. Here is
the complete contents of an animation:

```
KeyframeSequence
└── Keyframe (Time = 0.25)
    └── Pose "RightUpperArm"
        ├── CFrame            ← a rotation
        ├── Weight
        └── EasingStyle / EasingDirection
```

Joint rotations, and when they happen. **No damage. No power. No trajectory.
No range. No cooldown. No hitbox.** That is the entire format.

The only extensible field is `KeyframeMarker.Value`, a string — and anything
put there is data *you* authored, which belongs in the skill definition where
the server already reads it.

**So there is nothing in an animation to be authoritative about.** If they
carried damage and reach, holding them server-side would be non-negotiable.
They carry bone angles.

### Where authority actually lives, and it is already server-side

| Authority question | Answered by | Location |
|---|---|---|
| Does this entity own this skill? | `SkillService:isUnlocked` | server |
| Is it off cooldown? | `SkillService:isReady` | server |
| Is the entity allowed to act? | `StateService` | server |
| What shape does the attack hit? | `HitVolume` on the skill definition | server |
| Who was inside it at the compensated moment? | `SpatialService` + `TargetResolution` | server |
| How much damage? | `DamageResolution` | server |

**A client playing an animation the server never authorised accomplishes
nothing.** It is a lie told to its own screen: no damage, no movement, no
state change, nothing another player can observe as gameplay.

The single exception is hurtbox shape, which is why hurtbox anchoring is
restricted by network ownership — `HitDetection.md` §7 and `Animation.md` §11.

### And the cancel/reject loop already exists

> *"If they play the animation go for it, but I might send a packet back that
> will rewind your cheat or just straight up call `.cancel` on it."*

That is the built design, not a change to it:

| Step | Where | State |
|---|---|---|
| Client plays optimistically, registers the pending action | `PendingActions:add` | BUILT |
| Server disagrees | `EventRouter:reject()` | BUILT |
| Client cancels the track | `EventSender`'s `onResolved` | BUILT (untested end to end) |

### And boot-time validation is available too

The server *can* verify at boot that every animation a skill references
exists and loads — `GetAnimationClipAsync` works server-side (Part 4). The
validation wanted is available; only the file is not, and the file contains
nothing worth validating against.

---

## Part 8 — Rejected Designs

**Status:** SETTLED. Each kept with the test that catches it.

**Ship animations as `.rbxm` KeyframeSequences and play them locally.**
Registered ids are Studio-only (Part 4). The data loads fine; nothing can play
it. Re-verified against the newer `AnimationClipProvider` — same restriction.

**Move animation and mesh data under `ServerStorage` for authority.**
Impossible, and unnecessary: an animation holds joint rotations and no
gameplay data (Part 7). Authority already lives server-side in six places,
none of which read an animation.

**Put model templates in `ReplicatedStorage` so both sides can reach them.**
`ReplicatedStorage` is a broadcast. Every client downloads every boss model at
join and can inspect it before ever seeing the fight — spoiler surface plus
join time, for content most sessions never spawn. `ServerStorage` is the
default; clones reach clients through `Workspace` at the moment they should.

**Keep art in the place file and version only code.** The mainstream Roblox
answer, and correct for a team with artists editing concurrently. Rejected
here because the constraint that justifies it does not exist solo, and it
leaves the repo unable to rebuild the game.

**`.rbxmx` (XML) instead of `.rbxm` for diffability.** Several times the size
for a diff that is not human-readable and a merge that is not possible. Pays
a real cost for a theoretical benefit.

**Turn on Rojo's two-way sync and let Studio work land in the repo by itself.**
The plugin setting exists, and what it actually carries is `Script.Source` —
the one asset kind already authored in the editor, where it belongs. It does
not move a Part, an emitter or a rig. Enabling it buys a reverse channel for
code and a false impression that art is covered. (§6.1)

**Use `rojo syncback` as the routine art path.** It works, and it is the wrong
granularity: it reads a whole place or model file and rewrites the project
tree, pruning against `syncbackRules`. That is a rescue tool for a `.rbxlx`
that has drifted, not a way to check in one emitter. `Save to File` names
exactly what you meant to keep.

**Build effects in Workspace and leave them there.** The template ends up in
the place file — untracked, invisible to anyone cloning the repo, and still
rendering for you, so nothing looks broken until it is. Templates live in
storage; what appears in the world is always a clone made by code. (§6.2)

**Clone VFX on the server so everyone is guaranteed to see the same thing.**
Pays networked-instance cost for something that changes no game state and that
nobody can be advantaged by seeing differently. Cosmetics are per-viewer;
authority stays where Part 7 lists it. (§6.3)

**Treating "Workspace" and "the server" as two locations to move things
between.** Not a design, a misconception, recorded because it survived five
correction attempts. `Workspace` is a container inside a tree that the server
and every client each hold a full copy of (Parts 1–2).

---

## Part 9 — Current State and What Is Missing

**Status:** as of 2026-08-20.

| Piece | State |
|---|---|
| `src/` → Rojo → DataModel | **BUILT**, working |
| `assets/` | exists; holds two PNGs, unused by any build path |
| `assets/models/` | **BUILT**, empty |
| `assets/effects/` | **BUILT**, empty |
| `ServerStorage.Models` mapping in `dungeon.project.json` | **BUILT**, verified by `rojo build` |
| `ReplicatedStorage.Effects` mapping in `dungeon.project.json` | **BUILT**, verified by `rojo build` |
| `.rbxlx` in version control | deliberately gitignored — correct *only once* art comes through Rojo (Part 6) |
| Any imported mesh | **none yet** |
| Any uploaded animation | **none yet** |

**Asset ownership: DECIDED 2026-08-16 — a GROUP.** Chosen for the option value
of delegating permissions later. It applies to meshes and animations
identically, and it must hold from the very first upload: a personal-account
asset does not transfer to a group, it gets re-uploaded.

**The group does not exist yet.** Creating it is the first physical step of
this pipeline, before any Blender export or animation publish.
