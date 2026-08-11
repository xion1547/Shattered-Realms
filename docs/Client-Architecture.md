# Shattered Realms — Client Architecture
### How The Client Is Built, And Why It Isn't A Copy Of The Server

> **Read alongside `Architecture-Reference.md`.** That document is the server
> architecture and it stays authoritative for everything crossing the
> client/server boundary. This document owns the client side of the wire and
> nothing else. Where the two appear to disagree about the boundary itself,
> the server document wins and this one is stale.
>
> **Status:** nothing described here is built. Most of it is `PROVISIONAL`.
> Read the tags — they are the difference between a decision that survived
> being attacked and a decision that merely sounds good.
>
> - **SETTLED** — decided, with reasoning that has survived attack. Usually
>   because it falls out of a server-document decision that is already settled.
> - **PROVISIONAL** — the shape is decided, but it has never met a real use
>   case. Build the first one and let it disagree.
> - **UNBUILT** — no code exists. This is nearly everything here.
> - **SUPERSEDED** — code exists and this document no longer describes it.
>
> **Deliberately shorter than the server document.** The server document
> reached ~4,400 lines ahead of any code and a full session was spent
> compressing it. This one arrives second, with a working server to disagree
> with it. It stops at the decisions and leaves implementation detail
> genuinely open. Do not pre-write the rest of it.

---

## Table of Contents

1. The Diagnosis — Two Populations, One Treatment
2. The Boundary — What This Document Does Not Own
3. The Two Channels — Values You Watch vs. Things That Happened
4. The Five Concerns
5. VIEW — Widgets, Bindings, Renderers
6. ROUTE — The Client Router and the Presenters
7. INPUT — Intent, Contexts, and the Outbound Edge
8. PREDICT — One Pending Map, Not One Per Feature
9. PLAYBACK — Facts In, Content Out
10. Boot, Place Scoping, and Validation
11. Worked Example — The Health Bar, End To End
12. Worked Example — What Adding Things Actually Costs
13. Where This Design Hurts
14. Rejected Designs
15. Quick Reference
16. Build Order

---

## Part 1 — The Diagnosis — Two Populations, One Treatment

> **Status:** SETTLED. This is the reasoning every other Part applies.

The previous client ecosystem needed a `Manager` + `Controller` + `System` per
displayed property. Gold cost three files. HP cost three more. So did attack,
defense, every stat, every buff, every currency. Three files per property,
growing linearly with content, each set diverging slowly from the others.

The usual framing of that failure is "too much boilerplate." That framing is
wrong, and it leads to the wrong fix (write less boilerplate per property —
still `n` files, just smaller ones). The actual failure is a category error:

**There are two populations of thing on a client, they grow at completely
different rates, and the old design gave both the same treatment.**

```
BOUNDED POPULATION — grows when a designer draws a new screen
  the HUD, the inventory panel, the shop, the boss frame, the party frame,
  nameplates, damage numbers, the dialogue box, the minimap
  → maybe 15 of these, ever. Each is real code. That is not sprawl,
    that is just the UI.

UNBOUNDED POPULATION — grows every time content is added
  Gold, HP, MP, EXP, Level, Attack, Defense, Stamina, ShieldHits, every
  seasonal currency, every buff icon, every stat readout
  → hundreds of these over the game's life. Each must cost ZERO modules.
```

Gold is not a *thing on the screen*. Gold is a *number displayed inside* a
thing on the screen. The moment a number gets its own module, its own
lifecycle, and its own wiring, it has been promoted into the bounded
population, and the file count starts tracking content instead of design.

**The rule, stated once:**

> **Screen regions are code. Displayed values are configuration.**

Everything below is an application of that sentence.

This is structurally the same correction the server document already made in
its Part 8 ("Why EconomyService Was Wrong") — a currency is a
`ResourceDefinitions` row, never a Service. Same disease, same cure, other
side of the wire: **generic engine + declarative configuration.**

### The Third Population, Which Is Where Naive Designs Actually Die

There is a case that belongs to neither bucket above and breaks designs that
only account for two:

```
REPEATED INSTANCES — one code module, unbounded instances at runtime
  a nameplate per enemy (40 on screen during a wave)
  a damage number per cosmetic hit (the server document's Part 15 pool)
  a buff icon per active buff
  an inventory slot per item
```

You cannot write a module per enemy nameplate. You write **one** Nameplate
module and a pool keyed by entity. The server document already specified this
for damage numbers specifically; it is not a damage-number pattern, it is the
general shape for every repeated widget, and it is Part 5's `WidgetPool`.

---

## Part 2 — The Boundary — What This Document Does Not Own

> **Status:** SETTLED. Duplicating any row of this table is how the two
> documents drift into looking internally consistent while disagreeing.

| The server document owns | This document owns |
|---|---|
| What the client may report (its Part 13) | Input capture and intent |
| Outbound event payload shapes (its Part 12) | How a payload becomes something visible |
| The eventId correlation contract (its Parts 5, 15) | The client half of that contract |
| Server-clock anchoring | Scheduling playback against that clock |
| The explicit-reject carve-out (its Part 15) | What a reject does to a pending animation |
| Whether a Request is legal | Nothing. The client never decides this. |

**The golden rule, restated because everything here depends on it:** the
client owns no authoritative state. It is a display layer that is allowed to
guess ahead of the server for responsiveness, and required to correct itself
gracefully when the guess is wrong.

Two consequences that get forgotten:

- **There are no client Services, no client Entities, no client Components.**
  Those words mean specific things in the server document, all of them about
  authority over state. The client has no authority, so it needs none of the
  machinery that exists to protect authority. Reusing the vocabulary is how
  the old design ended up mirroring server structure it had no reason to
  mirror.
