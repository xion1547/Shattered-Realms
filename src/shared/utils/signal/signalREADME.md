# Signal System

Fact broadcast for this project. Canonical spec: `docs/Architecture-Reference.md`,
Part 11.5. This file is the practical usage guide; where the two disagree, the
Architecture Reference wins.

## What a Signal is

A Signal announces that something **has already, unconditionally happened**.
It carries no validation, makes no decision, returns nothing, and every
listener connected to it is called. Nothing connected to a Signal is ever
asked to approve or reject anything — that decision was already made and
finished by a Service before `Fire` was reached.

**A Signal never crosses the client/server boundary.** The class lives in
`shared/` because both sides use it, not because a signal is ever
transmitted. The wire is EventTape, in both directions. Client and server
each get their own module state and their own vocabulary.

## Files

| File | Purpose |
|---|---|
| `Signal.luau` | The broadcast primitive. Constructed by SignalService, not by gameplay code. `ReplicatedStorage` — both sides use the class. |
| `SignalService.luau` | The broker: `init` / `declare` / `on` / `validate`. `ReplicatedStorage`, with **separate module state per side**. |
| `serverShared/signal/SignalVocabulary.luau` | The server vocabulary — the flat list of legal fact names. **`ServerStorage`**, never replicated: it is the complete list of the game's internal event names. The client keeps its own. |

## The three rules

1. **A fact has exactly one owner.** `declare()` returns the only
   fire-capable reference. Keep it in a local or a private field. If two
   things can fire the same fact, listeners cannot trust it.
2. **Subscribe by name, never by module reference.** `on("Combat.OnKill", fn)`
   works in a place where `CombatService` does not exist. `require`ing the
   publisher does not, and that breaks place separation.
3. **Names come from a vocabulary file.** Facts are not created ad hoc.
   `declare` and `on` both reject a name that isn't in the loaded vocabulary.

## Usage

```lua
local SignalService = require(ReplicatedStorage.utils.signal.SignalService)
local ServerSignals = require(ServerStorage.Shared.signal.SignalVocabulary)

-- 1. First step of boot, before anything declares or subscribes.
--    Pass every vocabulary this place uses.
SignalService.init({ ServerSignals, DungeonSignals })

-- 2. The owning Service claims its facts and keeps the references private.
local OnKill = SignalService.declare("Combat.OnKill")

-- 3. Anything else subscribes by name. Legal before the owner has declared,
--    and legal in a place where the owner does not exist at all.
local conn = SignalService.on("Combat.OnKill", function(attacker, victim)
    -- react
end)

-- 4. After every Service has booted, before gameplay.
SignalService.validate()

-- Firing: only the owner can, because only the owner has the reference.
OnKill:Fire(attacker, victim)

-- Unsubscribing: hold the handle.
conn:Disconnect()
```

## Boot validation

`validate()` checks both directions and fails once, aggregated:

- a name **subscribed to but never declared** — a listener waiting on
  something that will never fire
- a name **in the vocabulary but never declared** — the vocabulary claiming a
  fact exists here when nothing produces it

Both are silent no-ops in production and boot failures here, which is the
point. Same two-way discipline the Architecture Reference applies to place
manifests (Part 13).

## Gotchas

- **`Connect` returns a handle.** Hold it if you will ever need to
  disconnect. There is no `Disconnect(fn)` — a wrapped closure could never be
  removed that way.
- **Duplicate connections are allowed.** Connecting the same function twice
  fires it twice. Earlier versions silently ignored duplicates, which hid
  double-registration bugs.
- **Listener order is connection order**, which is boot order — deterministic
  but implicit. A listener must not mutate state another listener on the same
  signal reads. Needing ordered reactions means the relationship was
  inherent, not optional — use a direct call or a pipeline (Part 11.4).
- **A failing listener is warned and skipped**, never rethrown. The fact is
  true regardless of who mishandles it.
- **There is no `get(name)`.** Handing back the Signal would hand back
  `Fire`, which is the one thing this module exists to withhold.

## Naming

Every name reads like a past-tense fact: `OnHit`, `OnDied`, `OnJoined`. If a
name reads like a command (`DoAttack`, `RequestPickup`), a Request or
Intention has drifted into Signal's territory and belongs in a direct Service
call instead.

## Removed

`SignalHelper` and `SignalEnum` are deleted. `SignalHelper` resolved a
registry path to exactly one Manager method, which meant it structurally
supported one listener per signal — the degenerate case an explicit
`:Connect()` already handles in one greppable line — while making runtime
behaviour depend invisibly on folder layout. `SignalEnum` derived a name list
by walking live Signal objects; under the vocabulary model the name list *is*
the source file. See Architecture-Reference.md Part 19.
