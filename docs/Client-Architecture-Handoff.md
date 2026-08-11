# Client Architecture — Handoff Primer

**Purpose:** this is a cold-start primer for a fresh conversation about the
*client* side of Shattered Realms. It is not the client architecture
document — it is the set of conclusions already reached, so that the client
document can be written without re-deriving them.

**Read alongside:** `Architecture-Reference.md` (the server document). That
document remains authoritative for anything crossing the client/server
boundary. This one is scaffolding for a document that doesn't exist yet.

> **Status:** PROVISIONAL, everything here. Nothing described is built.

---

## The One Hard Rule About Splitting These Documents

The client/server boundary is where the most expensive bugs live —
reconciliation, eventId correlation, clock anchoring, what a client is
allowed to claim. **Those rules live in exactly one place: the server
document.** If they get restated in the client document, the two will drift
and each will look internally consistent while disagreeing with the other.

| Server document owns (do not duplicate) | Client document owns |
|---|---|
| What the client may report (Part 13) | Input handling, intent capture |
| Outbound event payload shapes (Part 12) | Prediction and reconciliation mechanics |
| The eventId correlation contract (Part 5, 15) | HUD bindings and display config |
| Server-clock anchoring | Animation playback, VFX, damage numbers |
| The explicit-reject carve-out (Part 15) | Camera behavior |

**Part 15 should shrink into the interface spec** and point here for
everything else. It should not be rewritten as a full client architecture.

---

## Why The Client Is Not A Smaller Copy Of The Server

The server architecture is organized around **authority over state**. The
client owns no authoritative state, so it needs none of the machinery that
exists to protect state. There are no client Services, no client Entities,
and no client Components in the server's sense of those words.

Mapping server concepts onto the client 1:1 is exactly what produced the
failure below.

## The Failure Being Corrected — The 3n Problem

The previous client ecosystem required a `Manager` + `Controller` + `System`
per displayed property. Gold needed three files. HP needed three more. So did
attack, defense, every buff, every stat. Three files per property, growing
linearly with content, each set diverging slowly from the others.

This is structurally the same mistake as the per-currency-Service problem the
server document already resolved (see its Part 8, "Why EconomyService Was
Wrong", and "What Client Notification Is Not"). Same disease, same cure:
**generic engine + declarative configuration.**

```lua
-- client/hud/HUDBindings.luau  (sketch, not built)
return {
    { attribute = "Gold", element = "GoldLabel", kind = "text", format = "%d" },
    { attribute = "HP",   element = "HealthBar", kind = "bar",  max = "MaxHP" },
    { attribute = "EXP",  element = "ExpBar",    kind = "bar",  max = "EXPCeiling" },
}
```

One binding engine reads the table, subscribes to each Attribute, updates the
named element. **Adding a displayed value is one row, not three files.**

Consequence: `BaseManager`, `ComponentLoader`, and the Manager/Controller/System
trio do not get repaired — they dissolve. They existed to give every property
a home. Once properties don't need homes, nothing is left for them to do.

**Naming collision worth knowing about:** `shared/utils/ComponentLoader.luau`
has nothing to do with entity Components. It walks a GUI folder for modules
exposing `newManager()` and instantiates client Manager objects. It belongs to
the rejected ecosystem above.

## The Four Client Concerns

```
INPUT      raw input → intent; sends Requests. Owns nothing.
PREDICT    pending-actions map, optimistic playback, reconciliation
VIEW       HUD and world visuals. Reads replicated values. Never decides.
PLAYBACK   animation, VFX, camera, damage numbers. Driven by inbound events.
```

## Signal On The Client

Signal is **not a transport**. It never crosses the client/server boundary in
either direction; the wire is EventTape both ways. The `Signal` class lives in
`shared/` and works on both sides, with separate instances and separate
vocabularies that are never wired together.

The client needs much less pub/sub than the server, because most client
"communication" is data binding, not events:

| Need | Mechanism |
|---|---|
| A replicated value changed → redraw | Attribute + `GetAttributeChangedSignal` (Roblox provides this) |
| A discrete server event happened | Inbound EventTape, one dispatch point |
| A genuinely client-local fact (input mode changed, cinematic started, panel opened) | Client-side Signal — the only place it earns its keep |

If the client ends up declaring twenty signals, most are probably row one in
disguise.

## Animation — Facts, Not Commands

**Wrong shape:** server tells the client "play animation X for Y seconds."
That makes every new animation a server change and fills server code with
cosmetic knowledge.

**Right shape:** server sends what happened; the client decides how to render
it.

```
Server sends:  { type = "SKILL_ACTIVATED", entityId, skillId = "SLASH_3",
                 serverTime = 1234.56 }
Client does:   look up SLASH_3 in its own animation manifest → play it,
               anchored to serverTime
```

The animation manifest is Content Layer. A flashier animation becomes a
content edit that never touches server code.

The server does own **timing** where timing is authoritative — telegraph/
execute, cinematics — which is why events carry a server timestamp and the
client plays to the server clock, never its own.

## Camera — Client Only, But Half Of A Paired Feature

- **Server `CinematicService`** (Dungeon only, in the server registry):
  decides a cinematic happens, sets `FROZEN`/`INVULNERABLE` via StateService,
  handles opt-in/opt-out, sends the event with a server timestamp.
- **Client `CameraController`:** receives it, hijacks the camera, plays to
  that timestamp, restores.

The state consequences are server-authoritative — a player who is IMMOBILIZED
during an ultimate stays immobilized whether or not their camera cooperated.
The camera itself is purely cosmetic. Keeping the halves separate means a
client that refuses the camera does not escape the gameplay effect.

## Known Problem To Address Early

`src/gameModes/dungeon/client/` and `src/gameModes/hub/client/` are currently
near-duplicates of each other — two copies of `ClientManager`, `UIManager`,
`UIRootGUI`, `PlayerManager`, the healthbar trio, `CameraSystem`,
`InputSystem`, `TweenUtil`. This is the client version of the problem the
server document solved in its Part 13: **one shared tree, scoped per place via
`.project.json`**, never duplicated per place. The client needs the same
answer, and the duplication gets worse with every place added.

## Conventions To Carry Over

1. **Status tags on every section** — `SETTLED` / `PROVISIONAL` / `UNBUILT` /
   `SUPERSEDED`. Most valuable in a brand-new document, where nearly
   everything is provisional and it is tempting to write as though it isn't.
2. **A rejected-designs table, not narrated history.** Keep the *test* that
   catches a mistake; drop the story of which revision made it. The first two
   rows are already written: the Manager/Controller/System ecosystem, and
   `ComponentLoader`-style folder auto-loading.
3. **Do not pre-write it.** The server document reached ~4,400 lines ahead of
   any code, and a full session was spent compressing it. The client document
   arrives second, with a working server to disagree with it — let it grow as
   the client gets built.