- **Signal never crosses the wire, in either direction.** The `Signal` class
  in `shared/` works on both sides, with separate instances and separate
  vocabularies that are never wired together. Nothing client-side is ever a
  Signal listener for a server Fact. The wire is EventTape both ways, plus
  replicated Attributes. See Part 3.

---

## Part 3 — The Two Channels — Values You Watch vs. Things That Happened

> **Status:** SETTLED. This split is the spine of the whole client. It
> falls directly out of the server document's Part 12 ("Outbound Traffic")
> and its Part 15 ("The HUD"), and it decides which mechanism every piece of
> incoming information uses.

Everything arriving from the server is one of exactly two kinds, and they get
completely different treatment:

```
CHANNEL A — A VALUE                       CHANNEL B — AN OCCURRENCE
"your gold is 1250"                       "that hit dealt 340, 10 hits, crit"
"this entity's HP is 4200"                "the boss began telegraphing"
"you are INVULNERABLE"                    "the finisher cinematic starts at T"

Transport: replicated Attribute           Transport: inbound EventTape
Arrives:   eventually-consistent          Arrives:   ordered, every one, once
           (intermediate values may
            be skipped — that is fine)
Client:    BINDING (Part 5)               Client:    PRESENTER (Part 6)
Costs:     one config row                 Costs:     one case in an existing
                                                     presenter
Test:      "if I missed an update,        Test:      "if I missed one, the
            does the final value still                player missed something
            look right?"                              that happened"
```

Getting this backwards is expensive in both directions:

- **A value pushed as an occurrence** means the HUD desyncs permanently the
  first time a packet is lost, because nothing re-states the truth.
- **An occurrence watched as a value** means the player silently misses
  things. Attribute replication only guarantees the client eventually sees
  the *final* value — three rapid hits can collapse into one observed HP
  change, and the damage number cascade the game is built around never
  happens.

**HP is the case that proves both halves.** The HP *number*, for bar fill, is
a replicated Attribute — Channel A. The *hit that changed it* — total damage,
hit count, crit — is an inbound EventTape push — Channel B. Same underlying
mechanic, two channels, because the player needs both "my bar is at the right
place" and "I saw that hit land." Anyone who tries to serve both from one
mechanism ends up with either a desyncing bar or invisible hits.

---

## Part 4 — The Five Concerns

> **Status:** PROVISIONAL. The handoff primer named four. `ROUTE` is added
> here because the fourth question in that primer — "something needs to route
> data from the server to ownership on the client" — had no home among the
> other four.

```
ROUTE      inbound EventTape lands here. One flat table, five Presenters.
           Owns eventId correlation and "is this about me."
INPUT      raw input → intent → outbound Request. Owns nothing else.
PREDICT    the pending-actions map, the value overlay, reconciliation.
VIEW       Widgets own screen regions. Bindings connect values to elements.
           Renderers know how to draw a value. Reads only; never decides.
PLAYBACK   animation, VFX, sound, camera. Driven by Presenters, anchored to
           the server clock, configured by content manifests.
```

**Applying the server document's own layer test to `ROUTE`, honestly**, since
its Part 2 warns specifically against inventing a layer to give a concept a
home: the *router itself* is a table lookup and a call — that is a step, not
a layer, and it gets exactly one small file. The substance lives in the
**Presenters**, and a Presenter is not a pass-through: it resolves the
pending-action map, decides whether an event concerns the local player,
fabricates cosmetic cascades from aggregate payloads, and suppresses
competing feedback during a cinematic. Real branching, real state, real work.
The concern survives the test. If a Presenter is ever written that only
forwards its argument unchanged, delete it and route straight to the thing it
was forwarding to.

---

## Part 5 — VIEW — Widgets, Bindings, Renderers

> **Status:** PROVISIONAL, UNBUILT. This is the Part that replaces the
> Manager/Controller/System trio, and the one most likely to need
> adjustment once real UI exists. The Widget/Binding split is the load-bearing
> idea; the renderer vocabulary is a first guess.

### 5.1 — Widget

A **Widget** owns one coherent region of screen. It is the only thing in the
client that owns GUI Instances.

```lua
-- One Widget module. There are maybe fifteen of these in the whole game.
local InventoryPanel = {}

InventoryPanel.template = "InventoryPanel"   -- Content Layer template name
InventoryPanel.layer    = "PANEL"            -- UIRoot layer (5.4)

-- Declarative: the values this widget displays. See 5.2.
InventoryPanel.bindings = {
    { source = "Gold",     element = "Header/GoldLabel",  kind = "text", format = "%d" },
    { source = "BagUsed",  element = "Header/CountLabel", kind = "text", format = "%d/%d", also = "BagMax" },
    { source = "BagItems", element = "Grid",              kind = "list", item = "InventorySlot" },
}

function InventoryPanel:mount(root, subject) end   -- wire interaction, not data
function InventoryPanel:unmount() end              -- drop the bin; nothing else

return InventoryPanel
```

**What a Widget owns:**
- Its instance tree (cloned from a Content Layer template, or built in code).
- Its **local interaction state** — is this panel open, which tab is selected,
  what is hovered. This is genuinely client-local and genuinely stateful, and
  it is the only state a Widget is allowed to have.
- Its input handlers, which produce **intents** (Part 7) and never anything
  else.
- A single cleanup bin. **Every connection, tween, and task the widget creates
  goes in the bin. `unmount` drops the bin and nothing else.** One rule,
  applied without exception, is what prevents the entire class of client
  leaks — the same reasoning behind the server document's insistence that
  `Signal:Connect` return a disconnect handle.

**What a Widget does not own:**
- Fetching data. Bindings do that.
- Deciding anything about game state. It has no authority and no rules.
- Other widgets' instances. A widget never reaches outside its own root.

