# Shattered Realms — EventTape
### The Implementation Map for the Layer That Carries Everything

> **This is not a design document.** `Architecture-Reference.md` Part 12 owns
> every *why* about EventTape and stays authoritative. This document owns
> *what exists, where it lives, and how to add to it* — the questions Part 12
> deliberately does not answer because they change with the code.
>
> **Duplicating a rule from Part 12 into this file is the one thing that must
> not happen.** Two documents restating the same rule drift, and each ends up
> internally consistent while disagreeing with the other. Where you need the
> reasoning, this file links; it does not re-argue.
>
> **Status:** the inbound path is **BUILT**, and has now been driven end to
> end in Studio — see §7 for what was observed. The outbound path is
> **PARTIAL**: rejection works and has been seen working; confirmation exists
> but nothing calls it. Per-section tags below.
>
> - **BUILT** — exists, has tests, works.
> - **PARTIAL** — exists but has no real caller, or has a named gap.
> - **UNBUILT** — named here so it is not mistaken for an oversight.

---

## Boundary

| Part 12 owns (do not restate here) | This document owns |
|---|---|
| Why one centralized RemoteEvent | Which module owns which job |
| Why arrival order, never a sort | The two end-to-end traces |
| Why a routing table, not a handler folder | The wire message shapes |
| Why routing stops at the top-level domain | The recipe for adding an event type |
| Which services get an eventType at all | Where each validation actually runs |
| What the client may report (Part 13) | Caps, timeouts, and current gaps |

---

## 1 — The File Map

**Status:** BUILT.

Fourteen modules. The split is by *job*, and the one thing worth internalizing
is which side of the wire each lives on — anything in `shared/` is readable by
a client, which is why routing is not there (Part 13).

### `src/shared/eventTape/` — both sides

| Module | Owns |
|---|---|
| `event/Event.luau` | The one Event instance class. `Event.build` is the single constructor both paths use. |
| `event/EventSchema.luau` | The validation engine. Types, required/requiredFor, defaults, unknown-key rejection. |
| `event/Validators.luau` | Composable predicates for a schema's `check` field. Leaf module, no dependencies. |
| `event/EventBuilder.luau` | The fluent base. `extend()` mints a per-type Builder; `_set` validates one field at its call site. |
| `event/EventFactory.luau` | `create(eventClass)` → that type's builder. A named entry point, nothing more. |
| `event/EventType.luau` | The four top-level domain names, and nothing else. SubTypes live in their classes. |
| `event/EventRegistry.luau` | `eventType` → class, plus `validate()`, the boot check over every declaration. |
| `event/EventDeserializer.luau` | Plain data → typed Event. Plain module, one function. |
| `event/EventTape.luau` | An ordered batch. A list that serializes to plain data. Decides nothing. |
| `event/types/*.luau` | One file per event type: subTypes, schema, builder methods, accessors. |
| `wire/MessageKind.luau` | `TAPE` / `REJECT` / `CONFIRM` / `PUSH`. |
| `wire/RejectReason.luau` | Why the server refused, and the structural-vs-behavioural split. |

### `src/gameModes/dungeon/server/eventTape/` — server only

| Module | Owns |
|---|---|
| `EventRouter.luau` | Receive, deserialize, buffer, drain, route, reject. The whole inbound path. |
| `EventRoutingRegistry.luau` | `eventType` → `{ service, method }`, as declarative data. Never eager `require`s. |

### `src/gameModes/dungeon/client/eventTape/` — client only

| Module | Owns |
|---|---|
| `EventTapeClient.luau` | Façade. The only file input code imports. |
| `EventSender.luau` | Batches a frame's events into one tape, one `FireServer`. |
| `EventReceiver.luau` | Parses inbound messages, routes by `kind`. |
| `PendingActions.luau` | What was sent and not yet answered. Expiry sweep. |

---

## 2 — Trace: Client → Server

**Status:** BUILT.