**Every Widget has a `subject`** — the instance whose Attributes its bindings
read from. Default subject is the local `Player`. A nameplate's subject is
that enemy's Model. A party frame row's subject is that teammate's Player.
This one idea is what lets the *same* bar renderer serve the player's HP bar,
the boss frame, and forty nameplates without any of them knowing about each
other.

### 5.2 — Binding

A **Binding** is one row of configuration connecting a replicated value to an
element inside a widget. It is not a module, not a class, not a file. It is a
row.

```lua
{ source = "HP", element = "HealthBar", kind = "bar", max = "MaxHP",
  tween = 0.18, ghost = { delay = 0.35, duration = 0.55 }, predicted = true }
```

| Field | Meaning |
|---|---|
| `source` | Attribute name, read from the widget's `subject` |
| `element` | Path relative to the widget's root — `"Header/GoldLabel"` |
| `kind` | Which renderer draws it (5.3) |
| `predicted` | Opt in to the prediction overlay (Part 8). Default `false`. |
| everything else | Renderer-specific options |

**Bindings live on the widget that owns the elements, not in one global file.**
This was a real fork in the road and the reasoning matters:

- *Global binding file* — "one file to read every value in the game" is a
  genuine benefit, and it is what the handoff primer sketched.
- *Per-widget bindings* — element paths become short and relative instead of
  long and fragile; a binding's lifetime is automatically the widget's
  lifetime, so unmount unbinds for free with no separate bookkeeping; and a
  widget is readable as one unit (template + bindings + behavior) instead of
  half here and half in a 400-row table.

Per-widget wins on cohesion and on lifetime, which is the one that actually
prevents bugs. The cost — losing the single readable map — is paid back by
the boot validation in Part 10, which walks every binding anyway and can dump
the full map on demand.

**The engine:** at mount, walk the widget's `bindings`. For each row, resolve
`element` against the widget root, resolve `source` against the subject, apply
the current value once, then subscribe to `GetAttributeChangedSignal(source)`
and apply on every change. Put the subscription in the widget's bin. That is
the entire binding engine — it is small, it is written once, and it never
changes when a new value is displayed.

**Zero Signals are involved.** A value changing is not an event that needs
announcing; Roblox already announces it. The handoff primer's warning applies
directly here: if the client ends up declaring twenty Signals, most of them
are bindings in disguise.

### 5.3 — Renderer

A **Renderer** knows how to apply a value to an element in one visual style.
This is the generic engine. The set is small and closed on purpose.

| `kind` | Applies | Options |
|---|---|---|
| `text` | value → `TextLabel.Text` | `format`, `also` (extra sources) |
| `bar` | value/max → fill size | `max`, `tween`, `ghost`, `direction` |
| `icon` | value → `ImageLabel.Image` via a manifest | `manifest` |
| `visible` | truthiness → `.Visible` | `invert`, `fade` |
| `color` | value → a color, via thresholds | `stops` |
| `list` | an array value → pooled child widgets | `item`, `key` |

Six renderers cover the overwhelming majority of a game HUD. Count the
instances the way the server document's Test 3 demands: `bar` alone serves
player HP, MP, stamina, EXP, boss HP, boss shield, nameplate HP, cast bars,
and dungeon timers — well past the "ten or more things sharing real
structure" bar. `text` serves every number on screen. These earn their
genericity honestly.

**`bar` is where the HP-slide behavior lives.** Smooth tween to the new fill,
plus an optional **ghost** — a second fill behind the real one that lags,
showing recently-lost value draining away. That is the "simulate healing and
taking damage" feeling, and it is a property of *bars*, not a property of
*health*. Writing it once means the boss shield bar and the stamina bar get it
free.

**The rule that keeps this from rotting — a renderer earns genericity by
having a second user.** The first time a widget needs some unusual visual
behavior, write it explicitly inside that widget. The second time a *different*
widget needs the same thing, promote it to a renderer or a renderer option.
Never speculatively. This is the client's version of the server document's
Test 3, and it is the specific discipline that stops `bar` from growing
fifteen flags to serve one boss bar that needed phase segments.

**The complementary rule — when a renderer's options stop being readable, it
has become code in disguise.** The server document's Part 2 warns about config
entries containing functions; the client version is a renderer with so many
interacting flags that nobody can predict what a row does. When that happens,
split the variant into its own `kind`, or move it back into the widget that
needed it. A binding row must stay legible to someone who has never read the
renderer.

### 5.4 — UIRoot

One module owns the ScreenGui layer stack and nothing else:

```
WORLD    -- billboard/surface UI: nameplates, world markers
HUD      -- always-on: health, resources, skill slots, minimap
PANEL    -- opened screens: inventory, shop, character
OVERLAY  -- damage numbers, toasts, tooltips
MODAL    -- confirmations, cinematic letterboxing, death screen
```

Widgets declare a `layer` and mount into it. `UIRoot` decides `DisplayOrder`
and `ZIndexBehavior` once, centrally, instead of every widget guessing at a
`DisplayOrder` number and the stacking becoming empirical. Small job, real
job, one file.

### 5.5 — WidgetPool

The generic engine behind every repeated widget (Part 1's third population).

```lua
local pool = WidgetPool.new(Nameplate, { size = 48, layer = "WORLD" })

pool:acquire(key, subject)   -- reuse or create; binds to that subject
pool:release(key)            -- returns to the pool, drops the bin
```

Two independent users, which is why it is an engine rather than a damage
number feature:

- **Value-driven**, via the `list` renderer — buff icons from a replicated
  buff array, inventory slots from a bag array. The renderer diffs the array
  against live children by `key` and acquires/releases the difference.
- **Event-driven**, straight from a Presenter — damage numbers, floating loot
  toasts, hit markers. No value to watch; something happened, so pull one.

The server document's Part 15 damage number pool (80 pre-allocated labels,
steal-oldest on exhaustion, distance cull, 30ms stagger) is exactly one
configured instance of this — not a bespoke system.

---

## Part 6 — ROUTE — The Client Router and the Presenters

> **Status:** PROVISIONAL, UNBUILT. The one-flat-table shape is settled by
> analogy with the server's `EventRoutingRegistry`; the Presenter split by
> domain is the guess.

This is the answer to "something needs to route data from the server to
ownership on the client."

### 6.1 — The Router

Client-side mirror of the server's `EventRoutingRegistry`, same shape and the
same reason: one flat table a developer can open and read end to end, rather
than a folder of one-line modules or a self-dispatching Event object.

```lua
-- client/route/ClientRouter.luau
-- One entry per top-level inbound eventType. Grows by one line when a new
-- domain starts talking to the client — never one line per subType.

return {
    COMBAT    = CombatPresenter.receive,
    RESOURCE  = ResourcePresenter.receive,
    STATE     = StatePresenter.receive,
    CINEMATIC = CinematicPresenter.receive,
    WORLD     = WorldPresenter.receive,
}
```

Dispatch *below* the top level — which subType of `COMBAT` this is — is that
Presenter's own business, exactly as the server document scopes its routing to
the top-level domain only.

**Inbound events reach exactly one Presenter, by direct call.** No Signal fan
out at this edge. The temptation is real — a hit event visibly concerns damage
numbers, hit VFX, a bar flash, a sound, and camera shake, which looks like
textbook one-to-many. But the ordering between those five is not arbitrary,
they need shared context (was this crit, is this the local player, is a
cinematic suppressing feedback), and the server document's own rule applies:
*if you need ordered reactions, the relationship was inherent, not optional.*
So the Presenter calls them, in order, explicitly, in code you can read.

### 6.2 — Presenter

A Presenter turns server facts into presentation. **One per inbound domain.
Five of them. Never one per widget.**

```lua
-- client/route/CombatPresenter.luau

function CombatPresenter.receive(event)
    if event.subType == "HIT" then
        -- 1. Resolve the optimistic prediction, if this was ours
        Prediction.confirm(event.id, event)

        -- 2. Is this about us, and are we allowed to show it right now?
        if Feedback.suppressed(event) then return end

        -- 3. Fabricate the cosmetic cascade from the aggregate payload
        DamageNumbers.cascade(event.targetId, event.totalDamage,
                              event.hitCount, event.isCrit)

        -- 4. Playback
        VFX.playHit(event.targetId, event.isCrit)
        Sound.playHit(event.isCrit)

    elseif event.subType == "TELEGRAPH" then
        Telegraph.show(event.entityId, event.skillId, event.serverTime)
    end
end
```

**If you ever write `HealthBarPresenter`, you have rebuilt the thing this
document exists to prevent.** The count is the test: presenters are bounded by
*how many domains talk to the client* (five), not by how many things are on
screen (fifty). If the number of Presenters starts tracking the number of
widgets, the trio has grown back under a new name.

**When a Presenter gets big, split it inside its own folder, not into more
Presenters.** `CombatPresenter` with twelve subTypes becomes
`CombatPresenter` plus a `combat/` folder of small subType modules it calls —
the same way the server document lets a domain Service dispatch internally
without EventTape learning about it. The public surface stays one entry in the
router.

### 6.3 — Where Client-Local Signal Actually Earns Its Keep

Bindings cover replicated values. Presenters cover inbound events. What is
left for a client Signal is genuinely small, and that is the point:

| Need | Mechanism |
|---|---|
| A replicated value changed | Binding — Attribute + `GetAttributeChangedSignal` |
| A discrete server event happened | Presenter, via the router |
| **A genuinely client-local fact** | **Client Signal** |

Client-local facts are things the server never knows and never needs to:
input mode changed from keyboard to gamepad, a cinematic started locally, a
panel opened, the camera entered first person, the settings menu changed a
value. These are one-to-many, unordered, and genuinely optional — which is
exactly Signal's contract in the server document's Part 11.5, applied to a
different vocabulary.

**Expect fewer than ten of these for the whole game.** If the list grows past
that, re-check each one against the table above; most candidates are Channel A
values in disguise.

---

## Part 7 — INPUT — Intent, Contexts, and the Outbound Edge

> **Status:** PROVISIONAL, UNBUILT.

Input has the same two-population problem as display, and the same fix.

```lua
-- content/input/IntentMap.luau — declarative, one row per binding
return {
    { intent = "ATTACK",      keyboard = Enum.KeyCode.Q,     gamepad = Enum.KeyCode.ButtonX, context = "GAMEPLAY" },
    { intent = "SKILL_1",     keyboard = Enum.KeyCode.One,   gamepad = Enum.KeyCode.ButtonY, context = "GAMEPLAY" },
    { intent = "OPEN_BAG",    keyboard = Enum.KeyCode.B,     gamepad = Enum.KeyCode.DPadUp,  context = "GAMEPLAY" },
    { intent = "CLOSE_PANEL", keyboard = Enum.KeyCode.Escape,                                context = "PANEL"    },
}
```

Rebinding, gamepad support, and touch all become edits to this table. There is
no `AttackInputController`.

**The context stack is the part that is real architecture, not configuration.**
When the inventory is open, `Q` must not swing a sword. When a cinematic is
playing, nothing should respond. A stack of active contexts (`GAMEPLAY` →
push `PANEL` → push `CINEMATIC`) with each intent declaring which context it
belongs to solves this once, centrally, instead of every handler
defensively checking whether some panel is open. Pushing and popping the
stack is a **client-local fact**, and one of the legitimate uses of a client
Signal from 6.3.