```
input code
  │  EventFactory.create(CombatEvent):withSubType(…):withTargetId(…):build()
  │    → each :withX() validates ITS OWN field immediately (EventBuilder._set)
  │    → build() runs cross-field rules and mints the eventId
  ▼
EventTapeClient:queue(event, label, onResolved)
  │  → PendingActions:add(eventId, label, onResolved)
  │  → EventSender._queue
  ▼
EventSender:flush()                        once per Heartbeat, or at 16 queued
  │  → EventTape:serialize()  — flattens to plain data, metatables do not
  │                             survive a RemoteEvent
  │  → FireServer({ kind = TAPE, tape = … })
  ▼
════════════════════ the wire ════════════════════
  ▼
EventRouter:_receive(player, message)
  │  → rejects a non-TAPE message                        (warn, no reply)
  │  → EventTape.unpackSerialized                        (warn, no reply)
  │  → over 32 events? drop the whole tape               (warn, NO REJECT — §7)
  │  → per event: EventDeserializer.deserialize(blob)
  │       ├── ok    → buffer { player, event, receivedAt }
  │       └── fail  → reject(eventId, MALFORMED)
  │  → receivedAt is stamped ONCE per tape, server-side. The only timestamp
  │    anything ordering-related may use.
  ▼
Scheduler Heartbeat → router:drain()       BEFORE any service tick, so a tick
  │                                         never sees a half-applied frame
  │  → processes the batch in insertion order. No sort — insertion order IS
  │    arrival order (Part 12).
  ▼
EventRouter:_route(player, event, receivedAt)
  │  → no route for this eventType? reject(UNROUTABLE) — this is the Hub-has-
  │    no-Combat case working as designed, not a gap (Part 13)
  │  → pcall(handler, player, event, receivedAt)
  ▼
CombatService:OnAttack(player, event)
     subType dispatch from here on is Combat's own business, never EventTape's
```

**The buffer cap is 2048.** Past that, events are counted and dropped, and the
count is warned once per drain rather than once per event.

---

## 3 — Trace: Server → Client

**Status:** PARTIAL — every piece below exists and is wired; nothing calls
`confirm` or `push` yet, because no Service resolves anything yet.

```
Service (once one exists)
  │  router:confirm(player, eventId, diff)   answering a specific Request
  │  router:push(player, eventType, payload) unsolicited — someone else's hit
  │  router:reject(player, eventId, reason)  refusing a Request
  ▼
FireClient({ kind = …, … })
  ▼
EventReceiver:_dispatch(message)
  │  → invalid kind? warn and drop (means a client/server build mismatch)
  ├── REJECT  → PendingActions:resolve(id, "REJECT", msg)
  │              structural reason → warn loudly, never shown in-game
  │              ILLEGAL           → the only one a real player can cause
  ├── CONFIRM → PendingActions:resolve(id, "CONFIRM", msg)
  │              TODO: apply message.diff to the display layer
  └── PUSH    → the handler registered via EventTapeClient:onPush(eventType, fn)

separately, every Heartbeat:
PendingActions:sweep()  → anything unanswered for 10s resolves as "TIMEOUT"
                          so a dropped packet cannot strand an optimistic
                          animation forever (Part 15)
```

`onResolved(outcome, message)` is the single callback an optimistic action
supplies. `outcome` is `"CONFIRM"`, `"REJECT"` or `"TIMEOUT"` — a caller that
handles all three needs nothing else to be correct under packet loss.

---

## 4 — The Wire

**Status:** BUILT.

Every payload in both directions is an envelope with a `kind`. It is the one
field every message has, because the receiver must switch on it before it
knows how to read anything else.

```lua
-- client -> server
{ kind = "TAPE",    tape = { events = { <serialized event>, … } } }

-- server -> client
{ kind = "REJECT",  eventId = "…", reason = <RejectReason> }
{ kind = "CONFIRM", eventId = "…", diff   = <what the commits RETURNED> }
{ kind = "PUSH",    eventType = "…", payload = { … } }
```

A serialized event is exactly four fields:

```lua
{ eventId = "…", eventType = "COMBAT", subType = "MELEE", data = { … } }
```

**No timestamp crosses the wire.** `os.clock()` has an arbitrary per-process
origin, so the sender's value is meaningless to the receiver — and a
client-reported time would be untrusted regardless (Part 13). The Event keeps
a local construction time with no setter; the server stamps `receivedAt`.

### Reject reasons

| Reason | Kind | Sent today? |
|---|---|---|
| `MALFORMED` | structural | **yes** — failed deserialization or validation, one reject per event |
| `UNROUTABLE` | structural | **yes** — no Service owns this eventType here |
| `OVERSIZED` | structural | **yes** — tape past `MAX_EVENTS_PER_TAPE` (50), one reject per tape |
| `RATE_LIMITED` | structural | **yes** — past the token budget, one reject per tape |
| `ILLEGAL` | behavioural | no — needs a Service that refuses an action |