**Intent handlers are a small closed set of verbs, not one per key.** `ATTACK`,
`USE_SKILL(n)`, `INTERACT`, `TOGGLE_PANEL(name)`, `MOVE`. A handler's whole
job is: decide nothing, build the Request, hand it to Prediction, send it.

```lua
function Intents.ATTACK()
    local eventId = HttpService:GenerateGUID(false)
    local revert  = Playback.playAttackOptimistically()   -- returns undo
    Prediction.register(eventId, revert)
    Outbound.send({ eventType = "COMBAT", subType = "MELEE", id = eventId, ... })
end
```

Three lines of real work. The client reports **intent only** — never values,
never state. That rule and its full list live in the server document's Part 13
and are not restated here.

**One case worth naming, from the server document's Part 13:** a cosmetic
ability in a place that has no combat is a *pure client feature*. The client
knows what place it is in; it plays the animation locally and **never sends
the request**. It does not send a request that the server politely ignores.
That is not a nuance about mocking — it is the reason the Hub's routing table
having no `COMBAT` entry stays a security property instead of a bug report.

---

## Part 8 — PREDICT — One Pending Map, Not One Per Feature

> **Status:** PROVISIONAL, UNBUILT. The server document's Part 15 calls this
> the least pressure-tested part of the whole architecture, and that
> assessment carries over unchanged. Expect the first real latency case to
> disagree with something here.

The single most important structural claim in this Part: **prediction is one
module, not a capability sprinkled across features.** There is no
`PredictedHealthManager` and no `PredictedGoldManager`. There is one pending
map, one timeout sweeper, one teardown path, and features hand it a closure.

```lua
Prediction.register(eventId, revert, timeout)  -- revert is a closure the
                                              -- feature supplies; Prediction
                                              -- never knows what it undoes
Prediction.confirm(eventId, payload)          -- called by a Presenter
Prediction.reject(eventId, reason)            -- explicit server reject
Prediction.overlay(source)                    -- pending delta for a value
Prediction.clearAll()                         -- player leaving, place change
```

The generic engine is the map, the timeout, and the lifecycle. The declarative
part is the closure. Adding prediction to a new action costs one `register`
call at the call site that already exists.

### 8.1 — The Animation Contract

The full contract lives in the server document's Part 15 and is not
duplicated. The client half:

1. Play optimistically **before** sending anything.
2. Generate the eventId, `register` the revert closure, send the Request.
3. On confirm — let it finish naturally, apply the real payload.
4. On reject — run the revert immediately.
5. On timeout — run the revert. **Every pending action needs a bound.** A
   dropped packet must not leave an animation playing forever.
6. On the player leaving — `clearAll`, as ordinary teardown, not as a special
   case of this pattern.

The explicit-reject message is a deliberate, narrow carve-out from the
server's normal silent-rejection rule, and the reasoning for it is the server
document's, not this one's.

### 8.2 — The Value Overlay

The one place a store-like thing is genuinely justified, and worth explaining
because the obvious version of it is a mistake.

**The mistake first:** a client `Store` that mirrors every replicated
Attribute into a Lua table and re-broadcasts changes. That layer receives X
and immediately emits X unchanged. It is the server document's Command Layer
failure, on the client, and it should never be built. Roblox's Attribute
system *is* the store; wrapping it buys nothing and adds a desync surface.

**What is genuinely not a pass-through:** while a hit is predicted but
unconfirmed, "what HP should I display" is not the attribute value. It is the
attribute value plus the pending delta. Combining those is real work that has
to happen in exactly one place or two features will do it differently.

So: bindings read the raw Attribute by default. A row marked
`predicted = true` reads through `Prediction.overlay(source)` instead, which
returns `attribute + Σ(pending deltas for that source)`. When the real value
lands, the pending delta is dropped and the overlay collapses to the truth
automatically. One flag, zero cost for the ~95% of rows that never predict.

**Predicting a number at all requires the damage formula to be shared code,**
which the server document carves out explicitly and justifies (every input the
formula needs is already something the client legitimately has for display).
If a future formula needs an input the client should not see, that value
cannot be predicted and this pattern does not apply to it.

**Reconciliation pacing, from the server document, restated because it is a
client implementation rule:** the *displayed number* may pop instantly when
corrected — players do not scrutinize a digit. The *bar's animated drain*
should be paced deliberately slower, so the authoritative correction usually
arrives before the bar would have to visibly snap. The `bar` renderer's
`tween` and `ghost` timings are where this is tuned, which is another reason
they are renderer options rather than per-widget code.

---

## Part 9 — PLAYBACK — Facts In, Content Out

> **Status:** SETTLED as a principle (it is the server document's own
> position), PROVISIONAL and UNBUILT as a mechanism.

**The wrong shape:** the server tells the client "play animation X for Y
seconds." Every new animation becomes a server change, and server code fills
up with cosmetic knowledge.

**The right shape:** the server sends what happened; the client decides how to
render it.

```
Server sends:  { type = "SKILL_ACTIVATED", entityId, skillId = "SLASH_3",
                 serverTime = 1234.56 }

Client does:   look up SLASH_3 in its own animation manifest → play it,
               anchored to serverTime
```

The animation manifest is **Content Layer** — the same layer the server
document's Part 6 describes, living in `shared/definitions/`, validated at
boot, never written at runtime. A flashier animation is a content edit that
never touches server code and never touches client code either.

Playback covers animation, VFX, sound, camera, and screen effects. Each is a
small module with a `play(id, context)` surface driven by its own manifest.
The Presenters call them; they never subscribe to anything and never decide
anything.

### 9.1 — The Server Clock Is The Only Clock

Anything that must look the same on two screens at once — the multiplayer
combo, the domain ultimate, the weapon finisher — schedules against the
server's clock, never local receipt time. The payload carries an anchor
(`playAt = serverTime`); each client schedules relative to that anchor rather
than playing on arrival.

This needs to be **one shared shape** that any synchronized broadcast uses,
designed once, not solved separately for combos, ults, and finishers. The
server document flags this as real, known, unfinished design work; the client
half of it is a single `Playback.scheduleAt(anchor, fn)` helper plus the
discipline to always use it. If a client's clock has drifted such that the
anchor is already in the past, play immediately from the correct offset —
never skip and never wait.

### 9.2 — Camera

The camera is client-only, but it is half of a paired feature.

- **Server `CinematicService`** decides a cinematic happens, sets
  `FROZEN`/`INVULNERABLE` via `StateService`, handles opt-in/opt-out, and
  sends the event with a server timestamp.
- **Client camera playback** receives it, hijacks the camera, plays to that
  timestamp, restores.

Keeping the halves separate is deliberate: the state consequences are
server-authoritative, so a player who is IMMOBILIZED during an ultimate stays
immobilized whether or not their camera cooperated. **A client that refuses
the camera does not escape the gameplay effect.** Camera restore must be
unconditional and bounded — a cinematic that errors mid-playback must still
give the camera back.

---

## Part 10 — Boot, Place Scoping, and Validation

> **Status:** SETTLED (it is the server document's Part 13 discipline applied
> unchanged), UNBUILT.

### 10.1 — One Client Tree, Scoped Per Place

`src/gameModes/dungeon/client/` and `src/gameModes/hub/client/` are currently
near-duplicates — two copies of `ClientManager`, `UIManager`, `UIRootGUI`,
`PlayerManager`, the healthbar trio, `CameraSystem`, `InputSystem`,
`TweenUtil`. This is the client version of a problem the server document
already solved, and it gets the same answer:

**One shared client tree. Place membership is declared in the build files, not
expressed by duplicating folders.** Organize by role; let each place's
`.project.json` decide which subset is included.

```
src/client/route/        ClientRouter, CombatPresenter, StatePresenter, ...
src/client/view/         UIRoot, BindingEngine, renderers/, WidgetPool
src/client/widgets/      HUD, InventoryPanel, ShopPanel, Nameplate, ...
src/client/input/        IntentEngine, ContextStack, intents/
src/client/predict/      Prediction
src/client/playback/     Animation, VFX, Sound, Camera
shared/definitions/      AnimationManifest, UITemplates, IntentMap, ...
```

Two things change per place, and neither is a folder: which widgets mount
(`WidgetManifest`), and which router entries exist. Everything else is
identical code in every place, exactly as a Service is never *different* per
place on the server.

### 10.2 — Explicit Mount, Never Folder Discovery

`shared/utils/ComponentLoader.luau` walks a GUI folder for modules exposing
`newManager()` and instantiates them. **It is deleted, not repaired**, along
with `BaseManager` and the Manager/Controller/System trio. They existed to
give every property a home; once properties do not need homes, nothing is left
for them to do.

> **Naming collision worth knowing about:** that `ComponentLoader` has nothing
> to do with entity Components in the server document's sense. Same word, two
> unrelated jobs.

What replaces it is a flat declarative manifest, for exactly the reason the
server document rejected auto-loading twice: folder-discovery makes runtime
behavior depend invisibly on folder layout and naming, so a rename breaks the
game with nothing to grep.

```lua
-- client/WidgetManifest.luau — per place
return {
    { widget = "HUD",            layer = "HUD",    places = { "HUB", "DUNGEON", "FARM" } },
    { widget = "InventoryPanel", layer = "PANEL",  places = { "HUB", "DUNGEON", "FARM" } },
    { widget = "ShopPanel",      layer = "PANEL",  places = { "HUB" } },
    { widget = "BossFrame",      layer = "HUD",    places = { "DUNGEON" } },
    { widget = "DamageNumbers",  layer = "OVERLAY",places = { "DUNGEON" } },
}
```

### 10.3 — Fail Loud At Boot

This is the price of declarative configuration and the reason it stays
trustworthy. Config-driven UI fails *silently* by default — a typo produces a
label that simply never updates, which is close to undiscoverable. So the
client runs the same aggregated boot-check discipline the server document
applies to Signals, effect coverage, and place manifests:

```lua
ClientBoot.validate()
-- every binding's `element` resolves inside its widget's template
-- every binding's `kind` names a real renderer
-- every renderer's required options are present on every row using it
-- every WidgetManifest entry names a real widget module
-- every router entry names a real presenter function
-- every IntentMap `context` is a real context; every intent has a handler
-- every manifest id referenced by playback exists in the Content Layer
-- fails ONCE, listing everything wrong — not a warn() per row
```

A binding row cannot name an Attribute that does not exist yet, because it
legitimately might not (a resource the player has never earned). That one is a
warning, not a failure — but it should still be *reported*, aggregated, at
boot.

**Two-way, same as the server:** a widget declared in the manifest but missing
from the build is a `.project.json` bug and hard-fails. A widget present in
the build but declared for another place is also a failure — that is a leaked
inclusion, and on the client it is a spoiler surface as much as a bug.

---

## Part 11 — Worked Example — The Health Bar, End To End

> **Status:** illustrative. This is the case the whole document was written
> to answer, so it is traced completely.

The question: *something needs to own HealthBar and its health GUI, and handle
sliding the bar so healing and damage feel real.* Here is every piece of that,
and which existing thing owns it.