**Tape-level refusals send ONE reject, never one per event.** Answering all
fifty ids would let a sender turn one inbound message into fifty outbound
ones — amplification handed to exactly the traffic being refused. The client's
`PendingActions` sweep resolves the rest as `TIMEOUT`, so nothing is stranded,
only slower to clear.

`RejectReason.isStructural(reason)` is the client's branch: structural means
the payload was refused before any game logic ran, so warn loudly and show
nothing in-game. `ILLEGAL` is the only one worth surfacing in the UI.

**One nuance on `UNROUTABLE`:** it is structural, but a *legitimate* client can
cause it. A place that excludes a Service rejects its eventType by design
(Part 13), so a client that has not caught up with which place it is in
produces exactly this. Worth a warning; not proof of tampering.

### Rate limiting

**Per player, token bucket, charged per EVENT.**

| Knob | Value | Bounds |
|---|---|---|
| `MAX_EVENTS_PER_TAPE` | 50 | one burst, per tape |
| `RATE_LIMIT_PER_SECOND` | 50 | sustained refill |
| `RATE_LIMIT_BURST` | 100 | spendable at once, then earned back |

The per-tape cap alone was never enough: a tape is one frame's batch, so a cap
of 50 permits ~3000 events/second at 60fps. It bounds one burst; the bucket
bounds throughput.

Three properties worth keeping:

- **Charged for the whole tape before any of it is processed** — otherwise a
  refused tape has already paid for the work it was refused for.
- **A refusal deducts nothing.** Charging for refused traffic would dig a hole
  a spammer could never climb out of, leaving them locked out after stopping.
- **The per-tape cap is checked first**, so an oversized tape never reaches the
  limiter and cannot cost a client its budget.

Buckets are held in a weak-keyed table, so a departing player's bucket is
collected without anything having to remember to clean it up.

---

## 5 — Where Validation Runs

**Status:** BUILT. Three places, deliberately, each answering a different
question.

| Where | When | Why there |
|---|---|---|
| `EventBuilder:_set` → `EventSchema.checkField` | every `:withX()` call | The error names the line that is wrong. Type + `constraint` only. |
| `Event.build` → `EventSchema.parse` | `build()` **and** deserialize | Cross-field rules — `required`, `requiredFor`, defaults, unknown keys — cannot be judged until every field is in. |
| `EventRegistry.validate()` | boot, once | The declarations themselves: schema well-formedness, and every field has a builder method. |

**It is `parse`, not `validate`, and the name is load-bearing.** It does not
answer a yes/no question — it returns a *new* table: unknown keys rejected,
declared fields copied, defaults filled in. A payload of `{ id = "attack1" }`
comes back as `{ id = "attack1", speed = 1.0 }`, bigger than it went in.

**A constraint validates the value, never the world.** It may not consult a
definitions table, a registry, or any game state. There was an
`existsIn(catalog)` and `AnimationRegistry.isKnown` wired into a schema; both
are gone. The check made this layer depend on the Content Layer to answer a
question it could not act on — "this skill exists" is not "this player may use
it" — and the Service has to answer that regardless. Existence and permission
are a Service's job (Part 5). `Validators.luau` states the boundary in full.

**The property worth protecting:** the authoring path and the wire path both
end at `Event.build`. A rule enforced only in the builder would apply to
hand-written events and be silently skipped for anything arriving from a
client — which is the half that actually matters.

**Failures are raised on the authoring path and returned on the wire path.**
A bad `:withSkillId(42)` is a programmer error and throws. A bad payload off
the wire is expected traffic, so `deserialize` returns `(nil, reason)` and the
router rejects that one event and keeps processing the rest of the tape.

**Boot validation gates nothing at runtime.** Everything `EventRegistry
.validate()` checks is static. Forgetting to call it costs you an early
failure, never a broken deserialize. It is called from
`ServerManager:_initEventTape` and from `Main.client.luau`.

---

## 6 — Recipes

### Adding an event type

**Three files always. Two more only if a client sends it.** Nothing else in
the codebase changes — and every omission below is caught at boot or by the
type checker, never silently.

**1 — `EventType.luau`.** One name in `NAMES`:

```lua
CRAFTING = "CRAFTING",
```

**2 — `types/CraftingEvent.luau`.** The whole event, one file:

```lua
local Event = require(script.Parent.Parent.Event)
local EventBuilder = require(script.Parent.Parent.EventBuilder)
local EventSchema = require(script.Parent.Parent.EventSchema)
local EventType = require(script.Parent.Parent.EventType)
local Validators = require(script.Parent.Parent.Validators)

local CraftingEvent = {}

CraftingEvent.eventType = EventType.CRAFTING

CraftingEvent.SubType = table.freeze({ ALPHA = "ALPHA", BETA = "BETA" })

local schema: EventSchema.Schema = {
    thingId = { type = "string", required = true },
    amount  = { type = "number",
                requiredFor = { CraftingEvent.SubType.BETA },
                constraint = Validators.range(1, 99) },
}
CraftingEvent.schema = schema

local Builder = EventBuilder.extend(CraftingEvent)
CraftingEvent.Builder = Builder

function Builder:withThingId(thingId: string) return self:_set("thingId", thingId) end
function Builder:withAmount(amount: number)   return self:_set("amount", amount) end

function CraftingEvent.getThingId(event) return event:get("thingId") end

-- Fails HERE if this stops being a valid event module, rather than in
-- EventRegistry -- the wrong file to be reading when the mistake is in this one.
local _conforms: Event.EventModule = CraftingEvent

return CraftingEvent
```

Note `requiredFor` references `CraftingEvent.SubType.BETA`, never the bare
string. Misspell it and the field silently stops being required for a subType
that no longer matches anything.

**3 — `EventRegistry.CLASSES`.** One line, keyed by the constant:

```lua
[EventType.CRAFTING] = require(types:WaitForChild("CraftingEvent")),
```

**4 — `EventRoutingRegistry`, only if a client originates it** and a Service
must authorize it. Outbound-only types (`ANIMATION`) get no row on purpose, and
an inbound one is correctly rejected as `UNROUTABLE`.

**5 — the Service must expose that method.** Absent in this place is legal and
becomes `UNROUTABLE`; present but missing the method fails boot.

#### What catches you if you forget

| Mistake | Caught by |
|---|---|
| `EventType` name with no class | `EventRegistry.validate()` — names it |
| schema field with no `:withX()` | `validate()` — names the method you owe |
| `:withX()` with no schema field | `validate()` — names the orphan |
| no `Builder`, no subTypes, wrong `eventType` | `validate()` |
| typo'd spec key, uncalled validator | `EventSchema.validateSchema` |
| routing key that is not a declared type | `EventRouter:resolveRoutes`, at boot |
| routing entry whose Service lacks the method | `resolveRoutes`, at boot |
| module missing a required field | the `_conforms` line, in your own file |

There is no `build` wrapper to write, no `builder()` wrapper, and no
deserializer change. SubTypes never leave the class that declares them.

**The one drift the validator does not catch:** it checks that a method with
the right *name* exists, never what that method *sets*. A copy-pasted
`withThingId` whose body reads `_set("amount", …)` passes boot and writes the
wrong field. Closing that means generating the setter bodies from the schema —
a real change, not yet made.

### Adding a routable domain

One row in `EventRoutingRegistry`, naming a service module and a method:

```lua
COMBAT = { service = "CombatService", method = "OnAttack" },
```

Entries are **data, never eager `require`s**. `EventRouter:resolveRoutes`
resolves them lazily against the services actually present in this place, with
three outcomes: module and method present → routable; module absent → not
routable here, and that is correct; module present but method missing → a real
bug, fails boot.

### Adding a validator

`Validators.luau`, and use it in a schema's `constraint`.

**Every validator is a factory** — `Validators.nonEmptyString()`, never
`Validators.nonEmptyString`. That uniformity is what makes the footgun guard
possible: with no bare-predicate exception, any constraint that *is* one of the
module's own functions is by definition the uncalled mistake, so the check is a
scan of the module rather than a hand-kept list that silently stops covering
whatever you forget to add to it. An uncalled factory would otherwise be a
function returning a truthy closure, passing every value forever.

It must answer from the value and the schema alone — see the boundary note in
§5. If it needs a catalog, it is a game rule, not a constraint.

---

## 7 — Verified End to End

**Status:** run in Studio, this revision. Recorded because there is no
automated way to observe a RemoteEvent crossing the boundary — the trace was
the observation, and the instrumentation that produced it has since been
removed.

Three paths were driven from a temporary client UI and all three behaved:

| Path | Result |
|---|---|
| `COMBAT/MELEE` | Full happy path — built, queued, flushed one frame later (~17ms), received, charged one token, deserialized, buffered, drained, reached `CombatService:OnAttack` with its `targetId` intact. |
| `ANIMATION/ATTACK` | `UNROUTABLE` → `REJECT` → client resolved its pending action and fired the caller's callback. ~34ms round trip. The first exercise of the outbound half. |
| Hand-rolled `ADMIN_GIVE_GOLD` | Fabricated payload sent straight to `FireServer`, bypassing the builder entirely — the way a real attacker arrives. Died at the registry lookup before any Service saw it. The client correctly reported it as untracked, because `PendingActions` never recorded something it did not send. |

Also confirmed in the same run: a mixed-domain tape (COMBAT, COMBAT,
INVENTORY) buffered and drained in send order with no sort; one malformed
event inside a valid tape was rejected while the events either side of it were
processed; four junk envelopes were discarded at `RECV`; a 60-event tape was
refused as `OVERSIZED`; and token accounting decremented and refilled
correctly across frames.

**The suite found eight failures, and two of them had never run.** One test
passed a human-readable message into `Assert.throws`'s *expected substring*
slot, so it asserted the error text contained that sentence — it never could.
Another branched on `event:getData().n`, and `n` has never been a `CombatEvent`
field, so the intentional error never fired and the test's premise was never
exercised. Both had been reporting green while testing nothing.

---

## 8 — Known Gaps

**Status:** current as of this revision. Goes stale faster than anything else
here — when it disagrees with the repository, the repository is right.

- **A successful action never resolves on the client.** `CombatService:OnAttack`
  logs and returns; nothing calls `EventRouter:confirm`. So a successful event's
  pending entry sits until the 10-second `TIMEOUT` sweep, which means *success
  is currently indistinguishable from a lost packet*. Rejection is the only
  outcome that resolves promptly. Blocked on real validation existing.
- **`ILLEGAL` is never sent**, for the same reason — it is the one reason a
  Service produces, and none of them refuse anything yet.
- **The outbound shape is PROVISIONAL.** `confirm` / `push` send one message
  per call with no batching — the minimum that works. Part 12 specifies the
  inbound path in detail and leaves this open deliberately. Decide the real
  shape when the first Service needs it, and update Part 12 then, not here.
- **`CONFIRM` does nothing with `diff`.** `EventReceiver:_onConfirm` resolves
  the pending entry and has a TODO where the display layer will go.
- **`UnreliableRemoteEvent` is not used.** Part 12 names it as a legitimate
  second channel for purely cosmetic traffic that needs no ordering
  guarantee. A later optimization, not a foundational decision.

---

## 9 — Invariants That Break Silently

Each of these has already broken once, or is one edit away from it. None of
them fail loudly on their own.

| Invariant | What breaks if violated |
|---|---|
| `serialize()` returns plain data all the way down | Metatables do not survive a RemoteEvent. The receiver gets plain tables where it expected methods. |
| The drain buffer is never sorted | `table.sort` is not stable; sorting by timestamp actively reorders same-timestamp events away from true arrival order. |
| `EventRoutingRegistry` holds names, never `require`s | A place excluding a Service errors on load instead of simply not routing that type. |
| Routing stays in `server/` | Anything in `ReplicatedStorage` can be dumped by a client, including the full map of internal event names. |
| A definitions table never touches the DataModel at load | `AnimationRegistry` used to read `workspace.Animations` at require time and took the client down with it. |
| No timestamp crosses the wire | A client-supplied time is the exact input the latency rewind must not let a client choose. |
| Every pending action has a bound | Without the sweep, a dropped packet strands an optimistic animation forever. |

---

## 10 — Rejected Designs

Compressed. The full reasoning for each lives in Part 12 — kept here only so
nobody re-proposes one after reading this file alone.

| Rejected | Test that catches it |
|---|---|
| One RemoteEvent per eventType | Ordering cannot be guaranteed across N independent tapes |
| Per-domain EventTape pipelines | Same — and routing still has to happen anyway |
| A `handlers/` folder of one-line modules | Can you read the whole event→service map in one file? |
| Self-dispatching `Event` objects | A `shared/` data object would depend on a server-only Service |
| Event subclasses per type | The differences became data; the subclass had nothing left to own |
| Generated `:withX()` methods | A generated method is invisible to the language server, which is the entire point of having one |
| A per-type `build` wrapper | Pure argument binding; both callers already hold the class |
| `preload()` as a runtime gate | It loaded nothing and guarded a static property with a runtime flag |
| A null service for an absent domain | Absence is a security property; auto-confirming trains the client on a world where nothing fails |