| Concern | Owner | Cost |
|---|---|---|
| The Frame/Fill/Ghost/Label instances | The `HUD` widget's template | part of one template |
| Getting the current HP number | Binding row, `source = "HP"` | one row |
| Getting max HP for the fill ratio | Same row, `max = "MaxHP"` | same row |
| Smoothly sliding the fill | `bar` renderer, `tween` option | zero — already written |
| Lagging ghost bar showing lost HP | `bar` renderer, `ghost` option | zero — already written |
| Draining early on a predicted hit | `predicted = true` on the row | one word |
| Correcting when the server disagrees | `Prediction` overlay collapse | zero |
| Red flash the instant a hit lands | `CombatPresenter` → `Feedback.pulse` | one line in an existing presenter |
| The damage numbers themselves | `DamageNumbers` pooled widget | zero — already written |
| Low-HP vignette below 25% | Written explicitly in `HUD` | a few lines, **on purpose** |
| Death screen | `StatePresenter` reacting to `DYING` | one case |

The whole of it, on the config side:

```lua
HUD.bindings = {
    { source = "HP", max = "MaxHP", element = "HealthBar", kind = "bar",
      tween = 0.18, ghost = { delay = 0.35, duration = 0.55 }, predicted = true },
}
```

**There is no `HealthComponent`, no `HealthBarManager`, no
`HealthBarController`, and no `HealthBarSystem`.** The instinct that "something
needs to own this" was correct — it just pointed at the wrong noun. What the
game needed was a **bar renderer**, written once, that every bar in the game
uses. HP turns out not to be special at all; it is the first customer of a
generic thing, and the boss shield bar, the stamina bar, and forty enemy
nameplates are customers two through forty-two.

**Note the one row that is deliberately explicit.** The low-HP vignette is
written as ordinary code inside the `HUD` widget, not as a generic threshold
system, because there is exactly one of it. If a second threshold effect ever
appears — a low-stamina desaturation, say — *then* promote it to a `color`
renderer with `stops`, per 5.3's second-user rule. Not before. A document that
never says "write this one explicitly" is a document that is about to
reproduce the problem it was written to fix.

---

## Part 12 — Worked Example — What Adding Things Actually Costs

> **Status:** illustrative, but this table is the acceptance test for the
> whole design. If any row grows, something has drifted.

| Adding | Cost | Modules |
|---|---|---|
| A new currency, shown in the top bar | one binding row + one TextLabel | **0** |
| A new stat readout on the character panel | one binding row | **0** |
| A new bar (boss shield, stamina) | one binding row | **0** |
| A new buff type | a Content Layer entry with an icon | **0** |
| A new animation for a skill | a manifest entry | **0** |
| A new key binding / gamepad support | rows in `IntentMap` | **0** |
| Nameplates for a brand-new enemy type | nothing — it has a subject and Attributes | **0** |
| A new panel (Guild, Crafting) | widget module + manifest row + N binding rows | **1** |
| A new inbound event subType | one case in an existing Presenter | **0** |
| A whole new inbound domain | presenter + one router row | **1** |
| A new visual style no existing renderer covers | write it in the widget; promote on second use | **0–1** |

Compare against the old ecosystem, where a new currency cost **3** and a new
stat cost **3**. The shape of the change is what matters: cost is now linear in
*design decisions* (new screens, new domains) and **constant in content**. The
old design was linear in content, which is the one axis that never stops
growing.

---

## Part 13 — Where This Design Hurts

> **Status:** SETTLED as honest accounting. Every one of these is a real cost,
> accepted deliberately. A design document that only lists benefits is a sales
> pitch.

**Traceability. This is the big one.** In the old design, "who updates this
label?" was answered by grepping `GoldController`. Now the answer is "nothing
does — a row in a table does," and grep will not find it. This is the same
permanent trade the server document makes for its effect table: static
traceability sold for flexibility. Three mitigations, none of which fully pay
it back: bindings live next to the widget that owns the element (short search
radius), boot validation can dump the full binding map on demand, and
`element` paths are literal strings that *are* greppable if you search for the
element name instead of a module name.

**Renderer creep.** `bar` will be asked to grow options forever. The
second-user rule and the legibility rule in 5.3 are the defenses, and they
require actual discipline at the moment of writing, which is exactly when it
is most tempting to add one more flag.

**Presenter god objects.** `CombatPresenter` is the one at real risk, because
combat has the most subTypes and the most feedback. Split into a `combat/`
folder early — before it hurts, not after.

**Prediction is the least-validated thing here.** It has never met a real
latency case. The server document says the same about its own half. Build the
attack case, watch it on a throttled connection, and let it disagree with
Part 8.

**Declarative config fails silently by default.** Part 10.3 exists entirely to
convert that into a loud boot failure. If the boot validation is ever skipped
"to move faster," this design becomes worse than the one it replaced, because
at least a missing Controller threw an error.

---

## Part 14 — Rejected Designs

> Kept because the *test* that catches each mistake is durable, while the
> story of which revision made it is not.

| Rejected | Why it failed | Test that catches it |
|---|---|---|
| `Manager` + `Controller` + `System` per property | 3n growth tracking content, not design; each trio diverging | Count what a new currency costs. More than one row = wrong |
| `ComponentLoader` folder auto-loading | Runtime behavior depends invisibly on folder layout and method names; a rename breaks the game with nothing to grep | Can you find what mounts this by reading one file? |
| `BaseManager` handing a reference down to a Controller | Solved a problem created by the trio's own existence | Does this exist only to serve a structure that is itself rejected? |
| A client `Store` mirroring Attributes into Lua tables | Receives X and emits X unchanged — the Command Layer failure, client side. Attributes already are the store | Does the layer branch, store, or combine anything? |
| A Signal per displayed value | Data binding wearing pub/sub clothes; Roblox already announces value changes | Is this a value change? Then it is a binding, not a Signal |
| One Presenter per widget | Rebuilds the trio under a new name | Are Presenters bounded by domains, or by screen elements? |
| Signal fan-out at the inbound edge | Hit feedback needs ordering and shared context; ordered reactions mean the relationship was inherent | Would it break if two listeners ran in the other order? |
| A generic threshold/effect system for the low-HP vignette | One instance. An engine for one case is more complex than the case | Count the instances. Fewer than two = write it explicitly |
| Per-place client duplication (`hub/client`, `dungeon/client`) | Two copies drift; the divergence is invisible because the names match | Is this a code concern or a build concern? |
| A `NullCombatService`-style client stub for absent domains | The place-absence guarantee is a security property; a client-only feature should simply never send | Is the feature client-side, or is the absence a security property? They are unrelated concerns |
| Client deciding anything about game state | It has no authority; see the server document's Part 13 | Did the client just decide something instead of display something? |

---

## Part 15 — Quick Reference

### "Where does this belong?"

| This thing | Goes here |
|---|---|
| A number on screen | A binding row on the widget that owns the element |
| A bar that slides | A binding row, `kind = "bar"` |
| A new screen or panel | A Widget module + a `WidgetManifest` row |
| A repeated element (nameplate, slot, icon) | One widget module + a `WidgetPool` |
| An array of things rendered as children | A binding row, `kind = "list"` |
| Reacting to something that *happened* | A case in the domain's Presenter |
| Which Presenter an inbound event goes to | `ClientRouter` — one flat table |
| Which sub-handler inside a domain | That Presenter's own business |
| Deciding what animation a skill plays | The animation manifest (Content Layer) |
| Making two clients see the same moment | `Playback.scheduleAt(serverTime, ...)` |
| A key binding | A row in `IntentMap` |
| "Can I act right now?" (menu open, cinematic) | The input context stack |
| Undoing a mispredicted action | A closure handed to `Prediction.register` |
| Panel-open state, hover state, selected tab | The widget's own local state |
| Current HP, current Gold, current anything | A replicated Attribute. Never client state. |
| Z-order / which layer draws on top | `UIRoot` |
| Cleanup | The widget's bin, dropped in `unmount` |

### "Attribute or EventTape?"

| Ask | Answer |
|---|---|
| If I missed one update, does the final value still look right? | Attribute — Channel A, a binding |
| If I missed one, did the player miss something happening? | Inbound EventTape — Channel B, a Presenter |
| Both, for the same mechanic? | Both channels. HP is exactly this. |

### "Config or code?"

| Ask | Answer |
|---|---|
| Does this grow when content is added? | Config. Always. It must cost zero modules. |
| Does this grow when a designer draws a new screen? | Code. One module is correct. |
| How many instances of this visual behavior exist? | 1 → write it in the widget. 2+ → promote to a renderer. |
| Does this config row need a function in it? | Then it is code. Pull it into a renderer or a widget. |

### "Is this a naming smell?"

| Name | Problem | Fix |
|---|---|---|
| `GoldManager` / `HealthBarManager` | A value promoted into the bounded population | A binding row |
| `HealthComponent` | The right instinct, the wrong noun — health is not a category of behavior | The `bar` renderer + one binding row |
| `HealthBarPresenter` | Presenters are per domain, not per widget | A case in `CombatPresenter` / `ResourcePresenter` |
| `UIManager` | Placeholder, not a job. Split it | `UIRoot` (layers) + `WidgetManifest` (mounting) |
| `ClientManager` | Same | `ClientBoot` — mount the manifest, validate, done |
| `PlayerManager` (client) | The client has no player state to manage | Attributes on the Player instance, read by bindings |
| `ClientStore` / `ClientState` | Attributes already are the store | Bindings read Attributes; only `Prediction` overlays |
| `ClientCombatService` | Services own authority; the client has none | `CombatPresenter` |
| `TweenUtil` | Graveyard | Tweening belongs to the renderer that needs it |

---

## Part 16 — Build Order

> **Status:** PROVISIONAL. Ordered so that each step is testable on its own
> and the first visible result arrives early.

**Phase 1 — the skeleton that proves the shape.**
`UIRoot`, `ClientBoot`, `WidgetManifest`, the binding engine, and exactly two
renderers (`text`, `bar`). One widget: `HUD`. One binding row: HP. This is the
smallest thing that demonstrates a value on screen with zero per-value
modules, and it is where the design either holds up or does not.

**Phase 2 — the second channel.**
`ClientRouter` and `CombatPresenter`. `WidgetPool` and `DamageNumbers`. Now
both channels exist and the health bar case from Part 11 is complete except
for prediction.

**Phase 3 — the outbound edge.**
`IntentMap`, the intent engine, the context stack, `Prediction`. Attack
becomes real: intent → optimistic playback → Request → confirm or revert.
This is where Part 8 gets to disagree with reality.

**Phase 4 — breadth.**
The remaining renderers, the remaining Presenters, `InventoryPanel`,
`Nameplate`, playback manifests. All of this is now additive by construction —
if any of it requires touching Phases 1–3, that is the signal something in the
earlier phases was wrong.

**Phase 5 — the delete.**
`BaseManager`, `ComponentLoader`, the healthbar trio, the duplicated
per-place client trees. Do this **last**, not first: they are the working
system until the replacement demonstrably works, and deleting them early
trades a messy client for a broken one.

---

## What This Document Is Not

It is not finished, and it should not be. The handoff primer's instruction
applies to its own successor: **do not pre-write it.** The server document
reached 4,400 lines ahead of any code and had to be compressed afterward.
This one deliberately stops at the decisions.

Every `PROVISIONAL` tag above is an invitation. Build the first real case,
let it disagree, and change the document — the authority is the reasoning, not
the text.
