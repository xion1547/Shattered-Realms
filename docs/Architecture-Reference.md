# Shattered Realms — Architecture Reference
### The Single Source of Truth for How This Game Is Built

> This document exists because you have walked away from this project before
> and come back to find yourself re-discovering decisions you already made,
> re-arguing things you already settled, and rebuilding foundations you already
> laid. That stops here. This document is written to you — future you, six months
> from now, wondering why things are the way they are.
>
> Read it top to bottom when returning after time away.
> Use the section headers to navigate when looking something up mid-development.
> Do not skim it. Every section exists because something went wrong, something
> was hard-won, or you argued about it out loud — sometimes across several
> conversations — until it actually made sense. The length is intentional.
> Confusion that resurfaces more than once in this project's history gets
> written out in full here, on purpose, so it never has to be re-derived
> from scratch again.
>
> **Status note (read this first):** as of this revision, only the EventTape
> and Signal layers exist in code. The Signal layer is **superseded** — the
> document no longer describes what that code does, and the code is what's
> scheduled to change (Part 11, Part 19). Everything else here — Combat,
> Resource, State, Equipment, every Service in the registry, the
> Entity/Component system — is a **should-do**: an architectural decision made
> in advance, on purpose, so that when you build it, you build it once,
> correctly, without re-litigating the decision.
>
> **How to read the status tags.** Every Part carries one, because a settled
> decision, an open question, and an abandoned design all used to read here in
> the same confident, fully-argued voice — which is precisely how you end up
> re-arguing something that was never actually decided.
>
> - **SETTLED** — decided, with reasoning that has survived being attacked.
>   Change it for a better argument, not a new mood.
> - **PROVISIONAL** — the shape is decided but has never met a real use case.
>   Build the first case and let it disagree. Do not extend it in advance.
> - **UNBUILT** — no code exists yet. This is most of this document, by design.
> - **SUPERSEDED** — code exists and this document no longer describes it. The
>   code is the thing that's wrong, and it is scheduled for replacement.
>
> **Neither this document nor the game design document is an axiom.** Both are
> living drafts, deliberately broad and abstract in places, written during the
> development stage of the game's design. The game does not exist yet. When a
> concrete decision (a system, a feature, a piece of code) conflicts with
> something written here, question the document — it may be the thing that's
> wrong, not the code or the new idea. The authority is the underlying
> reasoning, not the text. If reasoning changes, the document should change
> with it, without ceremony.
>
> **This revision incorporates a long, adversarial architecture pass** — the
> EventTape/routing model was redesigned from scratch and re-derived with real
> justification instead of assertion, a State system was added, the Resource/
> Combat boundary around HP was resolved, the client was given a real
> architecture for the first time (prediction, reconciliation, synchronized
> playback), and the security model was corrected to account for a third
> place. Where this revision replaces an earlier model outright, it says so
> explicitly in the relevant Part.
>
> **A rejected design is not deleted, it is compressed.** Where a wrong turn
> taught something real, what gets kept is the *test* that catches it — not
> the narrative of which revision said what. See Part 11's rejected-designs
> table for the pattern. The reasoning is the durable artifact; the history of
> the argument is sediment, and it costs more to maintain than it returns.
>
> **Two lessons that came out of that history and generalize past it:**
> *never infer that a design was intentional or unintentional from what the
> code currently does* — most of this architecture is unbuilt by design, so
> treating an unfinished implementation as proof of intent is exactly
> backwards, and it produced at least one confidently-wrong correction here
> already. And its complement: *a design argued three times and built zero
> times is not settled, it is unvalidated.* Arguing harder does not
> pressure-test a shape. A second real use case does.

---

## Table of Contents

1. The Story of How This Architecture Was Found
2. The Core Philosophy — Generic Engines and Declarative Configuration
3. The Six Roles — Definition, Component, Service, Entity, Pipeline, and Signal
4. A Note on the Word "Event" — Terminology That Must Not Collide
5. Requests, Intentions, and Facts — Where Validation Actually Lives
6. The Five Layers
7. The Entity System — Composition and Component Invariants
8. The Resource System — Why EconomyService Was Wrong
9. The State System — Composable Status Flags, and Why HP Isn't Enough
10. The Service Layer — Where the Game Lives
11. Resolution and Cross-Domain Communication — The Pipeline, Effects, and Signal
12. The EventTape — Ordering, Deserialization, and Routing to Services
13. The Security Model — Places, Absence, and Two-Way Validation
14. The Update Loop — The Scheduler
15. The Client Architecture — Prediction, Reconciliation, and What the Client Owns
16. Error Philosophy, Logging, and Testing
17. Data Migration and Definition Validation
18. Build Order — What to Build and When
19. Known Implementation Bugs Being Fixed
20. Quick Reference — Fast Answers Mid-Development

---

## Part 1 — The Story of How This Architecture Was Found

> **Status:** history. Not a specification — nothing here is a rule. Read it
> for the failure modes, not the conclusions; where a discovery in this Part
> was later walked back, the correction is noted inline rather than deleting
> the enthusiasm that produced it.

This section exists because you kept re-discovering the same pattern without
realizing it was the same pattern. Naming it and tracing its history will
help you recognize it the next time you need to apply it somewhere new —
and will help you resist the temptation to over-apply it when it doesn't fit.

### The First Discovery: The EventTape

You built the EventTape to solve a specific problem: Roblox RemoteEvents fire
in an arbitrary order, and when multiple hits land near-simultaneously in combat,
the processing order matters. A hit that triggers a kill should resolve before
a hit that triggers a buff. You needed ordering guarantees.

**A precision worth stating here, even though it wasn't obvious until much
later (see Part 12's "Ordering Is Arrival Order, Not a Sort"): the guarantee
you actually needed was never "recover the true, fair order between two
different clients" — there isn't one to recover between independent network
connections with different latencies. What you needed was simpler: don't let
anything scramble the order the server actually received things in.**
EventTape delivers exactly that, and nothing more ambitious than that.

Your inspiration was the Turing machine tape — a mechanism that reads an ordered
sequence of symbols and processes them one at a time, without the machine itself
needing to know what the symbols mean. The tape carries the meaning. The machine
carries the behavior.

You built it the same way:

- The **tape processor** (the generic engine) handles buffering, atomic buffer swaps,
  ordering, and deserialization. It knows nothing about what event types exist.
  It never needs to change when a new event type is added.

- The **event type** (the declarative config) is what developers add. A new
  event type declaration, plus one entry in a routing table (see Part 12), is
  all that's needed to add a new kind of traffic. The engine is untouched.

### The Second Discovery: The Signal System

You built a `GlobalRegistry` — a nested table of `Signal` objects — and a
`SignalHelper.AutoConnectAll` function that walks the registry, reads the folder
path implied by the signal's position in the table, finds the matching Manager
module in the filesystem, finds the matching method, and connects them. Automatically.
Zero manual wiring.

Same pattern again:

- The **signal engine** (Signal, SignalService, SignalHelper, AutoConnectAll) is
  generic. It knows nothing about what signals exist or what they announce.
  Adding a new signal never requires touching the engine.

- The **registry** (GlobalRegistry, DungeonRegistry) is declarative. Developers
  add signal entries to a table. The engine discovers and wires them.

**Correction, applied in this revision — the pattern was real, this instance
of it was not.** The auto-wiring is being deleted (Part 19), and the reason
is worth keeping right here next to the enthusiasm that produced it: a
registry path resolves to exactly one Manager method, which means
`AutoConnectAll` structurally supports exactly **one listener per signal** —
the degenerate case a single explicit `:Connect()` line already handles. It
automated the one case that never needed automating, while making runtime
behavior depend invisibly on folder layout and method naming, so a rename
breaks wiring with nothing to grep. Run it through Part 2's Test 3 honestly:
adding a listener explicitly is one line; adding it through the engine is a
registry entry *plus* a correctly-named folder, module, and method. The
engine loses its own test.

What survives is the *discovery* — declarative registry plus generic engine
is a real and repeatedly correct pattern, and it produced EventTape and
ResourceService, both of which hold up. What doesn't survive is the
assumption that finding the pattern once means every subsequent thing shaped
vaguely like it deserves an engine. That assumption is the specific failure
this Part's closing warning is about.

### The Third Discovery: The Resource System

You built ResourceService when you realized that `EconomyService` was the wrong
abstraction — named after *data* (economy) instead of *behavior* (mutation rules).
When you asked "what if there are multiple currencies?" you realized EconomyService
would become a god object. The correct abstraction was a generic engine driven by
a declarative config.

Same pattern, third time:

- The **ResourceService** validates, mutates, persists, and notifies for any resource
  type. It reads the resource's definition and applies the rules. It never changes
  when a new resource type is added.

- The **ResourceDefinitions** declares each resource's specific rules.
  Adding a new seasonal currency costs five lines of config. Zero engine changes.

### What This Means Going Forward — And The Warning

Every time you design a new system, ask: **"Is this the same pattern again?"**
If yes, write the generic engine once and extend it through config.

But a second architect who reviewed an earlier version of this document flagged
the most important warning you need to internalize:

> *Don't make it a religion. Sometimes ComboA.lua, ComboB.lua, ComboC.lua is
> objectively better than ComboService + ComboDefinitions + ComboRuleParser +
> ComboRegistry + ComboBehaviorEngine.*

The pattern is a tool, not a law. Apply it when it genuinely reduces complexity.
Do not apply it speculatively. The test is always: does building the generic engine
now make things simpler, or does it make things more complicated in service of
a future that may never arrive?

This warning turned out to matter in practice, not just in theory. Across several
long working sessions, this document went through several invented layers
that sounded reasonable and were later removed entirely once tested against real
code and against the actual mental model you were trying to build toward:

- A **Command Layer** with a dedicated `CommandFactory` — invented, argued about
  at length, and removed once it became clear it was a layer that only ever
  received something and immediately passed it forward unchanged. See Part 5.
- A **`Signal:SetHandler()` authority-and-mutation model**, where firing a
  signal would route to one authoritative handler responsible for validating
  and mutating, separately from a `NotifyListeners()` broadcast to observers.
  This one has a more tangled history than the others — it was the *original,
  correct* design, got wrongly erased by a later pass that mistook incomplete
  code for abandoned intent, then got seriously reconsidered a second time in
  this revision before being retracted again — this time for a real reason:
  the validated-mutation guarantee it was chasing turns out to come for free
  from an ordinary Service method plus restricting who can fire a signal at
  all, without Signal needing a second concept bolted onto it. See Part 11
  for the full three-pass history — it's kept in detail on purpose, since
  two different wrong turns produced two different plausible-sounding
  "corrections" before the actual reasoning was found.
- A **per-domain EventTape pipeline model** — one RemoteEvent and one ordering
  buffer per top-level domain (Combat, Inventory, Resource...), considered at
  length during this revision. It was rejected because it forfeits the single
  deterministic ordering guarantee EventTape exists to provide, without even
  removing the need for routing — see Part 12.
- A **unified `ModuleResolver` generic engine**, meant to cover Signal wiring,
  Event routing, *and* Component loading behind one abstraction. Rejected once
  it became clear the three don't actually share behavior past "look up a
  module" — one connects a listener, one calls a function expecting a return
  value, one instantiates an object. Three cases, not ten; per Part 2's own
  test, that's the "write them explicitly" bucket, not the "build the engine"
  bucket. See Part 10 and Part 12.
- **Per-currency Services** (`GoldService`, a hypothetical `RaidTicketService`,
  `EventCurrencyService`) — this one slipped in informally, mid-conversation,
  as shorthand in worked examples, not as a deliberate proposal, and needed
  correcting before it became real code. Every currency is already covered
  by the existing generic `ResourceService` + `ResourceDefinitions` pattern
  from Part 1's own Third Discovery — a new currency costs one declarative
  entry, never a new module. See Part 8.
- **`CurrencyService`**, a subtler recurrence of the same mistake one level
  up — carving a service out by `category` instead of by resource instance
  looks like progress over the mistake above, but it isn't: the very next
  question is what houses EXP/Level, then what houses the shield counter,
  and the sprawl is rebuilt with three buckets instead of one-per-resource.
  `category` stays a field in `ResourceDefinitions`, never a service
  boundary. See Part 8.
- **A `GoldManager`/`ResourceManager` wired up purely to relay client
  notification and dirty-tracking** — this one was actually built, mentally,
  before being caught. It used Signal-and-a-reactive-Manager to simulate a
  guarantee (the client will definitely hear about this, the save will
  definitely happen) that Signal was never built to provide, and reproduced
  the exact per-resource duplication of the first mistake above, just one
  layer downstream. Client notification and dirty-tracking are now the
  generic last steps of `ResourceService.grant`/`.drain`/`.set` themselves —
  see Part 8's "What Client Notification Is Not" and Part 11's "Direct Call,
  Registry, or Signal."

Catching these on paper, before code was built around them, is exactly
what this document is for.

---

## Part 2 — The Core Philosophy — Generic Engines and Declarative Configuration

> **Status:** SETTLED. This is the reasoning every other Part is an
> application of. Test 3 in particular is the one most often skipped.

### The Pattern Stated Explicitly

```
Generic Engine          +       Declarative Configuration
──────────────────              ──────────────────────────
Does the work                   Describes what work to do
Written once, stable            Grows constantly as the game grows
Knows nothing specific          Knows everything specific
Changes only when the           Changes whenever new content,
  category of behavior changes    new types, or new rules are needed
```

### The Three Tests For Any New System

Before writing a new system, answer these three questions.

**Test 1: What is the generic part?**
What behavior repeats identically regardless of the specific case?
What code would be duplicated if you handled each case separately?
That repetition is your engine. Identify it. Extract it. Write it once.

**Test 2: What is the declarative part?**
What changes between specific cases?
That specification is your config. Make it as simple and readable as possible —
legible to someone who did not write the engine.

**Test 3: Does a generic engine actually reduce complexity here?**
A generic engine is only worth building if it makes adding future instances
*simpler* than just writing them explicitly. If you have three combo types that
are wildly different from each other, three files is simpler than an engine
that has to accommodate all three. Count the cases. If the answer is "two or
three specific things that don't actually share behavior," write them
explicitly. If the answer is "ten or more things with a clear shared structure,"
build the engine.

### When This Pattern Should NOT Be Applied

**When behavior is genuinely unique:**
A boss finisher cinematic is not a generic resource mutation. Write it explicitly.
The pattern is for things that genuinely repeat, not things that superficially look similar.

**When config entries start containing functions:**
If ResourceDefinition entries start having `onGrant = function(entity) ... end`,
the config has become code in disguise. Pull that behavior back into the engine as
a recognized behavior category (like `onFloor = "TRIGGER_DEATH"`), or accept that
this case needs its own dedicated system.

**When the engine accumulates per-instance special cases:**
If ResourceService has `if resourceId == "Gold" then` blocks, the abstraction failed.
The engine handles categories. If it's handling instances, the design is wrong.
This is exactly what nearly happened with HP — see Part 8 and Part 9 for how
that was resolved without ResourceService ever learning what a shield or an
invulnerability window is.

**When you're building a layer to hold something that has nowhere else to go:**
This is the failure mode that produced the Command Layer mistake described in
Part 1 and Part 5, and the per-domain EventTape pipeline mistake described in
Part 12. Sometimes a new layer gets invented not because a real
repeating behavior was found, but because a *concept* feels like it deserves
a home, and building a layer feels like giving it one. The test: does anything
actually live in this layer that isn't just passing through unchanged from the
layer before it? If a layer's entire job is "receive X, immediately produce Y,
nothing else ever happens here, nothing is ever stored or branched on," it is
not a layer. It is a naming exercise wearing architecture's clothes. Fold the
transformation into whichever real, already-necessary step is doing adjacent
work.

**When a data object reaches upward to call the thing that's supposed to react to it:**
This is a second, more specific version of the same failure mode, and it
deserves naming on its own because it nearly happened once already — see the
self-dispatching Event discussion in Part 12. A shared, dumb data object (an
Event, a Command payload, a DTO) knowing how to call the Service that consumes
it feels like it removes a layer of ceremony. It actually just relocates the
routing decision into the wrong file, and — worse, in a Roblox client/server
codebase specifically — risks making a `shared/` object depend on a
server-only Service, which either breaks on the client or forces the Service
to become dual-environment-safe just to satisfy a data object's convenience.
Routing decisions belong in a small, explicit, server-side table (see Part 12),
never inside the data object being routed.

### Closed Vocabularies — Never Compare Bare Strings

**If a value comes from a fixed set, it gets an enum, and call sites use the
enum. Never a string literal.**

This is not style. It is the difference between a mistake that fails at the
call site and one that travels:

```lua
-- A typo here is nil. It fails immediately, at the line that is wrong,
-- with a message naming what was expected.
Events.create(Events.Type.COMBAT, Events.SubType.COMBAT.MELE, {...})

-- A typo here is a perfectly valid string. It serializes, crosses the wire,
-- and fails on the server -- or worse, silently matches nothing and the
-- action just never happens.
Events.create("COMBAT", "MELE", {...})
```

The second one is the expensive kind of bug: the error surfaces far from its
cause, in a different process, possibly minutes later, and "nothing happened"
is the hardest symptom to trace.

**The rules, concretely:**

- **One declaration, or a validator — never two hand-maintained copies.**
  Prefer deriving. Where deriving is impossible because the generated thing
  is an *API surface* — a generated method is invisible to autocomplete, and
  discoverability is the whole point of having one — hand-write it and add a
  boot check that the two agree. `EventBuilder`'s `:withX()` methods are
  hand-written for exactly that reason, and `EventRegistry.validate()` asserts
  every schema field has one and every one maps to a field. Checking
  the invariant is a legitimate alternative to generating around it; a second
  hand-maintained copy with nothing checking it is not.
- **Freeze them.** `table.freeze` turns an accidental write into an error
  instead of a shadowed value nobody notices.
- **The enum is the door, not a suggestion.** If a constructor accepts a raw
  string that happens to match, people will pass raw strings. Validate against
  the vocabulary and reject anything outside it — see `EventRegistry.isValid`
  / `hasSubType`, `StateService`'s declared flag set, and `SignalService`'s
  vocabulary check.
- **Membership tests are functions, not table indexing.** A read-only
  metatable that raises on unknown keys makes `Enum[x] == nil` throw before it
  can evaluate — this exact bug made `Event`'s validation branch unreachable.
  Expose `isValid(x)` and let it use `rawget`.

**Where this already applies:** each event class's `SubType` (event
taxonomy), `MessageKind` and `RejectReason` (the wire protocol),
`RemoteEventsEnum`, `StateService`'s four flags, `ResourceDefinitions` ids,
and the effect-handler labels in Part 11.2. Any new closed set joins them.

**The one exception, stated so it is not mistaken for laziness:** content ids
that live in a definitions table are already validated against that table at
boot (Part 17), so a string key there is checked by a different mechanism.
`ResourceDefinitions.Gold` does not also need an enum wrapper.

### Domain Boundaries: Conceptual Coupling vs. Contingent Coupling

Part 10 gives the test for whether something is its own domain-level Service or
a sub-service nested under a parent: *could this thing's logic exist meaningfully
without the parent domain?* That test needs one further sharpening, because it's
easy to answer it wrong by only looking at what's currently built.

Ask **why** the answer is "no" (if it is). There are two different reasons
something might currently have no life outside its parent domain:

- **Conceptual coupling** — the thing is *definitionally* part of its parent, and
  always will be, no matter how the game's content evolves. A skill is a combat
  concept by definition; there is no version of this game where "skill" stops
  meaning "something used in combat." This is a safe case for nesting.
- **Contingent coupling** — the thing merely *happens* to only be used by one
  domain so far, because that's what's been designed. A buff is fundamentally
  "a temporary modifier" — a concept with no inherent tie to combat — and the
  fact that every current example is combat-scoped is a fact about today's
  content, not about what a buff *is*.

When the coupling is contingent, default to keeping the thing a **peer domain**
that the current single caller happens to depend on, rather than nesting it.
This costs nothing extra to build — it's the same code either way, the only
difference is which folder it lives in and whether a future second caller is
structurally allowed to reach it without violating a boundary. Peer-by-default
under genuine uncertainty preserves options for free; nesting under genuine
uncertainty forecloses them for free. Only nest when the coupling is
conceptual, because conceptual couplings don't need to be undone later.

This is why `BuffService` is a peer domain in this revision (Part 10), not
nested under `CombatService`, even though every currently-designed buff is
combat-scoped.

**A related but distinct test, for a different question entirely, lives in
Part 11.4: "Direct Call, Table, or Signal."** This one decides where code
*lives* (nested sub-domain vs. peer domain), decided once per domain, at
design time. That one decides how two *already-separate* peer domains talk
for a specific interaction (direct call, a registry, or a Fact), potentially
decided differently for every pair of domains that ever need to communicate.
They rhyme — both are ultimately asking "how tightly does this really need
to be coupled" — but conflating them is exactly what produced the
`GoldManager` mistake documented in Part 8.

---

## Part 3 — The Six Roles — Definition, Component, Service, Entity, Pipeline, and Signal

> **Status:** SETTLED. The shortest Part and the one to have memorized
> cold. If a piece of code seems to blur two roles, come back here first.

This is the shortest part of the document and the most important one to have
memorized cold, because every other part is an elaboration of it. If you ever
find yourself unsure which file a piece of logic belongs in, come back here
first before anywhere else.

```
Definition:
  - owns the idea, not the instance
  (read-only, one per type, forever — never mutated, never aware that any
   instance exists at all. An Entity reads it once, at construction, to
   seed its starting values — see Part 6)

Component:
  - owns invariants
  - owns local consistency
  (a fact that is true about itself alone, checkable without looking at
   anything else in the game — "am I full?", "is my hp within bounds?")

Service:
  - owns game rules
  - owns orchestration
  (a fact that requires looking at more than one thing at once — "is this
   player allowed to pick this up right now, given their zone and quest
   state?" — and the actual sequence of steps that makes something happen)

Entity:
  - owns state
  (a container assembled from Components; has no logic of its own beyond
   what its Components enforce)

Pipeline:
  - owns execution order
  (a fixed, ordered sequence of steps that read and mutate a shared
   context object for one operation — never a rule, never state of its
   own; see Part 11's `DamageResolution` pipeline)

Signal:
  - announces completed state changes
  (nothing more — no routing, no validation, no rejection; see Part 11)
```

### Definition vs. Entity — The Confusion That Kept Recurring

This distinction is pinned down here, explicitly, because it got confused
more than once across real conversations about this document, and every
time it did, the confusion traced back to the same root cause: Definition
and Entity can both look, at a glance, like they're "describing what a
thing is." They are not doing the same job, and the difference isn't
subtle once it's named correctly:

**Definition is the idea. Entity is the occurrence.**

A Definition (`GoblinTemplate`, `ResourceDefinitions.Gold`) doesn't know how
many instances exist, doesn't track any of them, and isn't aware anything
has ever been built from it. It has no "current" anything — only starting
values, floors, ceilings, and behavior tags that apply equally to every
instance that will ever be spawned from it. It isn't "the abstract version
of a goblin" in any active sense — it's inert data sitting in a table,
waiting to be read.

An Entity is the only thing in this whole model that can say "I exist,
right now, at this specific value, in this specific spot in the game." It's
created when something spawns, destroyed when that thing is removed, and
every Service, Signal, and piece of replicated state that refers to "this
goblin" is holding a reference to the Entity — never to the Definition. The
Entity touches its Definition exactly once, at construction, to read its
starting values. After that moment the Definition doesn't hear from it
again — the Entity's state is entirely its own from then on, changing every
time it's hit, healed, buffed, or moved, while the Definition it was built
from sits untouched, still describing the same starting point for the next
instance spawned from it.

If you ever catch yourself asking "does this belong in the Definition or
the Entity," the test is: **does it exist once, per type, forever, unaware
of any instance — or does it exist once per spawned instance, and change
while the game is running?** The first is a Definition. The second is an
Entity (or one of the Components an Entity is assembled from).

|  | Definition | Entity + Component | Service |
|---|---|---|---|
| What it is | static rules / starting values | live, current, per-instance state | shared logic |
| How many exist | one per **type** (one `GoblinTemplate`, period) | one per **instance** (one per goblin actually spawned) | one for the **whole game** |
| Changes at runtime? | No — read-only after boot (Part 6) | Yes — constantly, during play | No meaningful state of its own |
| Analogy | the blueprint | the physical thing built from it | the factory process that operates on any physical thing you feed it |

Six roles, but only five of them participate in runtime causation — a
Definition's only involvement is the one-time read at construction described
above; it is never part of the request-to-mutation-to-announcement chain
below, and is never touched again once an Entity has been built from it:

```
A Service decides something is allowed (game rules)
        ↓
A Service calls a typed mutation method on an Entity's Component —
  for an operation complex enough to need one, this step runs through a
  Pipeline first (Part 8), but the Pipeline only orders execution; the
  Service is still what decided to run it and what the result means
        ↓
The Component checks its own local invariant and either applies the
  change or refuses it (component-level truth only — no game rules here)
        ↓
Once the Service has confirmed the mutation actually happened, the
  Service fires a Signal
        ↓
The Signal announces the confirmed fact to whoever is listening
```

**The decision rule, stated once, explicitly, so it never has to be
inferred from examples:** only a Service (or a Pipeline step a Service has
registered) may decide a game rule — whether something is allowed, how much
of something should happen, whether an action is legal right now. A
Component never branches on a game rule; it only ever checks its own local
invariant and applies or refuses a change on that basis alone. A Signal
never decides anything — it fires after a decision is already final,
carrying the result, not making one. A Definition never decides anything
either — it is read, never consulted as an authority; the Service reading
it is the one making the decision, using the Definition as input. If you
ever aren't sure who's allowed to decide something, this is the rule: find
the Service (or the Service-registered Pipeline step) responsible for that
domain. If there isn't one yet, that's a gap to fill, not a reason to let a
Component or a Signal make the call instead.

Every other part of this document — the Entity/Component split in Part 7, the
Service registry in Part 10, the Signal contract in Part 11 — is this same
four-line shape, examined in more detail for one role at a time. If a piece
of code seems to blur two of these roles (a Component making a cross-entity
decision, a Signal deciding whether something is allowed, a Service reaching
directly into another Entity's Component instead of going through that
Entity's owning Service, or a Definition being written to at runtime instead
of just read), that is the signal something has drifted and needs to be
pulled back to its correct role.

---

## Part 4 — A Note on the Word "Event" — Terminology That Must Not Collide

> **Status:** SETTLED. Terminology only — but the collision it prevents
> is real and cost real confusion before it was named.

This section exists because the word "Event" was argued about, at length,
across multiple conversations, and the confusion kept resurfacing. It is
pinned down here, early, so it never has to be re-argued.

There are **three different things** that could reasonably be called "an
event" in this codebase. They are not the same thing, and the fix is simply
to never use the bare word "event" without being clear which one is meant.

**1. `RemoteEvent`** — a built-in Roblox API class. This is Roblox's name,
not yours. You cannot rename it and should not try to. It is the transport
mechanism client and server use to send raw data to each other. It has no
opinions about ordering, trust, or meaning. Always refer to it by its full
name, `RemoteEvent`, never shortened to "the event." As of this revision,
there is exactly **one** `RemoteEvent` carrying all client/server traffic —
see Part 12 for why.

**2. An `Event` object (and its subclasses — `AnimationEvent`, and future
types like `AttackEvent`)** — the typed, self-validating, self-serializing
class hierarchy living in `shared/eventTape/event/`. This is what EventTape
carries and what `EventDeserializer` reconstructs from raw wire data. Its
name refers to what it represents at the transport layer — a unit of typed
data flowing through the tape — not to a claim about whether what it
represents has been confirmed or validated yet. An `Event` object can
represent something that hasn't happened yet (a player's attack input,
still needing validation) just as easily as something that has (an outbound
effect cue). The class itself is neutral about that; see Part 5 for where
the actual confirmed/unconfirmed line is drawn.

**3. `EventTape`** — the name of the ordering/throughput engine itself,
described fully in Part 12. Its name refers to *what it does* (reads an
ordered tape of symbols, Turing-machine style, per Part 1) — not to a claim
that everything flowing through it has been confirmed. The name was kept,
deliberately, over more "accurate" alternatives that were considered and
rejected, because a developer seeing `EventTape` sitting next to a folder
that handles RemoteEvent traffic will correctly guess what it does.

**The rule going forward:** never write or say the bare word "event" without
context making clear which of the three you mean. In code, this means:

- Roblox's networking object is always written `RemoteEvent`, never `event`.
- The typed class hierarchy is referred to as `Event` (capitalized, matching
  its actual class name) or by its specific subclass name (`AttackEvent`).
- The engine is `EventTape`, referred to by its full name.
- Signal's own broadcast, once it fires, is called exactly that — "the Signal
  fired" or "a Signal announcement" — not "an event," to avoid re-colliding
  with meaning #2 above. Signal does not carry `Event` objects; by the time
  a Service fires a Signal, the `Event` object that originally triggered the
  Service call has already served its purpose and been discarded. See Part 11.

If you ever catch yourself writing a comment like `-- the event fires and
notifies everyone`, stop and ask which of the three meanings you actually
mean, and name it explicitly.

**A fourth naming collision to watch for, introduced this revision:**
`StateService` (Part 9 — composable status flags like FROZEN, DYING,
INVULNERABLE) and `StatService` (Part 10 — final stat computation, attack/
defense/speed) are one letter apart and do fundamentally different jobs.
Never abbreviate either in speech or comments to just "State" or "Stat"
without the full word — the near-identical spelling is a standing invitation
to misread one for the other mid-refactor.

---

## Part 5 — Requests, Intentions, and Facts — Where Validation Actually Lives

> **Status:** SETTLED as a model, UNBUILT. The three-tier split and the
> "validation lives in the Service method" conclusion have both survived
> being attacked; none of the code exists.

This section replaces an earlier version of this document that placed this
same distinction on Signal itself — describing `Signal:Fire()` as delivering
an unconfirmed "command" to a single handler, separately from a broadcast of
confirmed results. That framing is gone. It never matched your actual Signal
implementation, and more importantly, it was never the model you were actually
building toward — see Part 11 for the full explanation of the correction, and
the note at the top of this document.

What survives, fully intact, is the underlying distinction — it just lives at
a different place in the pipeline now: **at the Service call boundary, not on
Signal.**

### The Story of the Command Layer — Why It Isn't In This Document

An earlier draft of this document included a fourth architectural layer: a
**Command Layer**, with typed Command objects, a `CommandFactory` to build
them, and a dedicated folder for them — sitting between the Remote Layer and
the Service Layer.

That layer was removed. Not renamed — removed. The reasoning, in full, because
it is exactly the kind of thing this document exists to preserve so it never
has to be re-derived under pressure at 2am:

The Command Layer was invented to solve a problem that didn't actually exist.
Under close questioning, "deserialize the packet" and "construct the thing
that represents intent" turned out to be the same step, described twice, with
two different names. `EventDeserializer` already does the full job of turning
raw wire data into a typed, self-validating `Event` object. A separate
`CommandFactory` sitting after it would have received an object with nowhere
further to transform it — it would have existed for one line of code and
then been discarded. That is the layer-with-nothing-in-it failure mode named
explicitly in Part 2.

### Three Tiers, Not Two

The two-way split above (something requested versus something confirmed) is
enough for player-originated actions on its own, but it under-describes one
real case: enemies and bosses. A server-authoritative AI system deciding to
attack isn't *requesting* permission the way a player is — it already has
authority, because it already lives on the server. Treating its decision with
the exact same suspicion as a player's click is the wrong model. Treating it
with zero scrutiny at all is also wrong, because bugs happen even in trusted
code. The resolution is three tiers:

```
REQUEST                    INTENTION                   FACT
(client-originated)        (server-AI-originated)      (resolved outcome)
──────────────────         ──────────────────         ──────────────────
"I would like to attack"   "The boss decided to        "200 damage was
                             attack"                     dealt, entity mutated"
Adversarial — assume        Trusted — assume good       Not validated at all.
the client might be lying   intent, but a bug could     This is reality being
                             still produce nonsense      recorded, not judged.
Validated for LEGALITY,     Validated for SANITY,       No check applies — the
inside the Service:         inside the Service:         Entity has already been
"am I allowed to do         "does this make sense?"     mutated. A Signal is
this right now?"            (target isn't nil, damage   fired to announce it.
                             isn't negative)
```

**Where each tier physically lives in the pipeline:** a Request or an
Intention becomes a typed `Event` object (see Part 4), gets routed by
EventTape (Part 12) to the Service method that owns that domain, and that
Service method is where the legality or sanity check actually happens —
`return false, reason` and stop, or proceed. **Signal is never part of this
step.** Signal is only ever touched afterward, once the Service has already
decided to proceed and the Entity has already been mutated — at which point
there is nothing left to validate, only something to announce. A Fact is not
"delivered to Signal for approval." A Fact is what a Service creates when it
calls `Signal:Fire()` after the fact is already true.

### Every Event Object Carries an ID — Always

Every `Event` object built by `EventDeserializer` should carry a unique ID,
generated either at creation on the client or assigned by the server on
receipt:

```lua
-- Conceptually, the data an AttackEvent carries
{
    id        = generateUUID(),   -- e.g. "a3f9-12bc-..." unique per instance
    eventType = "COMBAT",
    subType   = "MELEE",
    data      = { actorId, targetId, skillId, hitsPerTarget },
    timestamp = os.time(),
}
```

When you are debugging at 2am and a hit registered when it should not have,
every log line that references `id = "a3f9-12bc"` leads you to the exact
Event that caused it. Without IDs, you are matching timestamps and praying.
With IDs, you trace the chain in seconds. This costs nothing to add now.

**This ID has a second job as of this revision, on the client:** it is the
correlation key between an optimistically-played client animation and the
server's eventual confirmation or rejection of it. See Part 15 for the full
client-side contract — the short version is that the client keeps a small
map of `eventId → currently-playing animation handle`, and resolves it when
the matching server response arrives.

### The Telegraph/Execute Pattern — Solving Perceived Latency for Server-Authoritative NPCs

Bosses and enemies live entirely on the server, which is correct and
necessary for security (see Part 13), but naive server authority creates a
specific bad feeling: the server decides an attack landed, replication takes
~100ms, and the player perceives being hit before they ever saw anything
happen. The fix is **not** to make NPCs client-authoritative, and it does
**not** route them through the client's Request pipeline. Instead, a single
NPC attack decision produces **two separate Service-driven mutations, each
announced by its own Signal**, in sequence:

```
BossAIService decides "I will swing" at server time 0.0s
        ↓
BossAIService mutates the boss's StateFlags (Part 9) to include TELEGRAPHING
        ↓
Signal:Fire() announces the telegraph — clients see a warning: red
  indicator, windup animation, audio cue, ground marker. This is not
  decoration, it is latency compensation.
        ↓
~1.0–1.2s later, server time reached: BossAIService calls CombatService
  to resolve the actual attack
        ↓
CombatService validates (sanity-checks, since this is an Intention, not
  a Request), calculates damage, mutates the defending Entity's Vitals
        ↓
Signal:Fire() announces the confirmed hit — damage numbers, sounds,
  reaction animations
```

Both steps follow the exact Part 3 shape (Service decides → Entity mutates →
Signal announces) — there are simply two of them, back to back, with a
deliberate delay between. The player has time to react between the telegraph
announcement and the resolution.

**Ordering correction:** an earlier revision of this section called
telegraphs "not decoration, latency compensation," and the paragraph above
once claimed windups exist to make server authority feel fair. That
over-corrects against "purely aesthetic" and lands somewhere misleading.
**Telegraphs exist for combat readability first** — you see the windup, you
recognise which attack it is, you choose dodge or parry. That loop is the
skill of the genre and works identically in single-player games with zero
latency; Dark Souls and Monster Hunter did not invent windups for networking
reasons. The latency benefit is a genuine and load-bearing *consequence* —
it is what licenses resolving NPC attacks with no rewind (see
`HitDetection.md`) — but it is not the purpose. `BossAIService` (Part 10) owns
producing both mutations; `CombatService` still owns resolving what the
Execute step actually does, exactly as it does for player attacks.

### The Full Flow, Restated End to End (Player-Originated Example)

```
Client presses attack button
  ↓
Client plays the attack animation immediately, optimistically (Part 15),
  and records eventId → animation handle in its pending-action map
  ↓
RemoteEvent fires (client reports INTENT ONLY, per Part 13) — one Event,
  even if the skill will ultimately produce multiple cosmetic hits (Part 8)
  ↓
EventTape receives the raw packet, orders it, buffers it
  ↓
EventDeserializer reconstructs the typed Event object (AttackEvent),
  which validates its own shape (correct field types, non-empty id) —
  this is the Event's own local self-consistency check, not a game rule
  ↓
EventTape's routing step (Part 12) looks up eventType "COMBAT" and
  calls CombatService.OnAttack(event) directly — a plain function call,
  not a Signal
  ↓
CombatService.OnAttack(event)
  → validate: skill unlocked? cooldown clear? target in range? latency window?
  → if invalid: log warning with event.id, send an explicit reject message
    back to the client so it can cancel the optimistic animation quickly
    (see Part 5's note above and Part 15 — this is the one deliberate
    carve-out from "rejected Requests get no response")
  → check StateService (Part 9): is the target INVULNERABLE or is this
    entity DYING? If so, the damage resolves to zero — stop here.
  → check the boss's own Attack-Based Shield hit-counter (Part 9), if any
  → calculate: damage formula, one roll for the whole activation, not one
    per cosmetic hit (Part 8)
  → mutate: EnemyEntity vitals via ResourceService.drain() with the final,
    fully-resolved amount (ResourceService's own drain() already pushes
    the outbound EventTape confirmation and marks Gold/HP/etc. dirty as
    its own inherent last steps — Part 8 — nothing here has to ask for that)
  → check: dead? trigger kill flow
  → push CombatService's own outbound EventTape confirmation directly —
    { totalDamage, hitsPerTarget, isCrit, newHp } — this is what the client's
    Damage Number System (Part 15) actually consumes, inherently, as part
    of what "a hit landed" already means. Not a Signal. Signal never
    crosses the client/server boundary at all — nothing client-side can
    ever be a Signal listener, only a consumer of an outbound EventTape
    push or a watcher of a replicated Attribute.
  ↓
Only now, after everything above has already happened and already reached
  the client on its own: Signal["Combat.OnHit"]:Fire(attacker, target,
  totalDamage, hitsPerTarget, isCrit, newHp) — ONE fire per activation, for
  genuinely optional server-side reactions only
  ↓                        ↑ the only Signal call in this entire flow, and
  │                          notably not the mechanism anything above depended on
  ├── ComboDetector       → checks 200ms combo window
  └── AchievementService  → checks combat milestones
```

Every listener sees confirmed, validated state. None of them validate
anything, and none of them are load-bearing — the client already knows what
happened by the time this fires. The Service already did all of that,
before Signal was ever touched. Listeners react to a fact that's already
fully true. They do not judge, and nothing downstream is waiting on them.

---

## Part 6 — The Five Layers

> **Status:** SETTLED. The layer boundaries have held through every
> revision. The concurrency rules assume single-threaded execution — see
> the Parallel Luau caveat at the end of the Service Layer rules.

Every line of code belongs to exactly one layer. If you cannot place something,
the design of that thing is wrong — not the layer model.

Note: this was Six Layers in an earlier draft, which included a separate
Command Layer between Remote and Service. That layer has been removed — see
Part 5's full explanation of why.

Note: Signal is intentionally **not** one of the five layers below. It is a
cross-cutting capability that the Service layer uses, the same way the
Service layer uses DataService — described in its own Part (11) because
enough Services use it that it deserves full treatment, not because it is a
pipeline stage data physically passes through on its way somewhere.

### Layer Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│  0. CONTENT LAYER  (not "code" — but needs a home)                 │
│                                                                     │
│  Game content declared as data. Read by engines, never modified     │
│  at runtime. Defines what exists in the game world.                 │
│                                                                     │
│  ResourceDefinitions, HurtboxDefinitions, BuffDefinitions,          │
│  LootTables, DungeonDefinitions, ItemDefinitions                    │
│                                                                     │
│  ONE FILE PER THING, walked at boot (2026-08-23):                   │
│    definitions/enemies/Goblin.luau    stats, hp, loot, hurtbox      │
│    definitions/skills/BasicSwing.luau volume, clip, score           │
│  Adding one is ONE FILE and ZERO code edits -- boot walks the       │
│  folder, so there is no index to forget. `boot/DefinitionLoader`    │
│  resolves and validates, aggregated into one failure naming the     │
│  file. Replaces the single `EnemyTemplates` table.                  │
│                                                                     │
│  A volume in a definition is a PLAIN TABLE, never a resolved one:   │
│  `serverShared` reaches every place, `HitVolume` exists in one, and │
│  requiring upward would fail ON LOAD in a place without combat.     │
│                                                                     │
│  Lives in: src/serverShared/definitions/ -> ServerStorage.Shared    │
│    NOT ReplicatedStorage. Definitions are game data (drop rates,    │
│    boss HP, floors/ceilings) and anything in ReplicatedStorage can  │
│    be dumped by a client -- see Part 13's replication boundary.     │
│    Client-facing content (animation manifests, item display names)  │
│    is a separate, deliberately small set in ReplicatedStorage.      │
│  Rule: validated at startup before any gameplay begins.             │
│  Rule: never written to at runtime.                                 │
│  Rule: adding a new enemy type = one new definition entry.          │
│  Rule: a weapon/skill's cosmetic hit count (Part 8) lives here —    │
│    it is declared data, never computed at runtime.                  │
└────────────────────────────────┬────────────────────────────────────┘
                                 │ read by engines at boot
┌────────────────────────────────▼────────────────────────────────────┐
│  1. REMOTE / EVENTTAPE LAYER                                        │
│                                                                     │
│  Client-facing surface, plus the server's own path for producing    │
│  its own Intentions (e.g. BossAIService). Captures raw input via    │
│  ONE centralized RemoteEvent (Part 12 — not one per domain).        │
│  EventTape buffers and orders it. EventDeserializer reconstructs    │
│  the typed Event object. A routing step (Part 12) then calls the    │
│  correct top-level domain Service method directly — a plain         │
│  function call, never a Signal. Dispatch below the top-level        │
│  domain (e.g. which sub-service within Combat handles a given       │
│  subType) is that domain's own business, not EventTape's — see      │
│  Part 12. Contains zero game logic. Trusts nothing from the client. │
│                                                                     │
│  Lives in: client scripts, shared/eventTape/, server/eventTape/     │
└────────────────────────────────┬────────────────────────────────────┘
                                 │ direct function call, routed by eventType
┌────────────────────────────────▼────────────────────────────────────┐
│  2. SERVICE LAYER                                                    │
│                                                                     │
│  Where the game lives. All rules, validation, orchestration,        │
│  entity mutation. The only layer that:                              │
│    - mutates entities                                               │
│    - calls another Service directly (or through the effect table,   │
│      when the target varies by content) whenever the relationship   │
│      is inherent — see Part 11.4, Direct Call, Table, or Signal.    │
│      This is the common case, not Signal.                           │
│    - fires Signals only for genuinely optional reactions — a Fact,  │
│      always AFTER a successful mutation, never before, never to     │
│      route or ask permission, and never the mechanism another       │
│      domain's own completion depends on                             │
│    - calls DataService                                              │
│    - reads computed stats (through StatService, never directly)     │
│    - reads or mutates entity status flags (through StateService,    │
│      never directly — see Part 9)                                   │
│                                                                     │
│  Lives in: src/server/services/                                     │
│                                                                     │
│  Concurrency note: Roblox server Luau runs on a single, cooperative │
│  scheduler, not preemptive threads — there is no data race between  │
│  two RemoteEvent handlers the way there would be in a genuinely     │
│  multi-threaded system. The real hazard is yield-point              │
│  interleaving: a Service method that validates, yields (task.wait,  │
│  a DataStore call, anything that isn't pure Luau), and then         │
│  mutates leaves a window where another call can invalidate what it  │
│  validated. Rule:                                                   │
│  Service mutation methods should not yield between validating and   │
│  mutating — that makes them atomic for free, since nothing else     │
│  runs until they return. If a method genuinely must yield mid-      │
│  mutation, it needs an explicit busy-guard on the entity it's       │
│  touching, not a general locking system.                            │
└────────────────────────────────┬────────────────────────────────────┘
                                 │ typed setter calls only
┌────────────────────────────────▼────────────────────────────────────┐
│  3. ENTITY LAYER                                                    │
│                                                                     │
│  State containers assembled from components. Components enforce     │
│  their own invariants (capacity, ordering, stack rules).            │
│  No cross-entity logic. No signal firing. No DataStore calls.       │
│  The only callers of entity setters are Services.                   │
│                                                                     │
│  Lives in: src/<place>/server/entities/ -> ServerScriptService      │
│    Components live in src/serverShared/components/ ->               │
│    ServerStorage.Shared. An entity's internals are server truth and │
│    the client, being a display layer, never holds one.              │
└────────────────────────────────┬────────────────────────────────────┘
                                 │ after confirmed mutation
┌────────────────────────────────▼────────────────────────────────────┐
│  4. DATA LAYER                                                      │
│                                                                     │
│  Persistence only. All DataStore operations go through DataService. │
│  Called by Services after successful mutation. Never speculatively. │
│  Always pcall-wrapped. Always retried on failure.                   │
│                                                                     │
│  Lives in: src/server/services/DataService.lua                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Layer Rules

**Content Layer:**
- Validated at startup before gameplay begins — see Part 17
- Never written to at runtime — definitions are read-only after boot
- Engines read definitions, not individual service methods
- When a definition is invalid, fail fast with a clear error rather than
  discovering it mid-game when a boss spawns with broken stats

**Remote / EventTape Layer:**
- Captures intent (Request or Intention). Produces a typed Event object.
  Routes it to exactly one top-level domain Service method, by direct call.
  Does nothing else.
- No arithmetic. No DataStore. No entity reads. No business logic.
- No Signal usage of any kind at this layer. Signal only belongs to Services,
  and only after mutation. See Part 11.
- Client prediction is allowed: play animations optimistically, correct if
  rejected — see Part 15 for the full contract, including the ID-correlation
  mechanism and the explicit-reject carve-out.

**Service Layer:**
- Named after behavior, not data. See Part 10.
- One service per behavioral domain. A domain can contain multiple internal
  modules (see the CombatService/SkillService note in Part 10) while still
  being one public-facing authority.
- Every public Service method is either a **query** (reads and returns a
  value, never persists, never fires a Signal, never has a side effect —
  `StatService.compute`, `StateService.has`) or a **mutation** (changes
  state and, as its own last steps, persists if needed and fires a Signal —
  `ResourceService.grant`, `StateService.set`). Never both in the same
  method. If a method's name reads like a question ("compute", "has", "is",
  "get"), calling it must never change anything; if it reads like an action
  ("grant", "apply", "set"), it's expected to.
- Never reads entity stats directly — always through StatService.
- Never reads or writes entity status flags directly — always through
  StateService (Part 9).
- Never mutates another service's domain — calls that service's public method.
- Never calls DataService speculatively — only after confirmed mutation.
- Never fires a Signal before mutation. A Signal firing IS the public record
  that a mutation already succeeded.
- If a circular dependency appears (A calls B calls A), one call belongs
  in a third service or in a Signal listener. See the Circular Dependency
  Policy in Part 10.
- Owns the entire decision to accept or reject a Request or Intention. This
  decision is made and finished before Signal is ever touched.
- When a Service's mutation is the *source* of a change to another domain's
  data (e.g. Combat causing HP loss, Inventory causing HP gain from a potion),
  the source Service resolves the full, final amount — including any
  interception from StateService flags — before calling the target domain's
  generic mutation method. See Part 8.
- The no-yield-between-validate-and-mutate rule above (and everything else in
  this document's concurrency reasoning) assumes standard, single-threaded
  script execution. Roblox's Parallel Luau / Actor API is a genuine exception
  — code actually running on a separate `Actor` executes on a real, separate
  CPU thread, and the "atomic for free" argument stops applying to it. This
  project doesn't use Parallel Luau and has no plan to, so there's nothing to
  design now — but if per-entity work (boss AI at scale, per Roblox's own
  recommendation for this feature, is a plausible future candidate) is ever
  moved onto Actors for performance, this entire concurrency section needs a
  second look before that code touches any shared Service state.

**Entity Layer:**
- State and invariants only. Components enforce self-consistency.
- Services enforce cross-entity rules and game rules.
- No inheritance for Entities specifically (see Part 7 for why, and Part 4
  — the exception that once covered `Event` classes has been retired, see Part 7).

**Data Layer:**
- Every DataStore call goes through DataService. No exceptions.
- Order: validate → mutate → confirm → save. Never save before confirming.
- Save before teleporting. Block teleport if save fails.
- Never trust client-reported elapsed time for AFK calculations.
- On save failure: entity holds correct in-memory state. Log the failure.
  Next successful save will persist it. Do not crash.

---

## Part 7 — The Entity System — Composition and Component Invariants

> **Status:** SETTLED as a model, UNBUILT. Composition-over-inheritance
> is the load-bearing decision here and it has been pressure-tested against
> the real weapon-drop and pet cases. Declaring composition itself as
> content (rather than code) is flagged inside as not yet decided.

### Why Inheritance Fails for Games

Inheritance says: "A Boss IS-A Enemy IS-A CombatEntity IS-A LivingEntity."
Every entity type inherits everything above it. The problem arrives when
requirements don't fit the tree:

```
Entity
  └── LivingEntity          (has HP)
        ├── CombatEntity    (has Stats, Buffs)
        │     ├── PlayerEntity  (has Inventory, Gold, EXP, Pets)
        │     └── EnemyEntity   (has AI, LootTable)
        │           └── BossEntity  (has Phases, multiple weapon slots)
        └── PetEntity  ← needs Inventory AND Stats AND Equipment
                          but those live on different branches
```

PetEntity needs Inventory. Inventory is on PlayerEntity. Do you:
- Move Inventory up to CombatEntity? Now every Enemy has an Inventory.
- Copy Inventory logic into PetEntity? Two copies to maintain forever.
- Create InventoryHavingEntity? The tree is now a graph.

Every new entity type produces one of these three bad outcomes. With composition:
PetEntity needs Inventory? Attach the Inventory component. Done.

### The Long Version of Why This Is True — Walking the Failure Mode All the Way Through

This section exists because the composition-over-inheritance conclusion above
was reached quickly, but trusting it required walking through the actual failure
mode in detail more than once. Per this document's own rule — if you circle
back to something repeatedly, write it out fully — here it is in full, so it
never needs to be re-derived from scratch.

**Start with the tempting version.** It feels natural to write:

```lua
Player:Attack(target)
Player:UseSkill(skill)
Player:Equip(item)
```

"A player attacks. Therefore Player should have an Attack method." This is not
an unreasonable instinct — it is how most people first learn object-oriented
design. But ask what `Attack()` actually has to contain. A real attack involves
input validation, cooldown checks, range checks, hit calculation, accuracy,
damage formulas, buffs, armor, status effects, resource costs, animation events,
achievement checks, combat logs, and multiplayer synchronization. Where does
all of that go? It has to go somewhere, and the only place available inside
a method literally named `Player:Attack()` is either directly inside that
method, or as a thin wrapper that immediately calls out to five different
services. Either way, `Player` has become a traffic controller for concerns
it has no business owning.

Then the second problem compounds it: every entity type that can attack now
faces the same question. Player can attack. Pet can attack. Enemy can attack.
Boss can attack. A future Summon or Turret can attack. Do all of them get
`Attack()`? Now you have an `Entity` base class accumulating `Attack()`,
`UseSkill()`, `Equip()`, `Move()`, `Trade()`, `Farm()` — one method per
capability any entity anywhere might ever need — and you have built, by
accretion, a god object with extra steps. This is the exact inheritance-tree
failure already described above, just arrived at through methods instead of
through fields.

**Now compare `InventoryComponent`, which does not have this problem, and ask
precisely why not.** An inventory's behavior is almost entirely self-contained.
`inventory:add(item)` needs to know: do I have space, can this item stack with
something already here, which slot does it land in. That's the whole job. It
does not need to know the player's level, what dungeon they're in, their quest
state, anything about combat, or anything about the economy. It is a fully
reusable mechanism — a chest can have one, a player can have one, a boss's
loot container can have one, a pet can have one, and all of them need the exact
same primitive operations, because "being a container with slots and a capacity"
is a genuinely generic behavior in a way that "being able to attack" is not.
Attack is not an intrinsic property of *containment* — a chest has an inventory,
but a chest cannot attack, because attacking was never something inventories do.

**The real split, stated as a rule:** components own **local truth** — facts
that are true about themselves alone, checkable without looking at anything
else in the game (Inventory knows its own slots; Stats knows its own numbers;
Equipment knows its own slots; Buffs knows its own active list). Services own
**world truth** — facts that require looking at more than one thing at once
(Combat decides whether an attack is currently legal; InventoryService decides
whether a pickup is currently legal; EquipmentService decides whether an item
can currently be equipped). A component can answer "am I full?" by looking only
at itself. A service has to answer "should this player be allowed to pick this
up?" by looking at the player, the drop, the zone, and the quest state all at
once. That is a structurally different kind of question, and it is why it
needs a structurally different kind of owner. This is exactly the Component
versus Service split stated in Part 3 — this section is the full derivation
of it.

**The bank account analogy, because it made this click:** an `Account` object
reasonably owns `deposit(amount)` and `withdraw(amount)`, and it reasonably
enforces that the balance can never go negative — that is a local, self-contained
invariant about the account itself. But the account does not decide whether a
given withdrawal of $10,000 should be allowed *right now* for *this* customer —
that is a decision made by the surrounding banking system, which knows about
fraud rules, account holds, daily limits, and dozens of things the account
object itself has no business knowing. The account enforces its own consistency.
The bank enforces the world's rules about the account. Same split, different
domain.

**The concrete anti-pattern to watch for**, if this line ever gets blurry in
practice:

```lua
-- WRONG — the service starts reimplementing the component's job
InventoryService.addItem(player, item)
{
    check capacity
    find stack
    rearrange slots
    merge items
}

-- CORRECT — the service orchestrates; the component performs
InventoryService.pickup(player, item)
{
    validate pickup rules (range, zone, quest state — WORLD truth)

    player.inventory:add(item)   -- LOCAL truth, component's own job

    -- Only after this succeeds: Signal:Fire() to announce it (Part 11)
}
```

If `InventoryService` ever starts containing slot-rearranging or stack-merging
logic, it has started pretending to be an inventory, and that logic needs to
move back into the component where it belongs.

**One more explicit warning, because the trap runs in both directions:** just
as attaching `Attack()` to every entity produces a god object, attaching a
matching Service to every component produces its own kind of sprawl —
`InventoryComponent`, `InventoryService`, `InventoryManager`, `InventoryController`,
`InventoryHandler`, `InventoryRegistry`, `InventoryFactory`, `InventorySystem`
is over-engineering in the other direction. Keep it lean: one
component holding local truth, one service holding world truth, nothing more,
per domain, unless a real second concern is discovered.

**Restated as the rule to actually remember:** this is not "give every noun a
service and every service a component." It is "put the code where the knowledge
belongs." An inventory knows how inventories work. A combat system knows how
combat works. A player entity does not need to know either — it just holds
the pieces that give it those capabilities. This is composition-based design:
not "a Player is an Entity that can attack," but "a Player is an Entity that
currently possesses a combat capability, an inventory capability, and an
equipment capability" — and any other entity can possess any subset of the
same capabilities without inheriting a single line of code it doesn't need.

### Matter — The Alternative You'll Get Asked About, and Where It Actually Stands

Unlike every other rejected alternative in this document, this one wasn't a
deliberate call — Matter (the community-standard Roblox ECS library:
components as plain inert data, "systems" as free functions that query
entities by component combination and run every frame) simply wasn't known
about when this architecture was designed. Worth saying plainly rather than
inventing a tidier origin story, since manufacturing a false "we considered
it and rejected it for reason X" would be exactly the kind of thing this
document exists to prevent, not produce.

Evaluated honestly now, on the merits, rather than left as a total unknown:
Matter's real value proposition is performance at large entity counts —
dense, cache-friendly iteration over thousands of simultaneously simulated
things, which is why Roblox's own ECS-heavy showcases tend to be large-scale
simulations. This game's actual entity-count shape, per the Performance
Strategy section of the design document, is the opposite of that case —
small party combat with mobs outside player radius put to sleep, explicitly
designed to keep active entity counts low, not to push thousands of them
through a frame. Matter's core strength doesn't have much to bite into here.

The deeper mismatch is architectural, not just performance-motivated: Matter's
components are deliberately pure data with no behavior of their own — every
invariant a component enforces in *this* document's design (Inventory
capacity, Vitals bounds, Stats versioning — Part 7's "Components Own
Invariants" section) would need to move into systems under Matter's model,
since plain data can't check itself. That's not wrong, it's just a different
philosophy this document didn't choose, and adopting Matter now would mean
rebuilding the Component/Service split this entire document is organized
around, not adding a library alongside it.

Net assessment: sticking with the current design is still the right call for
this project's actual shape, but for a reason grounded in this game's scale
and the cost of a rebuild — not because Matter is worse in general, and not
because it was weighed and found wanting the first time around. Revisit this
if entity-count-driven performance ever becomes a real, measured bottleneck,
not preemptively.

### The `Event` Inheritance Exception — Retired

An earlier revision granted `Event` classes a deliberate exception to the
no-inheritance rule: each eventType got a subclass built via
`setmetatable({}, {__index = Event})`. The reasoning was sound for that model
-- Event types are a closed, shallow taxonomy where every subtype genuinely
*is-a* Event, with none of the combinatorial-explosion risk that makes
inheritance wrong for entities.

**The exception is no longer needed, because the subclasses are gone.** Each
eventType now declares its parameters as a schema and its authoring methods
on a builder (Part 12), which left the subclass with nothing to own. There is
one `Event` instance class.

Kept here rather than deleted because the *reasoning* was correct and would
be re-derived the next time something looks taxonomy-shaped: a closed,
shallow is-a hierarchy is not what the anti-inheritance rule is about. The
rule targets **entities** needing arbitrary, independently-combinable
capabilities -- a Pet needing Inventory-and-Stats-and-Equipment from
otherwise unrelated branches of a tree. If a future closed taxonomy genuinely
needs inheritance, that argument still holds; it simply stopped applying to
Events once their differences became data.

### Components Own Invariants — Not Just Data

The old model treated components as bags of data — dumb containers that Services
read and write freely. That's half right. The corrected model, stated in short
form (the long form is above):

- **Components own invariants** (self-consistency rules about their own data)
- **Services own cross-entity rules** (game rules that involve multiple entities or systems)

For example, the Inventory component shouldn't just hold a list of items.
It should enforce its own rules:
- Capacity: `add()` fails if `count >= maxSlots`
- Slot ordering: items maintain a stable slot index, not a random list position
- Stack merging: adding a stackable item to a slot that already has that item increases quantity rather than filling a new slot
- Slot lookup: `getSlot(index)` returns the item at that specific index

These are not game rules — they're Inventory rules. The Inventory component knows
them regardless of whether it belongs to a Player, Pet, or Boss. This logic belongs
in the component, not scattered across every Service that touches inventory.

What Services own: "Can this player pick up this item right now given their
level, zone, and quest state?" That's a game rule. That's InventoryService.

```lua
-- Component invariant (lives in Inventory component)
function Inventory:add(item)
    if self:isFull() then
        return false, "INVENTORY_FULL"
    end
    local existingSlot = self:findStackable(item)
    if existingSlot then
        existingSlot.quantity += item.quantity
        return true
    end
    local slot = self:nextEmptySlot()
    self.slots[slot] = item
    return true
end

-- Game rule (lives in InventoryService)
function InventoryService.pickup(player, drop)
    if not DropService.isInRange(player, drop) then
        return false, "OUT_OF_RANGE"
    end
    if not ZoneService.canPickupHere(player) then
        return false, "WRONG_ZONE"
    end
    local ok, reason = player.inventory:add(drop.item)
    if not ok then return false, reason end
    DropService.consume(drop)
    Signal["Player.Inventory.OnItemAdded"]:Fire(player, drop.item)
    return true
end
```

### Entity Composition

```lua
-- Player: full economy, progression, social, combat
PlayerEntity = {
    identity   = Identity.new("PLAYER", userId),
    vitals     = Vitals.new({ maxHp = 100 }),
    stats      = Stats.new({ attack=10, defense=5, speed=8, critChance=0.05 }),
    buffs      = Buffs.new(),
    stateFlags = StateFlags.new(),   -- FROZEN / DYING / INVULNERABLE / IMMOBILIZED — see Part 9
    equipment  = Equipment.new({ "weapon", "armor", "accessory" }),
    inventory  = Inventory.new({ maxSlots = 30 }),
    resources  = Resources.new(),
    -- Equipped pets are Equipment slots, not their own component -- see
    -- "PetRoster Collapses Into Equipment" below.
    pets       = Equipment.new({ "pet1", "pet2", "pet3", "pet4", "pet5" }),
}

-- Enemy: combat entity with loot, no economy
EnemyEntity = {
    identity   = Identity.new("ENEMY", generateId()),
    vitals     = Vitals.new({ maxHp = template.hp }),
    stats      = Stats.new(template.stats),
    buffs      = Buffs.new(),
    stateFlags = StateFlags.new(),
    equipment  = Equipment.new({ "weapon" }),
    inventory  = Inventory.new({ maxSlots = template.lootSlots }),
    lootTable  = LootTable.new(template.loot),
    aiState    = AIState.new(template.aiProfile),
}

-- Pet: own stats, equipment, inventory — not just a cosmetic
PetEntity = {
    identity   = Identity.new("PET", generateId(), ownerId),
    vitals     = Vitals.new({ maxHp = template.hp }),
    stats      = Stats.new(template.stats),
    buffs      = Buffs.new(),
    stateFlags = StateFlags.new(),
    equipment  = Equipment.new({ "accessory" }),
    inventory  = Inventory.new({ maxSlots = 5 }),
    farmStats  = FarmStats.new(template.farmProfile),
    ultimate   = Ultimate.new(template.ultimateProfile),
}

-- Boss: enemy with phases, shield state, and multiple weapon slots
BossEntity = {
    identity    = Identity.new("BOSS", generateId()),
    vitals      = Vitals.new({ maxHp = template.hp }),
    stats       = Stats.new(template.stats),
    buffs       = Buffs.new(),
    stateFlags  = StateFlags.new(),
    equipment   = Equipment.new({ "weapon", "offhand" }),
    inventory   = Inventory.new({ maxSlots = template.lootSlots }),
    lootTable   = LootTable.new(template.loot),
    aiState     = AIState.new(template.aiProfile),   -- the boss FSM, Part 10
    phases      = Phases.new(template.phases),
    -- No separate shield component -- "ShieldHits" is a ResourceDefinitions
    -- entry (Part 8), stored in .resources like any other resource, set to
    -- template.shield.requiredHits at the start of each shield phase.
}
```

### Two Existences — The Lua Entity and the Roblox Body

Every fighter in this game exists **twice**, and the two halves are cleaned up
by completely different rules. Nearly every lifecycle bug comes from treating
them as one thing.

**The mental half — the Lua table.** `entity`, its components, its ring
buffer. Lua tracks whether anything still points at a table, and when nothing
does, it deletes it. Automatically. There is no free, no dispose, and no way
to make one happen sooner.

**The physical half — Roblox Instances.** The Part, the Model, the Humanoid.
These are not Lua tables. They live in the Roblox instance tree — the one
visible in Studio's Explorer — and setting `part.Parent = workspace` is what
puts one there. From that moment **Roblox holds it, not your code.** Dropping
every Lua reference does not remove it; it stays in the world until something
calls `:Destroy()` on it.

The consequence is not a memory leak anyone would spot in a profiler. It is a
map that slowly fills with corpses.

**Three things outlive a Lua table, and `destroy()` exists for exactly these:**

| What | Why it survives | What releases it |
|---|---|---|
| Instances | Roblox's tree holds them | `:Destroy()` |
| Event connections | The connection holds the closure, which holds the entity — and it keeps *firing* | `:Disconnect()` |
| Entries in long-lived tables | A strong key keeps the entity reachable and keeps it processed every tick | the owning service's removal call |

The third is the subtle one, and it is why `EntityService:deleteEntity` calls
`SpatialService:detach` rather than leaving it to the entity. An entity's
membership in another system's table is not the entity's own business to
clean up, and every system that gets one is a step some caller can forget.

**Ordering constraint this creates.** Teardown detaches before it destroys, so
that an attack resolving mid-teardown cannot find a half-dismantled entity.
But detaching also clears the spatial component's handle on the body — so by
the time `destroy()` runs, the entity can no longer reach its own Instance
through its components. Anything that must destroy a Model has to hold its own
reference to it. That is correct independently: the spatial anchor is the
*root part*, and what you want destroyed is the whole *Model*.

### Why the Component Is Called `Identity`, Not `Entity`

Recorded because it will be asked again. The component holding `_type`,
`_id` and `_ownerId` looks like a base class — every entity has exactly one,
it's mandatory, and it feels like the "core" the rest is built around. Three
reasons it isn't and isn't named as one:

**It is has-a, not is-a.** A base class would mean `PlayerEntity` *is an*
`Entity` and inherits from it. `PlayerEntity` **has an** identity, held in a
field, exactly the way it holds `stats` and `spatial`. Nothing is inherited
and nothing can be overridden. It is a mandatory peer, not a parent — and
everything above in this Part is about why that distinction is load-bearing
rather than pedantic.

**The name would collide with its own container.** In this model the entity
*is* the outer table. Naming a field inside it `entity` produces
`entity.entity:getId()`, a sentence that cannot be read. `entity.identity`
says what it is.

**Every other component is named for what it holds** — `Stats` holds stats,
`Resources` holds resources, `Spatial` holds spatial data. This one holds
identity. `Entity` would be the only component named after the thing that
contains it.

**Where the intuition is right, and in a different architecture would win:**
in a *pure* ECS an entity genuinely is just an id, with components attached
to that id — there, `Entity = { id }` is correct, and the Matter discussion
above is where that road was considered and not taken. Here the container is
the entity, so a component cannot also be one.

**And the shared thing the intuition is reaching for does exist.** It is not
a base class; it is the component manifest flagged at the end of this Part —
a Content Layer row declaring which components an entity type gets, and a
builder that assembles it. "A player variant" is a data edit against that
list, never a subclass.

### The Weapon Drop — Why This All Matters

```lua
-- Enemy spawns holding a weapon from its template
local goblin = EnemyEntity.new("GOBLIN", GoblinTemplate)
EquipmentService.attach(goblin, "weapon", ItemEntity.new("RUSTY_SWORD"))
-- StatService includes RUSTY_SWORD in goblin's computed attack

-- Goblin dies. Weapon detaches. Drop spawns.
local dropped = goblin.equipment:detach("weapon")
DropService.createDrop(goblin.position, dropped)

-- Player picks it up. Same ItemEntity object. No copy.
InventoryService.pickup(player, drop)

-- Player equips it.
local old = EquipmentService.detach(player, "weapon")
EquipmentService.attach(player, "weapon", dropped)
InventoryService.add(player, old)
StatService.invalidate(player)
-- Player's attack recalculated with RUSTY_SWORD
-- StatService used the same code path it used for the goblin
-- No type checks. No "came from enemy" flags. Same interface.
```

### Component Registry

**Naming:** this document names components by what they hold — "the Identity
component," "the Stats component." The *files* carry a `Component` suffix
(`IdentityComponent.luau`, `StatsComponent.luau`), which is what keeps
`SpatialComponent` and `SpatialService` distinguishable at a require site.
Conceptual name here, suffixed name on disk.

**Core components — shared across any entity type:**

| Component | Holds | Invariants It Enforces |
|---|---|---|
| `Identity` | id, type, ownerId | id is immutable after creation; type must be declared in `IdentityRegistry` |
| `Stats` | base stat table, version number | base stats are typed numbers; version increments on every change |
| `Buffs` | active buff list | no duplicate buff ids; expired buffs are removed before getAll() |
| `StateFlags` | FROZEN, DYING, INVULNERABLE, IMMOBILIZED, expiry per timed flag | flags are booleans or timed; no domain-specific meaning lives here — see Part 9 |
| `Equipment` | named slots → ItemEntity | slot names must match declared slots; one item per slot |
| `Inventory` | ordered item slots, capacity | enforces maxSlots; handles stack merging; stable slot indices |
| `Resources` | resourceId → current value | values are numbers; get() returns 0 for unknown resourceIds |
| `Spatial` | world anchor, the parts it tracks, and one position ring buffer per part | buffers are preallocated and never grow; one shared timeline and cursor across every tracked part; re-anchoring clears history — see `HitDetection.md` |
| `Hurtbox` | the zone list — N capsules, each an offset from a named limb | shape only, frozen at construction; holds no position and no history, which is what makes it rewindable |

**`Spatial` and `Hurtbox` are the pair most often confused**, and the test that
separates them is one question: **does it change while the game runs?**
`Hurtbox` holds shape, written once at attach; `Spatial` holds position over
time, written thirty times a second forever. That is also why
`endpoints(index, pose)` takes the pose as a parameter instead of reading it —
a component that read `part.CFrame` itself could only ever answer about *now*,
and this layer's whole job is answering about a moment that has passed.

Per-limb history lives *inside* `Spatial`, keyed by `BasePart`, rather than in
a child component. Same reasoning as `PetRoster` → `Equipment` below: compare
the bookkeeping. A per-limb ring needs a preallocated buffer that never grows,
ordered samples, interpolated lookup by timestamp, and clearing on rebind —
which is `Spatial` exactly, with an explicit key instead of an implicit one.

**`Vitals` is gone and was never built.** Earlier revisions of this table
listed `Vitals | hp, maxHp, isDead`. Part 8 resolved that HP is a resource
like any other and lives in `.resources["HP"]`, with `MaxHP` as its declared
ceiling. Two homes for one number is how they drift apart.

**Domain components — specific to certain entity types:**

| Component | Used By | Holds |
|---|---|---|
| `FarmStats` | Pet | earn rate/sec, preferred enemy type, loot quality modifier |
| `Ultimate` | Pet, Weapon | animation ref, damage pattern, cooldown, charge state |
| `AIState` | Enemy, Boss | FSM state, queued next move, aggro target, last-move timestamp |
| `Phases` | Boss | HP thresholds, per-phase stat overrides, per-phase move pools |
| `LootTable` | Enemy, Boss | drop definitions: itemId, weight, quantity range, rarity floor |

There is deliberately no separate shield component — the Attack-Based
Shield's remaining/required hit count lives in `.resources["ShieldHits"]`,
the same `Resources` core component every entity already has, per Part 8's
revision.

### PetRoster Collapses Into Equipment

An earlier revision gave the Player a dedicated `PetRoster` component. It
doesn't need one. Compare the bookkeeping: bounded slots, one occupant each,
a capacity ceiling — that is `Equipment`, exactly, with numbered slots
instead of named ones.

The genuine difference is not the slot, it's the **side effect**: equipping
a weapon changes a stat contribution, while equipping a pet spawns an
autonomous entity into the world. That is a spawn rule, and per Part 3 a
game rule belongs to a Service, not to the component holding the slot. So
the slot bookkeeping is `Equipment`, and "spawn/despawn the pet entity when
the slot changes" is one rule owned by whichever domain owns companions in
the world.

What this removes: one component, one set of duplicated capacity logic, and
the reason `PetService` looked like it had something to own (Part 10). AFK
assignments move to `AFKService`; cooldowns move to `SkillService`.

**Flagged, not yet decided:** entity composition above is still written as
code — `PlayerEntity = { vitals = ..., stats = ... }` hardcoded per type.
The natural next step is declaring it in the Content Layer as a component
manifest per entity type, so that "a pet that fights like an enemy" is a
data edit rather than a new entity module. Worth doing when a third entity
type needs a variation, not before.

**No such loader exists today, and do not mistake the existing one for it.**
`shared/utils/ComponentLoader.luau` is unrelated: it walks a GUI folder for
modules exposing `newManager()` and instantiates client Manager objects. It
belongs to the rejected per-property Manager/Controller/System ecosystem
(Part 15), not to the Entity/Component system in this Part. The two use the
word "component" for completely different things — an entity Component here
is a state container with invariants, not a loadable UI module.

**The Buff structure:**

```lua
Buff = {
    id        : string,                        -- unique instance id
    type      : string,                        -- "ATTACK_UP", "POISON", "FROZEN" ...
    category  : string,                        -- "BUFF", "DEBUFF", "STATUS"
    magnitude : number | table,                -- flat value or complex modifier table
    duration  : number | "PERMANENT" | "UNTIL_HIT",
    source    : string,                        -- "WEAPON", "PET", "BOSS", "ITEM", "ZONE"
    stackRule : string,                        -- "STACK", "REPLACE", "REFRESH", "IGNORE"
    appliedAt : number,                        -- server timestamp
    expiresAt : number | nil,                  -- nil if PERMANENT
}
```

### StatService — Versioned Cache Invalidation

Previous versions used `StatService.invalidate(entity)` to clear the stat cache.
This was replaced with version numbers after review, because explicit invalidation
calls can be missed — and a missed invalidate means stale stats with no error.

```lua
-- Stats component tracks a version number
Stats = {
    base    = { attack = 10, defense = 5, ... },
    version = 0,   -- incremented every time base stats change
}

function Stats:setBase(statName, value)
    self.base[statName] = value
    self.version += 1   -- cache is now stale; any cached computation is invalid
end

-- StatService cache entry
StatCache = {
    entityId        : string,
    statName        : string,
    computedValue   : number,
    buffVersion     : number,   -- entity.buffs version at time of computation
    equipVersion    : number,   -- entity.equipment version at time of computation
    statVersion     : number,   -- entity.stats version at time of computation
}

-- StatService.compute checks versions before returning cache
function StatService.compute(entity, statName)
    local cached = StatService._cache[entity.identity:getId()][statName]
    if cached
        and cached.statVersion  == entity.stats.version
        and cached.buffVersion  == entity.buffs.version
        and cached.equipVersion == entity.equipment.version
    then
        return cached.computedValue   -- still valid
    end
    -- recompute: base + equipment contributions + buff modifiers + level scaling
    -- store new cache entry with current versions
    -- return computed value
end
```

Buffs and Equipment components also carry version numbers, incremented on every
change. The cache entry stores the versions at time of computation. On the next
read, StatService compares versions. If anything changed, it recomputes. No
explicit invalidate calls needed anywhere. Misses are impossible.

### This Pattern Has A Second Instance — Hit Volumes

Worth flagging here rather than only where it is used, because the pattern is
this section's and the instance is easy to miss.

**A skill's hit volume composes exactly the way a stat does.** A longsword that
reaches three studs further and swings fifteen percent slower does not get its
own `CLEAVE` — it contributes a modifier, the same way it contributes to attack
power:

```
StatService.compute(entity, "attack")     = base + equipment + buffs + level
SkillService.volumeFor(entity, "CLEAVE")  = base volume, modified by
                                            equipment and buffs
```

Same composition, same version-stamped cache, same reason. A skill per weapon
is Part 8's per-currency-Service mistake in different clothes: the list grows
with the *product* of skills and weapons, and the entries drift apart one
balance pass at a time.

`HitDetection.md` §8.4 carries the full design — the closed modifier
vocabulary, and which volume fields may be modified at all. The short version
of that second half is worth repeating because it is not obvious: **a weapon
may change how long an attack lasts, and may not change the arc it sweeps.**
An animation player can stretch a clip in time; it cannot stretch it in angle.

---

## Part 8 — The Resource System — Why EconomyService Was Wrong

> **Status:** SETTLED as a model, UNBUILT. The generic-ResourceService
> boundary has survived shields, invulnerability, and the DYING lock without
> ResourceService learning what any of them are, which is the strongest
> evidence this Part is right.

### The Name Was the Bug

"EconomyService" is named after data, not behavior. Systems named after data
become god objects because data always grows. The correct abstraction: one
`ResourceService` that enforces mutation rules for any resource type, driven
by `ResourceDefinitions`.

### Why Equipment Doesn't Belong Here Either

It's worth being explicit about this, because it was a live question rather
than an obvious answer: Equipment could look, at a glance, like it belongs
inside ResourceService too — after all, it's "stuff a player has." Running it
through this Part's own definition of a Resource settles it. A Resource is
fundamentally **a number that moves** — it has a category, a floor, a
ceiling, and moves via `grant()`/`drain()`. Equipment isn't a number at all —
there is no floor, ceiling, grant, or drain for "a sword in the weapon slot."
Its actual rules are a completely different shape: slot-name validation,
one-item-per-slot enforcement, and — critically — it triggers `StatService`
cache invalidation on every change, which no Resource type does. Forcing
Equipment into ResourceService would immediately produce the exact smell this
Part warns about below (ResourceService importing concepts from a different
domain). `EquipmentService` stays a fully independent Service — see Part 10's
registry.

### Is It a Resource? The Actual Test

Equipment's counter-example above generalizes into a repeatable test, worth
stating explicitly because it came up again later in a form that was easy to
get wrong: **is the thing's current value directly stored and mutated, or is
it computed fresh from other state?** A Resource is the first kind — there is
exactly one stored number, and `grant()`/`drain()` are the only ways it
changes. Anything that's *derived* from multiple other, independently-changing
sources — even if it also happens to have a floor, even if it also can't go
negative — is not a Resource, because "can't go negative" was never the
actual test. It's just a property lots of non-Resources also happen to have.

**Stats (attack, defense, speed, crit chance) are the concrete case this
matters for, and they fail the test cleanly.** Look at what `StatService.
compute` actually does (Part 7): base stat, plus equipment contributions,
plus buff modifiers, plus level scaling, recomputed whenever any of those
versions change. There is no single stored "current attack" number that
`ResourceService` could `grant()` or `drain()` — attack is a function of
several other pieces of state, not a quantity that moves on its own. An
armor-shredding debuff doesn't need anything new to stay correct here either
— it's just a debuff with a negative magnitude on the armor stat, consumed
in `StatService.compute` step 4 like any other buff, and a "vulnerability"
status that increases damage taken is a multiplier applied during
`CombatService`'s damage resolution, before the final number ever reaches
`ResourceService.drain`. Neither one touches a floor, because neither one is
draining a resource — they're changing an input to a computation. Stats stay
`StatService`'s job.

**A related mistake, worth flagging so it isn't repeated in code:** informal
worked examples earlier in this document's own drafting referred to
`GoldService.grant(...)` as if Gold had its own dedicated module. That's
wrong, and was corrected before any code got written from it — Gold is a
`ResourceDefinitions` entry like every other currency, handled entirely by
the one generic `ResourceService`. If you ever catch yourself about to write
a `RaidTicketService` or an `EventCurrencyService`, that's the same mistake
recurring — check whether the new thing is actually just another
`ResourceDefinitions` entry before writing a module for it.

**A second, subtler version of the same mistake: a `CurrencyService`
(everything with `category = "CURRENCY"`), separate from however EXP,
Level, and `ShieldHits` get handled.** This looks like progress — one
service instead of N — but it isn't, for a precise reason: `category` was
never a domain boundary, it's a field describing behavior (does this
persist, does it reset, what triggers at its ceiling). The moment you carve
a service out by category, the very next question is what houses EXP and
Level (`ProgressionService`?), then what houses `ShieldHits`
(`CombatResourceService`?) — and you've rebuilt the original per-resource
sprawl with three buckets instead of one-per-resource, no better off, just
slower to notice. `category` stays a value inside one `ResourceDefinitions`
entry, read by the one `ResourceService`, exactly like `floor`, `ceiling`,
and `scope` already are — never a reason to fork the engine.

**The discipline this actually depends on, stated plainly so it's not
discovered the hard way:** `ResourceService` stays generic only as long as
nobody adds an `if resourceId == "Gold" then applyVIPMultiplier() end`
branch directly inside `grant()`. The instinct to do that will show up —
someone will be in a hurry, need a currency-specific bonus, and reach for
the fastest path. The moment that branch exists, the abstraction is already
dead and this is Option A again with extra steps. The correct home for that
logic is exactly where shield absorption and invulnerability checks already
live: the *calling* Service resolves the final amount — bonuses, multipliers,
whatever's specific to this trigger — before it ever calls `grant()`.
`ResourceService` should never learn a VIP multiplier exists, the same way
it was never allowed to learn what a shield is.

### The Combat Complexity Question — Resolved

An earlier revision of this document raised, but did not answer, a real risk:
treating HP as a plain Resource is elegant for the simple case, but combat
introduces true damage, shields, invulnerability windows, damage reflection,
life steal, death prevention, and execute thresholds — and if all of that
routes through `ResourceService`, it starts knowing too much about combat.
This is no longer a hypothetical. The game design confirms at least three of
these are real: the Attack-Based Shield (a hit-count absorption mechanic, not
even damage-based), the invulnerability window granted during a domain
ultimate, and the one-way DYING lock during a weapon finisher. The resolution:

**`ResourceService` stays exactly as generic as it is for every other
resource. It never learns what a shield, an invulnerable window, or a DYING
lock is.** Instead, **the domain that originates an HP-affecting action
resolves the full, final amount before ever calling `ResourceService.drain()`
or `.grant()`.** Concretely:

- A combat hit against an enemy: `CombatService` checks `StateService` (Part
  9) for INVULNERABLE or DYING first — if either is set, the resolved damage
  is zero and nothing further happens. If the target has an active
  Attack-Based Shield, `CombatService` decrements the shield's hit counter
  (a real, declared number — see below) instead of touching HP at all, until
  the shield breaks. Only once none of that applies does `CombatService`
  call `ResourceService.drain(entity, "HP", finalAmount, source)` with the
  number that should actually apply.
- A potion heal: `InventoryService` resolves what the potion grants — still
  checking `StateService` for anything that would block it — before calling
  `ResourceService.grant(entity, "HP", amount, "POTION")`.
- A poison-pool tick (illustrative only — no such mechanic is actually
  designed yet, this is here purely to show the pattern extends to a third
  kind of source): whatever ends up owning zone hazards, if one is ever
  built, would resolve its own amount, check `StateService`, and call
  `ResourceService.drain(...)` the same way.

This is the "source owns its own contribution" rule: whichever domain
*causes* the change computes it, `ResourceService` only ever receives a
final number and moves it. The one thing that must **not** be re-implemented
independently inside every source is the check for cross-cutting flags like
INVULNERABLE or DYING — those go through `StateService`'s one shared gate
(Part 9), consulted by every source uniformly, so that "invulnerable" reliably
means "immune to everything," not "immune to combat specifically." A future
zone-hazard tick that forgets to check `StateService` would silently bypass
an invulnerability window that's supposed to be absolute — that's exactly the
kind of duplicated, easy-to-forget check a shared gate exists to prevent.

**An open shape-question, not a resolved design:** every example above is
triggered once by a discrete Event (a hit, a potion drink) and resolves
once. Nothing here yet says whether a "source" is allowed to be something
that repeatedly calls `ResourceService` on its own schedule — a
damage-over-time or regeneration effect that keeps acting without a new
external Event triggering each application. If a self-sustaining-over-time
mechanic ever gets designed, whether it fits this same triggered-once shape
or needs a different one is worth one line of thought at that point. Not
resolved here, and deliberately not guessed at in advance.

### How "The Source Resolves The Final Amount" Actually Happens

The rule above says *what* has to happen but not *how*, and the worked
examples in this Part show it as an ad hoc sequence of calls (check
`StateService`, check the shield counter, then call `.drain()`). That is fine
while the list is short and stops being fine as it grows — and per the game
design it will grow, to armor, buffs, shields, invulnerability, crit, damage
reduction, reflection, lifesteal, on-hit triggers, execute thresholds,
stagger, and barriers.

**The mechanism is the `DamageResolution` pipeline, and it lives in Part 11**
— along with the four-phase Validate/Resolve/Commit/Announce boundary, the
rules that keep the context object and the steps from rotting, and the
separation between numbers the pipeline computes (direct calls, made here in
`ResourceService`'s terms) and consequences the Content Layer declares
(dispatched by label).

What matters for *this* Part is unchanged by it: `ResourceService` still
receives one final number and moves it, and still never learns what a shield
or an invulnerability window is. The pipeline removes the *enumeration*
problem inside `CombatService`; it does not move the boundary between Combat
and Resource, and `CombatService` still calls `ResourceService.drain()`
directly at the end exactly as described above.

**Hit count versus damage amount, for the Attack-Based Shield specifically:**
the shield's required and remaining hit counts are **real, server-tracked
numbers**, not cosmetic. They are declared per weapon/skill in the Content
Layer (a sword's definition literally says "this slash is N hits," the same
static fact a UI description would show the player), and are independent of
how the damage *total* for that same activation was computed. This is why
hit count and damage total are tracked as two separate concerns, even though
they originate from the same single skill activation.

**Revision, applying the test above: the shield hit-counter is a Resource,
not a separate component.** An earlier pass in this same revision (Part 9,
before "Is It a Resource?" existed as a stated test) kept it as its own
`ShieldState` component, reasoned about as a Combat-specific concept
alongside `StateService`'s boolean flags. Run it through the actual test
instead: it's a single stored number, it moves via `drain()` (one decrement
per landed hit), it has a floor (0), it has a ceiling (the boss's declared
required-hit-count), it triggers a behavior at floor exactly like HP's
`onFloor = "TRIGGER_DEATH"` does, and it isn't persistent — every property a
Resource has. It belongs in `ResourceDefinitions` as `ShieldHits`, initialized
per shield phase with the existing `ResourceService.set()` API (already built
for exactly this — "administrative set, used for initialization"), and
decremented with the existing `.drain()`. **What doesn't change:**
`CombatService` still owns the *decision* of whether an incoming hit should
drain `ShieldHits` or `HP` — that's Combat's world-truth call, per Part 3, and
it doesn't move just because the bookkeeping mechanism underneath it did. A
useful side effect of the revision: there's no need for a separate "is the
shield currently up" flag either — `ResourceService.get(boss, "ShieldHits") >
0` answers that for free, one less piece of state to keep in sync.

### Resource Categories

| Category | Examples | Direction | Persisted | Resets |
|---|---|---|---|---|
| `VITAL` | HP, Stamina | Both | No | Each session |
| `CURRENCY` | Gold, RaidTokens, GachaTickets | Both | Yes | Never |
| `PROGRESSION` | EXP, Level, ReputationRank | Up only | Yes | Never |
| `TIMED` | DailyTokens, WeeklyAttempts | Both | Yes | Real-world timer |
| `COMBAT_TEMP` | ShieldHits | Down only | No | Per shield phase, via `.set()` |

Note on HP specifically: per the game design, HP is server-memory-only and
never persisted — switching between places (Hub, Farm Zone, Dungeon) resets
it to max. It is still displayed in every place, so players can gauge
survivability, but it never reaches `DataService`.

`ShieldHits` is its own category rather than `VITAL` because its reset
behavior is different in kind, not just in degree — it doesn't reset per
session, it gets explicitly re-initialized by `CombatService` at the start
of each shield phase via `ResourceService.set()`, and has no meaning outside
an active shield window at all.

**Correction: `CONSUMABLE` (potions, ammo, crafting materials) has been
removed from this table — it was carried over from an earlier draft, before
this Part's own "Is It a Resource?" test existed, and it doesn't survive
being checked against that test.** If a potion is something you can see
sitting in a specific bag slot, stacked ("Health Potion ×12"), that's
`InventoryService`'s shape — slot position and stack-merging are exactly the
kind of thing the Inventory component was already built to handle (Part 7),
and a Resource has neither. Using an item decrements its stack via
`Inventory:add()`/`Inventory:remove()`, with a `consumable = true`-style flag
on the item definition marking that using it should remove one from the
stack — not a `ResourceService` entry. The one legitimate exception, not
currently planned and not to be assumed: a slot-less, abstract bulk
stockpile of crafting material that never occupies bag space (some games
track "Wood: 500" as a pure counter, separate from inventory) would
genuinely be Resource-shaped if it's ever designed — but that's a different
thing from a potion sitting in a slot, and nothing here confirms Shattered
Realms wants that distinction. Don't build it speculatively.

### Cross-Experience Persistence Scope

Some resources need to be shared across every place (Gold, probably), while
others are meaningful only within one place and shouldn't follow the player
across a teleport (`RaidTokens`, if raids are Dungeon-only currency). This
is a **declarative field**, the same as everything else about a resource's
behavior — not a reason to build a second service or a second persistence
path:

```lua
Gold = {
    category   = "CURRENCY",
    floor      = 0,
    persistent = true,
    scope      = "CROSS_EXPERIENCE",   -- shared across Hub, Farm Zone, Dungeon
},

RaidTokens = {
    category   = "CURRENCY",
    floor      = 0,
    ceiling    = 500,
    persistent = true,
    scope      = "PER_EXPERIENCE",     -- Dungeon-only, doesn't follow the player elsewhere
},
```

`ResourceService`'s own persistence step reads `scope` to decide which
backing store or key structure to save under. This is the same move as
`category`, `floor`, and `onFloor` — a field the generic engine already knows
how to interpret, not a new layer.

### ResourceDefinitions — The Config

```lua
-- src/shared/definitions/ResourceDefinitions.lua
-- Add entries here. Zero engine changes required for new resource types.

local ResourceDefinitions = {

    HP = {
        id         = "HP",
        category   = "VITAL",
        floor      = 0,
        ceiling    = "MaxHP",           -- references another resource id
        persistent = false,
        onFloor    = "TRIGGER_DEATH",
    },

    Stamina = {
        id         = "Stamina",
        category   = "VITAL",
        floor      = 0,
        ceiling    = "MaxStamina",
        persistent = false,
        regenRate  = 5,                 -- units per second
        regenDelay = 2,                 -- seconds after drain before regen starts
    },

    Gold = {
        id           = "Gold",
        category     = "CURRENCY",
        floor        = 0,
        ceiling      = nil,
        persistent   = true,
        transferable = true,
    },

    RaidTokens = {
        id           = "RaidTokens",
        category     = "CURRENCY",
        floor        = 0,
        ceiling      = 500,
        persistent   = true,
        transferable = false,
    },

    EXP = {
        id         = "EXP",
        category   = "PROGRESSION",
        floor      = 0,
        ceiling    = "EXPToNextLevel",  -- dynamic per level
        persistent = true,
        onCeiling  = "LEVEL_UP",        -- a recognized engine behavior, not a
                                         -- function -- see "EXP, Level, and
                                         -- the onCeiling Boundary" below
    },

    DailyTokens = {
        id            = "DailyTokens",
        category      = "TIMED",
        floor         = 0,
        ceiling       = 5,
        persistent    = true,
        regenRate     = 1,
        regenInterval = 86400,          -- one per real-world day
    },

    ShieldHits = {
        id         = "ShieldHits",
        category   = "COMBAT_TEMP",
        floor      = 0,
        ceiling    = nil,               -- set dynamically per shield phase, see below
        persistent = false,
        onFloor    = "TRIGGER_SHIELD_BREAK",
    },
}
```

`ShieldHits`'s ceiling isn't a fixed number the way `RaidTokens`' is — a
boss's required hit count varies per encounter. `CombatService` sets it at
the start of each shield phase: `ResourceService.set(boss, "ShieldHits",
template.requiredHits)`, using the existing administrative-set API, not a
new mechanism.

### EXP, Level, and the `onCeiling` Boundary

EXP fits the Resource shape cleanly — a stored number, moved only upward,
with a floor and a dynamic ceiling. Level is worth being more careful about,
because it's tempting to model it as a second, independent resource that
anything can `grant()` directly, and that's not quite right.

**Level should never be something an arbitrary caller directly grants.** It
should only ever change as the deterministic *consequence* of EXP crossing
its ceiling — which is exactly what `onCeiling` already exists to express.
`onCeiling = "LEVEL_UP"` names a small, closed, recognized behavior the
generic engine knows how to execute (roll EXP back down or reset it,
increment Level by exactly one, fire the relevant Fact) — not a function,
which would be the "config becoming code in disguise" smell Part 2 already
warns against. Whether Level itself ends up stored as a second, trivial
`ResourceDefinitions` entry that `LEVEL_UP`'s execution bumps internally, or
lives as a plain field on the entity that only the `LEVEL_UP` behavior is
allowed to touch, is an implementation detail either way — what actually
matters is that nothing outside the engine's own `onCeiling` execution is
ever allowed to move Level directly. If some other Service ever calls
`ResourceService.grant(entity, "Level", 1, "SOME_OTHER_REASON")`, that's a
sign the boundary has already been crossed.

**Anything richer than "the number went up" is not resource-shaped at all,
and doesn't belong inside `LEVEL_UP`'s execution.** Unlocking a new ability,
recomputing stats, playing a celebration animation — none of those are
things Leveling Up *is*, they're things that might *optionally* care that it
happened. Per the inherent-vs-optional test (Part 11), that makes them Facts,
not part of the engine's behavior tag: `LEVEL_UP` fires `Player.Progression
.OnLevelUp`, and `AbilityService`, `StatService`, and whatever UI plays the
celebration each react independently, on their own schedule, with zero
knowledge of each other. `ResourceService`'s own involvement ends the moment
the number changed and the fact was announced.

### ResourceService API

```lua
ResourceService.grant(entity, resourceId, amount, source)
--  1. Look up definition — error if not found
--  2. Validate source is registered and valid for current context
--  3. Validate amount > 0 and within sane bounds
--  4. Read current value, calculate new value, clamp to ceiling
--  5. Mutate entity.resources:set(resourceId, newValue)
--  6. Execute the onCeiling behavior tag if the ceiling was hit (LEVEL_UP,
--     etc.) -- a small, closed, engine-recognized vocabulary, never a
--     function (Part 2). If the tag names something richer than "the
--     number changed" (LEVEL_UP does), it fires its own dedicated Fact
--     here, in addition to step 9 below, not instead of it.
--  7. Persist-or-defer if definition.persistent (mark dirty, generic
--     per-entity dirty-set, flushed on DataService's own cadence)
--  8. Push the outbound EventTape confirmation directly, tagged with
--     eventId if a client Request is waiting on it
--  9. Fire this resource's own auto-generated Fact signal (see
--     "Auto-Generated Per-Resource Signals" below) -- for optional
--     reactions only. Per Part 11, this is the ONLY place in the codebase
--     allowed to fire it.

ResourceService.drain(entity, resourceId, amount, source)
--  Same flow downward. Executes the onFloor behavior tag if the floor was
--  hit (TRIGGER_DEATH, TRIGGER_SHIELD_BREAK, etc.), firing that tag's own
--  dedicated Fact in addition to the generic per-resource signal, same
--  rule as onCeiling above. amount here is always the FINAL, fully-resolved
--  amount -- the caller (Combat, Inventory, a zone hazard...) has already
--  run it through StateService and any domain-specific interception
--  (shields) before this is ever called.

ResourceService.set(entity, resourceId, value)
--  Administrative set — no source validation. Used for initialization
--  (including re-arming ShieldHits at the start of a shield phase).
--  Still validates bounds, persists, and fires the Fact signal.
```

### Auto-Generated Per-Resource Signals

Each resource gets its own Fact signal, generated from `ResourceDefinitions`
itself rather than hand-declared per currency — the same "generic engine,
declarative config" pattern this whole document keeps coming back to,
applied one level further than it was before. At boot, after
`ResourceDefinitions` is validated (Part 17), a small step walks it once and
creates one signal per entry: `Player.Resources.Gold.OnChanged`,
`Player.Resources.HP.OnChanged`, `Boss.Resources.ShieldHits.OnChanged`, and
so on. `ResourceService.grant`/`.drain`/`.set` look up the correct signal by
`resourceId` and fire that one specifically, as the last step of an already
validated, already-mutated call.

This was chosen over one shared `Player.Resources.OnResourceChanged(entity,
resourceId, delta, newTotal)` signal that every interested listener filters
internally. The shared-signal version was seriously considered — filtering
by `resourceId` isn't wrong, and referencing `ResourceDefinitions.Gold.id`
instead of a raw string already rules out the obvious typo risk — but it
means every listener, including ones that only ever care about Gold, gets
invoked on every HP tick and every Stamina regen tick and immediately bails
out. Either way, a new resource costs zero hand-written signal-wiring code —
the signal is generated from the same declarative entry that already defines
the resource's floor and ceiling, not authored separately.

Per Part 11's "Protecting the Fact," only `ResourceService` should ever hold
a fire-capable reference to any of these generated signals — everything else,
including anything `SignalHelper`-wires up, gets the listener-only handle.
**This generated signal is for genuinely optional reactions only —
Achievements watching Gold, a UI badge watching RaidTokens — never the
mechanism client notification depends on.** The next section is about why
that distinction had to be made explicit the hard way.

### What Client Notification Is Not: The Manager Layer, Tried and Rejected

This is worth walking through in full because it was actually built,
mentally, before the problem with it was caught — and the failure mode is
exactly the kind that resurfaces if it isn't written down.

**What was tried:** a `GoldManager` (and, by the same logic, one per
resource) wired up via `SignalHelper`'s auto-connect, listening to Gold's
Fact signal. On receipt, it pushes a confirmation to the client over
EventTape, and separately tracks that Gold is "dirty" so a batched save can
pick it up later rather than writing to the DataStore on every single grant.

**Why it looked reasonable:** it followed the established shape — Signal
fires, a Manager reacts, the Manager does the client-facing and
persistence-adjacent work. That's exactly the pattern `SignalHelper` was
built to support.

**Why it's actually wrong, and it took checking it against this document's
own already-written rule to see it:** apply the inherent-vs-optional test
from Part 11. Telling the client "your gold changed" and marking gold dirty
for a later save are not *optional reactions* to granting gold — they are
part of what granting gold *already means*. An action that mutates a
player's currency but never tells the client and never gets saved isn't a
degraded version of granting gold, it's not granting gold correctly at all.
That makes it inherent, by the same definition this document already uses
everywhere else — and inherent relationships don't get wired through
Signal-and-a-reactive-Manager. Doing it that way is pub/sub standing in for
what should just be the tail end of the same function call — paying
indirection cost to simulate something a plain return already gives you for
free. It's also, structurally, the exact same mistake as the original
per-currency-Service problem this whole Part is about, just relocated one
layer up: a hand-rolled `GoldManager` next to a hand-rolled
`RaidTokenManager`, the same ~6 lines duplicated per resource, diverging
slowly over time.

**The actual resolution: there is no Manager here at all.** `ResourceService
.grant`/`.drain`/`.set` do the client-facing and persistence-adjacent work
themselves, as their own last steps, generically, before ever touching the
Fact signal:

```lua
ResourceService.grant(entity, resourceId, amount, source, eventId)
--  ...validate, mutate, clamp (steps 1-6, unchanged)...
--
--  7. Persist-or-defer: if definition.persistent, mark resourceId dirty in
--     a generic per-entity dirty-set (a plain Set<resourceId>, not a
--     per-resource flag), flushed to DataService on whatever cadence it
--     already uses. Not every mutation needs to hit the DataStore the
--     instant it happens.
--  8. Push the outbound EventTape confirmation directly — payload is just
--     { resourceId, newValue, delta, source }, generic across every
--     resource, tagged with eventId if a client Request is waiting on it
--     (Part 15's pending-actions contract).
--  9. THEN, separately, fire this resource's own Fact signal (previous
--     section) — for anything that wants to optionally react. Not the
--     mechanism step 8 depends on; step 8 already happened on its own.
```

Dirty-tracking and client notification are properties of the resource
*system*, not properties of Gold specifically — which is exactly why they
belong inside the one generic `grant`/`drain`/`set` implementation instead
of being re-solved once per resource behind a Signal indirection. No
`GoldManager`. No `CurrencyManager`. The Manager layer collapses into three
generic lines already living inside code that exists regardless.

### Multi-Hit Skills — One Calculation, Cosmetic Fragmentation

**Four different numbers get called "hits" in conversation, and none of them
may be called that in code.** Each counts a different thing, so each name
carries its own denominator:

| Name | Counts | Declared on | Multiplies damage? |
|---|---|---|---|
| `hitsPerTarget` | strikes, **per enemy struck** | the skill (Content Layer) | No — one calculation, fragmented cosmetically |
| `maxTargets` | **distinct enemies** one activation may strike | the skill's `HitVolume` | No — it caps, never adds |
| `samples` | **evaluations of the volume** across its active window | the skill's `HitVolume` | No — results are deduplicated by entity |
| `chainJumps` *(PLANNED)* | **sequential re-targets**, each a fresh query from the last enemy struck | the skill | Each jump is its own activation |

The trap is the first two sitting side by side in one skill definition.
"This attack hits 6" is a sentence with no meaning — six strikes on one
enemy, or one strike on six enemies. Neither name can be read the wrong way,
which is the entire reason they are spelled like that.

`samples` is the subtlest, because it is not a gameplay number at all. It
exists so that a fast swing is not missed in the gap between two evaluations,
and its results are deduplicated per entity: three samples catching the same
enemy is **one** hit, not three. It belongs to detection, and it never
reaches content data. See HitDetection.md.

**`chainJumps` is not `maxTargets`.** Chain lightning arcing through five
enemies is five sequential resolutions, each originating from the previous
target, each with its own falloff and its own reach. Capping a single volume
at five is a different mechanic that happens to produce a similar-looking
number. Building one with the other produces a skill that hits five enemies
simultaneously from the caster and calls itself a chain.

---

A single skill activation may be declared (in content data) as producing
several cosmetic "hits" — a sword slash might be "10 hits" per its own
description. This does **not** mean the server performs ten independent
damage calculations, ten independent crit rolls, or ten independent
`ResourceService.drain()` calls. It means one calculation, one crit roll,
applied once, for the whole activation:

- The server computes **one** total damage number and **one** crit result
  for the entire activation — not one per cosmetic hit. There is no
  meaningful gameplay difference between "10 independent 10-damage hits"
  and "one 100-damage event," and computing 10 independent rolls for a
  purely cosmetic effect is unnecessary overhead for zero mechanical gain.
- The declared **`hitsPerTarget`** (10, in this example) is still real and
  server-known — it comes from content data and drives the Attack-Based
  Shield counter (Part 9) regardless of how the damage total was computed.
  Note which counter it drives: a shield that absorbs "the next 3 hits"
  counts strikes on *itself*, so `hitsPerTarget` is the number it consumes.
  `maxTargets` never enters that arithmetic.
- `ResourceService.drain()` is called **once**, with the final total.
- The outbound message to the client (Part 12, Part 15) carries the
  aggregate result — `{ totalDamage, hitsPerTarget, isCrit, newHp }` — and the
  client's Damage Number System (Part 15) is responsible for fabricating a
  staggered, cosmetic cascade of `hitsPerTarget` individual numbers from that one
  total. If the activation crit, every fabricated number in the cascade can
  reflect that visually (size, color, sound) without needing ten independent
  crit rolls to justify it.
- This applies to a single skill activation. A *combo* of several distinct,
  separately-fired activations (e.g. a player chaining multiple real attacks)
  is a different case — each real activation still goes through this same
  flow independently, and their `hitsPerTarget` values sum for shield-counting
  purposes, but each one gets its own real Event, its own real calculation,
  and its own real Signal fire.

---

## Part 9 — The State System — Composable Status Flags, and Why HP Isn't Enough

> **Status:** SETTLED as a model, UNBUILT. Small — four flags and one
> gate. Justified by uniformity rather than size; see the Buff comparison
> inside for why it stays separate.

### Why This Needed Its Own System

Several mechanics in the game design need to answer the same underlying
question about an entity: *is this entity currently allowed to act, or to be
acted upon?* The domain ultimate (opt-in players become INVULNERABLE and
IMMOBILIZED, all enemies in range become FROZEN) and the weapon finisher (the
boss becomes DYING, and nothing — no damage, no buffs, no AI — may affect it
until the cinematic completes) are the two confirmed mechanics that need
this, but the underlying need is general: a cutscene, a future mechanic, or
content not yet designed could just as easily need to make *any* entity
briefly untouchable.

This is not a Resource (it isn't a number that moves) and it isn't a Stat
(it isn't part of a computed attack/defense value). It is its own thing: a
small set of composable, mostly-boolean flags that any entity can carry, and
that any Service about to act on or mutate an entity must check first.

**Three clarifications, because this Service invites the same three
misreadings every time:**

- **It is not world state.** Not the dungeon's current wave, not which area
  a player is standing in. Those are `DungeonService` and `ZoneService`.
  Everything here is a property *of an entity*.
- **It does not store anything.** The data lives on the entity, on its
  `StateFlags` component, like every other piece of entity state in this
  architecture. `StateService` holds no state of its own at all.
- **So it is a gate, not a store.** Its entire reason to exist is being the
  single door. That makes it small — four flags, one gate function, a
  set-permission rule, maybe forty lines. It is justified by uniformity, not
  by size, and that is fine.

**Why it isn't just a Buff category — the honest version.** Compare the two
structures. A `Buff` is `{type, magnitude, duration, source, stackRule,
expiresAt}`. A StateFlag is a boolean with an expiry and a source. A
StateFlag is a Buff with no magnitude — and Part 7's `Buff` structure
*already declares* `category = "STATUS"` as a legal value. `FROZEN` is
genuinely expressible as `{type="FROZEN", category="STATUS", duration=3,
source="ULT"}`. The conceptual framing ("flags are gates, buffs are
modifiers") describes a difference in how they are *consumed*, not in what
they *are*, and it is not enough on its own to justify two systems.

The reason that does hold is performance-shaped, and it is worth stating
plainly so this question stops resurfacing every time someone notices
`category = "STATUS"` sitting in the Buff table:

**The gate is on the hot path of every single mutation in the game, and it
must be O(1) and unconditional.** If answering "is this entity INVULNERABLE"
means walking a buff list, evaluating stack rules, and checking expiry
against the clock, then the most safety-critical check in the codebase is
also its slowest and most conditional one. Buffs get *computed*; gates get
*read*. A flat boolean store behind one function is the right shape for
that specifically, and it is the only reason these stay separate.

**Naming warning, restated from Part 4:** this is `StateService`, not
`StatService`. They are one letter apart and do unrelated jobs. Never
shorten either in conversation or comments.

### What Lives Here, and What Doesn't

`StateService` owns a small, fixed vocabulary of cross-cutting flags:

| Flag | Meaning | Example source |
|---|---|---|
| `FROZEN` | Cannot act; AI ticking is skipped; timers do not advance | Domain ultimate (enemies in range) |
| `DYING` | One-way lock; rejects all further damage, buffs, and AI decisions | Weapon finisher, boss only |
| `INVULNERABLE` | Cannot take damage from any source | Domain ultimate (opted-in players) |
| `IMMOBILIZED` | Cannot move or act, but can still be damaged (distinct from INVULNERABLE — they're independent and can co-occur) | Domain ultimate (opted-in players) |

These live on a `StateFlags` component (Part 7), attached to any entity that
might ever need one — players, enemies, bosses alike. Per Part 3, the
component owns the local invariant (a flag is set or it isn't, and a timed
flag knows its own expiry); `StateService` owns the cross-cutting decision
logic (who is allowed to set which flag on which entity, and every other
Service's obligation to check it before acting).

**What does *not* belong here:** a boss's `AIState` FSM (`IDLE →
TELEGRAPHING → ATTACKING → STAGGERED → ...`, Part 10) is a separate,
boss-specific mechanism, not part of `StateFlags`. The FSM is inherently
mutually-exclusive (a boss is in exactly one of those states at a time) and
only bosses have one at all — players don't have an FSM in this design, just
whatever combination of `StateFlags` happens to be set. `FROZEN` and `DYING`
happen to also be meaningful as boss FSM states (a frozen boss's FSM simply
doesn't advance), but that's a boss-specific consequence of the shared flag,
not evidence the flag itself belongs inside the FSM. Similarly, a boss's
Attack-Based Shield hit counter is **not** a `StateFlags` entry — it's a
numeric quantity, not a boolean gate, and per Part 8's revision it now lives
in `ResourceService` as a `ShieldHits` resource rather than as its own
component. `CombatService` still owns the *decision* of when to drain it —
that hasn't changed — only the bookkeeping underneath moved.

### The Gate, Concretely

Any Service about to mutate an entity in a way that these flags are meant to
prevent must consult `StateService` first, as one common choke point rather
than re-implementing the check per source:

```lua
-- Inside CombatService, InventoryService, a zone-hazard tick, etc. —
-- anywhere that's about to reduce an entity's HP
if StateService.has(target, "INVULNERABLE") or StateService.has(target, "DYING") then
    return  -- resolved damage is zero; nothing further happens
end
```

This is why `INVULNERABLE` cannot be a check that only `CombatService`
performs — a poison-pool tick or a future self-damage effect that skips this
check would silently bypass a flag whose entire purpose is to mean "immune to
everything, full stop." One gate, checked uniformly, is what keeps that
guarantee true.

### Why This Is a Peer Domain, Not Nested Under Combat

Applying Part 2's conceptual-vs-contingent test: every *currently designed*
use of these flags happens to originate from combat (the domain ultimate, the
finisher), but the flags themselves have no inherent tie to combat — a
cutscene making every entity in a scene briefly untouchable is a plausible
future use with nothing to do with a fight. Since keeping `StateService` a
peer domain costs nothing extra to build today and preserves that option for
free, it stays a peer domain that `CombatService` (and anything else) calls
into, the same reasoning already applied to `BuffService` in Part 10.

### Client Notification, and Where the Fact Signal Fits

This applies Part 11's Direct-Call-or-Signal test to `StateService` the same
way Part 8 applies it to `ResourceService`, and it splits the same way for
the same reason.

**Telling the client an entity is FROZEN or INVULNERABLE is inherent, not
optional** — the domain ultimate's entire visual spectacle (Section 6 of the
design document) depends on the client correctly rendering the frozen world;
if the client never found out, the mechanic wouldn't just be worse, it
wouldn't work. So `StateService.set(entity, flag, value)` handles that
directly, as its own step, the same shape as `ResourceService`: mutate the
`StateFlags` component, then push whatever replication or outbound EventTape
confirmation the flag needs — no separate Manager, for the same reason none
exists for resources.

**Reacting to a flag changing — greying out an ability button, an
achievement, anything that merely *might* care — is optional.** For that,
`StateService.set` fires an auto-generated Fact signal as its last step, the
same mechanism as `ResourceService`: one signal per recognized flag,
generated from the small fixed vocabulary at the top of this Part
(`Player.State.Frozen.OnChanged`, `Player.State.Invulnerable.OnChanged`,
etc.), never hand-declared in a registry file, never the mechanism the
client-facing behavior depends on. Per Part 11's "Protecting the Fact," only
`StateService` should ever hold a fire-capable reference to these.

---

## Part 10 — The Service Layer — Where the Game Lives

> **Status:** the four-kind taxonomy, the single-door test, and the
> dependency layering are **SETTLED** — they resolve a real, recurring
> confusion about what counts as a domain. Every individual registry entry
> is **UNBUILT**.

### "Service" Was Doing Three Unrelated Jobs

The registry in this Part used to be one flat table, and that flatness was
itself the bug. It listed, under one word, things that are not the same kind
of thing at all — which is why "is this a domain-level service?" kept being
hard to answer. It was hard because half the table was not answering that
question.

There are **four kinds of Service**, and knowing which kind you are holding
determines its name, its dependencies, its place scope, and whether it is
allowed to know what an entity type is.

**1. Authority services** — `StatService`, `ResourceService`, `StateService`,
`BuffService`, `EquipmentService`, `InventoryService`.

These are not domains. Each is **the single door to one component type,
generic across every entity type in the game**. They own no game rules of
their own; they own the correctness of one kind of state. They are leaves in
the dependency graph — they require nothing but components.

**2. Domain services** — `CombatService` (owning `SkillService`),
`DungeonService`, `DropService`, `ShopService`, `ZoneService`, `LevelService`,
`ComboService`, `AchievementService`.

Real bounded contexts. These own game rules and orchestration. They call
downward into authority services constantly, and sideways into each other
rarely.

**3. Infrastructure services** — `SessionService`, `DataService`,
`CinematicService`, `AnnouncementService`.

Lifecycle, persistence, and output. Not game logic.

**4. Drivers** — `AIService`, `AFKService`.

Things that *tick* and produce Intentions (Part 5). Structurally they are
clients of the Service layer, not members of it — they decide something
should happen and then go through the same doors a player Request would.

### The Single-Door Test

**Does it behave identically for a player, a pet, a boss, and a dropped
item?**

If yes, it is an authority service. It is named after the component it
gates, it is generic, and it never learns what entity types exist.

If it ever needs `if entityType == "PET"`, it is not an authority service —
it is a domain service wearing the wrong name, and the entity-specific rule
belongs in whichever domain owns that behavior.

### Naming — And Why `StatService` Is Not a Violation

```
CORRECT                         WRONG
───────────────────────         ──────────────────────
ResourceService                 GoldService
CombatService                   EnemyService
StatService                     PlayerService
StateService                    PetService
BuffService                     GameService (not a domain — a placeholder)
EquipmentService                Utils (a graveyard — give each util to its domain)
```

"Name services after behavior, not data" is a rule for **domain services
only**, and stating it unqualified is what made `StatService` and
`ResourceService` look like violations of this document's own rule.

- **Domain services are named after behavior** — `CombatService`, not
  `EnemyService`.
- **Authority services are named after the component they gate** —
  `StatService`, `ResourceService`. That is correct, because the thing they
  own genuinely *is* a kind of state, and their whole value is being the
  only door to it.

The names that remain wrong are **entity-type services**: `PlayerService`,
`EnemyService`, `PetService`. These are named after a noun that is neither a
behavior nor a component. They always turn out to be a bag of unrelated
responsibilities that each belong somewhere else — see the `PetService`
dissolution below.

### Dependency Layering — The Rule That Makes Cycles Structurally Impossible

The real coupling question is not "may services depend on each other" (yes,
constantly, that is just composition). It is **which direction**.

```
drivers          AIService, AFKService, SessionService
                          ↓
domain           CombatService, DungeonService, DropService, ShopService,
                 ZoneService, LevelService, ComboService, AchievementService
                          ↓            (sideways: rare, one-directional)
authority        StatService, ResourceService, StateService, BuffService,
                 EquipmentService, InventoryService     ← leaves
                          ↓
                 components / entities
```

- **Downward is free.** `ShopService` → `ResourceService`, `CombatService` →
  `StatService`/`StateService`/`ResourceService`. Call as much as you want.
- **Sideways is suspicious.** Allowed, but justify it in a comment and never
  make it bidirectional. `CombatService` → `DropService` on a kill is fine;
  `DropService` → `CombatService` is not.
- **Upward never happens.** That is what a Fact is for (Part 11).

**The load-bearing constraint: authority services are leaves.**
`ResourceService` must never require `CombatService`. Hold that one line and
cycles are structurally impossible in the bottom two layers, which is where
almost all of them would otherwise appear.

This is prose today, and prose is enforced by whoever remembers it. It is
cheap to make real: a test that greps the requires in `services/authority/`
and fails if any of them names a domain service. Do that when the second
authority service exists.

### Circular Dependency Policy

If Service A calls Service B which calls Service A, one of the calls is in
the wrong place. Under the layering above this should now be rare — a cycle
means something is calling sideways in both directions, or upward.

1. The call belongs in a third service both A and B can call
2. One direction should be a Signal listener, not a direct call
3. The two services were actually one domain and should be merged

**Caution on option 2:** "make it a Signal listener" is only safe when the
relationship is genuinely *optional* (Part 11's test). If A's dependency on B
is inherent, converting that edge to a Signal doesn't remove the coupling —
it hides it behind "hope a listener happens to be connected," which is
exactly the `GoldManager`/`SetHandler` mistake reintroduced as a generic
escape hatch for cycles. If the relationship is inherent, use option 1 or 3.

Never work around a cycle with lazy requires or deferred loading. Fix the
design.

### A Domain Is Not the Same Thing as a File

A Service can own multiple internal modules while remaining one behavioral
domain with one public API. `SkillService` (skill-tree logic, cooldowns,
unlock state) lives **under** `CombatService`, not beside it — a skill is
meaningless without combat resolution, and combat resolution needs to know
what a skill does. Splitting them into independent top-level Services would
just recreate a circular dependency between them.

The rule for sub-module vs. new top-level domain is Part 2's
conceptual-vs-contingent test: **is the coupling to the parent definitional,
or does it merely happen to be true of today's content?**

`BuffService` was almost nested under Combat and it is worth preserving why
it wasn't, since the first instinct was wrong. Every currently-designed buff
use is combat-scoped, which made nesting look obviously right. Two things
overturned it. First, Part 7's `Buff` structure already declares
`source = "ZONE"` alongside `"WEAPON"`, `"PET"`, `"BOSS"`, `"ITEM"` — a
zone-sourced buff doesn't inherently require combat. Second, and more
concretely: Part 13's place separation means that if `BuffService` lived
inside `CombatService`'s subtree it could **never exist in the Hub or Farm
Zone at all**, structurally, foreclosing any future Hub-only buff by
construction rather than by choice.

`HEAL`, by contrast, *was* confirmed genuinely combat-exclusive — HP is
server-memory only and never persists across places. That is the actual
difference: `HEAL`'s combat-only status is a confirmed fact about the game,
`BUFF`'s was an assumption that didn't survive contact with its own declared
`source` field. `StateService`'s flags have Buff's shape, not Heal's.

### `PetService` Dissolves — And Why It Existed

`PetService` was in this registry, and it should not have been. It is an
entity-type service: named after a noun, owning a bag of unrelated
responsibilities. It got in because pets are a headline feature, not because
a behavior needed a home. Applying this Part's own first rule to its own
table dissolves it completely:

| Former `PetService` responsibility | Actual owner |
|---|---|
| Pet equip / unequip | `Equipment` component invariant + the domain that owns spawning |
| Ultimate routing | `CombatService` — `Ultimate` is already a component shared by Pet **and** Weapon (Part 7) |
| AFK farm assignment | `AFKService` (Farm Zone only) |
| Cooldown tracking | `SkillService`, under Combat, where cooldowns already live |

Nothing is left over.

**Pets need zero pet-specific combat code.** Compare `PetEntity` to
`EnemyEntity` in Part 7: `vitals`, `stats`, `buffs`, `stateFlags`,
`equipment`, `inventory` — identical. `Identity` already carries `ownerId`.
Add the `aiState` component that Enemy and Boss already use, and a pet is an
owned, AI-driven combat entity that goes through the same
`DamageResolution` pipeline as everything else. A pet activating a skill is
`SkillService.activate(petEntity, skillId)` — the same call a player makes,
with a different entity.

The total pet-specific surface is `FarmStats` (AFK only, never touches
combat) and `Ultimate` (already shared with Weapon). If you ever find
yourself writing `if entity.identity.type == "PET"` inside `CombatService`,
that is the alarm.

See Part 7 for the related collapse of `PetRoster` into `Equipment`.

### `BossAIService` and `PetAIService` Merge Into `AIService`

An earlier revision listed `BossAIService` in this registry and
`PetAIService` in Part 14's scheduler — the latter never appearing here at
all, which was itself a symptom.

Both do the same four things: tick at some frequency, iterate entities
carrying an `aiState` component, skip the ones `StateService` gates, and
emit an Intention. What differs is the *decision function*, and that is
already content — `template.aiProfile` (Part 7).

So: **one `AIService` owning the tick harness, with per-profile decision
modules behind a flat table** — the same shape as Part 11's effect handlers.
The frequency difference (bosses at 10Hz, pets at 4Hz) becomes a field on
the profile, not a reason for a second Service. The scheduler gets one AI
entry no matter how many creature types are added later.

### Service Registry

Everything below is a should-do. It is listed now so each domain only has to
be decided once. The **Places** column tracks which of the three places
(Hub, Farm Zone, Dungeon — see Part 13) each Service exists in.

**Place scope is decided by the persistence test, not by category** (Part
13): *does this service read or write data that survives a teleport?* If
yes, it exists in every place and is byte-identical there. Save data written
in the Hub is read in the Dungeon; a service whose rules differ by place
silently diverges the save.

**Authority services — the single door to one component type. Leaves.**

| Service | Owns | Places |
|---|---|---|
| `ResourceService` | Grant/drain/set for all resource types; floor/ceiling enforcement; onFloor/onCeiling triggers; regen ticking; the generic dirty-set and outbound push (Part 8). Stays fully generic — never learns about shields, invulnerability, or DYING. | All |
| `StateService` | Composable status flags (FROZEN, DYING, INVULNERABLE, IMMOBILIZED) for any entity; the one shared gate every mutating Service checks | All |
| `StatService` | Stat computation with versioned cache; the only place final stats are calculated. Pure query — never mutates, never fires a Signal | All |
| `BuffService` | Buff application, stack/replace/refresh/ignore logic, expiry timer | All |
| `EquipmentService` | Slot validation, equip/unequip rules. Deliberately independent of ResourceService (Part 8). Also holds equipped pets — a roster is bounded slots with one occupant each, which is what Equipment already is (Part 7) | All |

**Domain services — game rules and orchestration.**

| Service | Owns | Places |
|---|---|---|
| `CombatService` | Hit validation (latency-tolerant), the `DamageResolution` pipeline (Part 11), kill detection, loot trigger, shield-counter decisions. Owns the `SkillService` sub-domain (skill unlock state, cooldowns, skill-tree nodes) as a **child module**, not a sibling — see Part 12's eventType rule | Dungeon |
| `InventoryService` | Cross-entity item rules, pickup eligibility, transfer between entities. Domain rather than authority: it consults `DropService` and `ZoneService`, which a leaf may not do | All |
| `DungeonService` | Instance creation/cleanup, wave spawning, escalating pressure, boss spawn | Dungeon |
| `DropService` | Loot table rolls, world drop creation, unclaimed drop registry, pickup range validation | Dungeon |
| `ComboService` | 200ms multiplayer combo-window detection, server-clock-anchored playback (Part 12). Deliberately flagged as the one domain where the generic-engine pattern may be the wrong call — revisit with Part 2's Three Tests once requirements are concrete | Dungeon |
| `LevelService` | Level-up logic: stat growth, skill unlocks; called by ResourceService on EXP ceiling. Universal — it writes persisted progression | All |
| `AchievementService` | Milestone tracking, unlock checks. Pure listener — only ever reacts via a connected Fact, never called directly | All |
| `ZoneService` | Current zone per player, zone-gated eligibility rules | All |
| `ShopService` | Purchase validation, catalog; calls `ResourceService.drain()` for currency. If a Dungeon shop is ever added it is **this same service** with a different catalog entry in the Content Layer — never a second implementation | Hub (possibly Dungeon) |

**Infrastructure.**

| Service | Owns | Places |
|---|---|---|
| `SessionService` | Player join/leave flow, data load/save, teleport gating between all three places | All |
| `DataService` | All DataStore reads and writes — the only service that touches DataStore | All |
| `CinematicService` | Domain ult camera hijack, opt-in/opt-out, finisher camera, FROZEN/DYING coordination via StateService, server-clock-anchored playback (Part 12, Part 15) | Dungeon |
| `AnnouncementService` | Server-wide broadcast triggers (e.g. Mythic pet drop). Separate from `CinematicService` (personal camera) and the HUD (per-player display) | All — Phase 5 |

**Drivers — tick, decide, emit an Intention.**

| Service | Owns | Places |
|---|---|---|
| `AIService` | One tick harness for every entity with an `aiState` component; per-profile decision modules behind a flat table; consults StateService before ticking anything. Replaces the former `BossAIService` and `PetAIService` | Dungeon; also Hub/Farm if companion pets are present there — open, decide when pets are built |
| `AFKService` | Server-side elapsed-time × farmStat calculation, 8hr cap. Never trusts client-reported elapsed time (Part 13) | Farm Zone |

Deliberately **not** listed: Guild, Trading, Mail, Fishing, Crafting, and any
dedicated gacha-luck system. These came up only as hypothetical scalability
tests. Naming services for systems that don't exist and aren't planned is the
speculative-engine trap Part 2 warns against. Add them when they are real —
noting that `BuffService` and `StateService` are kept as peer authority
services *specifically* so a future system could consume them without
un-nesting anything first.

**Resolved this revision:** the eventType taxonomy used to nest
`BUFF`/`HEAL`/`DEBUFF` under `COMBAT`, which stopped mapping one eventType to
one top-level domain once BuffService and StateService became peer domains.
Redrawn: they are gone from COMBAT, `SKILL`/`ULTIMATE`/`PARRY`/`DODGE` joined
it (SkillService lives inside CombatService), and `TELEPORT` became `SESSION`.
Every top-level `eventType` now maps 1:1 onto exactly one Service domain, and
each event class owns its own subTypes rather than a central taxonomy file
declaring them a second time.

### StatService — The Most Critical Service

If any service boundary is violated, bugs appear in one system.
If StatService is violated, bugs appear in every system that touches combat,
UI, AI, and equipment simultaneously — all showing different wrong numbers,
all untraceable to a single source.

**Nothing reads raw stats for game decisions. Nothing.**

```lua
-- WRONG: bypasses buffs, equipment, level scaling
local dmg = attacker.stats:getBase("attack") - defender.stats:getBase("defense")

-- CORRECT: accounts for everything, always current
local atk = StatService.compute(attacker, "attack")
local def = StatService.compute(defender, "defense")
local dmg = math.max(0, atk - def)
```

`StatService.compute(entity, statName)`:
1. Check version cache — return cached value if all versions match
2. Get base stat from `entity.stats:getBase(statName)`
3. Iterate `entity.equipment:getAll()` — accumulate item contributions
4. Iterate `entity.buffs:getAll()` — apply modifiers (flat add, multiplier)
5. Apply level scaling if entity has a Level resource
6. Cache result with current stat/buff/equipment versions
7. Return computed value

This is a **query** in Part 6's sense — it never mutates, never persists,
never fires a Signal. Calling it can never change anything, which is what
makes it safe to call from inside a `DamageResolution` step (Part 11).

---

## Part 11 — Resolution and Cross-Domain Communication

> **Status:** the communication taxonomy (Direct Call, Table, or Signal) is
> **SETTLED**. The Resolution Pipeline is **PROVISIONAL** — the shape is
> decided, nothing is built. The Effect Table is **PROVISIONAL**, and should
> be built from what Parry actually needs rather than in advance. The current
> `Signal`/`SignalHelper`/`SignalEnum` implementation in code is
> **SUPERSEDED** — see 11.6.

This Part answers two questions that kept getting tangled together, and
separating them is most of the value here:

1. **How does one action resolve internally**, without the Service that owns
   it growing a branch per mechanic? (11.1 – 11.3)
2. **How do two separate domains talk to each other**, without every Service
   requiring every other Service? (11.4 – 11.5)

They are different questions. The first is about growth *inside* a domain;
the second is about edges *between* domains. Most of the wrong turns
recorded in 11.6 came from answering one with the other's tool.

---

### 11.1 — The Resolution Pipeline

#### The Problem

"The source resolves the final amount" (Part 8) says *what* must happen, not
*how*. Left as an ad hoc sequence of calls, it works while the list is short
— check `StateService`, check the shield, call `.drain()`. It stops working
once the list grows, and per the game design it will: armor, buffs, shields,
invulnerability, crit, damage reduction, reflection, lifesteal, on-hit
triggers, execute thresholds, stagger, and barriers are all named as real
mechanics elsewhere in this document.

Without a mechanism, that becomes an ever-growing hand-written `if` chain
inside `CombatService` — which is the actual shape of the "CombatService
becomes an 8,000-line god object" risk. It is not a Signal problem and not
an effect-dispatch problem. It is a growth problem inside one Service's own
method, and it needs its own answer.

#### Pipeline Is a Role, Not a Service

Per Part 3, `Pipeline` owns execution order and nothing else — never a rule,
never state of its own. **There is no `DamagePipelineService`.** There is an
ordered list of steps living inside `CombatService`, and the steps are small
modules, not Services.

This is the answer to "do we make a service per mechanic." No. There is no
`DamageService`, no `ShieldService`, no `ParryService`, no `CritService`.
Each of those would be a Service wrapping exactly one mechanic, which is the
sprawl this Part exists to prevent.

#### Four Phases, With Hard Boundaries

```
VALIDATE   Service. Is this legal? Owns the skill, off cooldown, target
           valid, in range, StateService gate. On reject: return, send the
           client an explicit reject if it has pending optimistic state
           (Part 15). No pipeline runs. No Signal fires. Nothing mutates.

RESOLVE    Pipeline. Pure computation. Reads through StatService,
           BuffService, StateService and the Content Layer. Mutates the
           context object and nothing else. Cannot reject.

COMMIT     Service. Applies the resolved numbers, then dispatches any
           content-declared effects. Must not yield.

ANNOUNCE   Service. Pushes the outbound EventTape diff, then fires Facts.
```

**Validation is not in the pipeline, and this boundary is not negotiable.**
If a step can reject, rejection logic ends up smeared across a dozen files,
and a rejected action can still have half-run by the time something says no.
The pipeline assumes the action is already legal. Its only job is arithmetic.

**Services are called during RESOLVE, but only queries.** `StatService
.compute`, `BuffService.get`, `StateService.has` — the query/mutation split
from Part 6 is exactly what makes this safe. Reads are free; writes are not.

#### The Context Object, and the Two Rules That Keep It Alive

`CombatService` builds one `AttackContext` per activation (attacker, target,
the resolved skill definition, base damage, tags, source) and hands it down
the phase list. Each step reads it and mutates it. Nothing in the pipeline
needs to know how many modifier types exist, and a new modifier is a new
step registered into a phase — not a new `if` inside `CombatService`.

This clears Part 2's Test 3 more cleanly than most generic engines here do:
twelve-plus named modifier types, each doing the same shape of work, well
past the "ten or more things sharing real structure" bar.

**The pipeline is not what rots. Two other things are, and both need a
stated rule:**

**Rule 1 — the context is a declared shape, not a scratch bag.**
`AttackContext` accreting forty fields because every step bolts one on is
how this pattern dies. Fields are declared up front and typed. If a step
needs a value no other step reads, that value belongs inside the step, not
in the shared context.

**Rule 2 — a step mutates the context and nothing else.** No step calls a
mutating Service. No step fires a Signal. No step starts another
resolution. The moment a step mutates the world, you get reentrancy — a
pipeline run triggering a pipeline run mid-flight — and the resulting
numbers are untraceable the first time they come out wrong.

So lifesteal does not heal the attacker inside the pipeline. It sets
`ctx.lifesteal = 40`, and COMMIT applies it. A parry counterattack does not
fire inside the pipeline; `ParryStep` sets a flag, and the counter runs
after the first resolution has fully committed. Steps compute; the Service
commits.

#### Phases

| Phase | What resolves here |
|---|---|
| `SOURCE` | base damage, weapon contribution, skill multiplier |
| `ATTACKER` | crit roll, attacker buffs, stat scaling |
| `DEFENSE` | armor, damage reduction, target buffs |
| `INTERCEPT` | parry, block, dodge, shield absorption |
| `COMMIT` | clamp, decide HP vs. ShieldHits, produce `ctx.final` |

**Prefer named phases over bare priority integers.** Flat priority numbers
become a known pain point once enough modifier types exist to have real
interaction rules ("shields resolve before armor, but only if…"), and they
tend to get tuned by trial and error rather than reasoned about. Ordering
*within* a phase is where subtlety hides — prefer steps that are
order-independent within their phase (collect additive contributions, apply
once) over steps that depend on running third.

#### One Open Decision: Where Modifier Steps Live

Not resolved here, deliberately:

- **Component-owned** (`BuffComponent:ModifyAttack(ctx)`, discovered by
  iterating whatever is attached to the target) — simpler call sites, but a
  Component is now reaching into a shared cross-entity context, which is not
  "local truth checkable by looking at itself alone" per Part 3. This would
  need to be an explicit, named exception to Part 3, not a silent one.
- **Service-owned** (`BuffService.modifyAttack(ctx)`, registered into a fixed
  phase at boot) — preserves Part 3's boundary exactly, at the cost of an
  explicit registration step per phase.

Decide this when the second modifier type is actually written, not before.

#### COMMIT: Use What Came Back, Not What You Computed

```lua
local applied = ResourceService.drain(target, "HP", ctx.final, "COMBAT")
-- returns the REAL amount after floor/clamp -- 12, not the 40 you computed

diff[#diff+1] = { entity = target.id, resource = "HP", delta = -applied }
```

The outbound payload is assembled from what the commits actually did, and
pushed once at the end. Using the computed value instead of the returned one
is how a client ends up rendering 40 damage when 12 landed — a desync that
looks like a networking bug and isn't.

**Atomicity is free, and here is exactly why:** the commit block must not
yield. Roblox server Luau is cooperatively scheduled, so nothing else runs
between the first `drain` and the last `BuffService.apply`. That is the same
no-yield-between-validate-and-mutate rule from Part 6, applied to the commit
block. If you ever yield mid-commit, partial application becomes real and
you need machinery you currently do not need. Don't. Persistence is deferred
through the dirty-set anyway (Part 8).

#### Naming: `DamageResolution`, Not `AttackPipeline`

Name it after what it resolves, not what triggers it. It takes "some amount
of damage from A to B" and resolves it through modifiers. A basic attack, a
skill, a parry counter, a DoT tick, and a future zone hazard all need the
identical phases. `AttackPipeline` implies attacks own it, and the first
hazard tick that needs it then feels like a hack.

**One pipeline per resolution *kind*, not per event type.** `CombatService`
will receive many different subTypes; most converge on this one resolution.
A heal is `compute amount → check gate → grant` — three lines, no phases, no
pipeline. Build a second pipeline when a second resolution kind actually has
ten modifiers, not before.

---

### 11.2 — Effects: Consequences Declared by Content

#### Two Kinds of Change Come Out of a Resolution

This distinction decides the whole mechanism, and getting it backwards
produces either a god object or a pointless second vocabulary.

**Numbers the pipeline computed.** Final damage, shield vs. HP, crit,
lifesteal amount. Combat's own arithmetic. Exactly one of each per
resolution, names known at write time. **Direct call in COMMIT.** Wrapping
these in descriptors buys nothing and costs you the return value.

**Consequences the content declared.** `{ type = "DEBUFF", buff = "POISON" }`,
`{ type = "STATE", flag = "STAGGERED" }`. These arrive from a definitions
file. The pipeline does not know what is in the list, the count varies per
content entry, and a designer can add a fifth one tomorrow. **These are
dispatched by label.**

That second case is *forced*, not chosen: you cannot hardcode a call for
something that arrived as data. That is the entire justification for a label
table, and it is a considerably stronger one than "Parry might need it."
It also keeps the dispatched set small — only ever content-declared effects,
never the arithmetic.

#### The Table

A flat, static, server-only table — the same shape already settled for
`EventRoutingRegistry` in Part 12, for the same reason:

```lua
-- server/resolution/EffectHandlers.luau
-- Server-only. One entry per effect type. The full vocabulary is readable
-- in one screen. Every handler is (target, effect, source) -> ().

return {
    DAMAGE = require(script.Parent.effects.DamageEffect),
    HEAL   = require(script.Parent.effects.HealEffect),
    BUFF   = require(script.Parent.effects.BuffEffect),
    DEBUFF = require(script.Parent.effects.DebuffEffect),
    STATE  = require(script.Parent.effects.StateEffect),
}
```

**Not a `register()` registry.** An earlier revision specified
`EffectResolver.register(effectType, fn)` called by each Service at boot.
That is precisely the "folder of one-line handler modules" pattern Part 12
considered and rejected, because registration scatters the picture across N
files instead of one place a developer can read end to end — and it adds
registration-order questions and duplicate-assertion machinery for a closed
vocabulary that has maybe eight entries, ever. A fixed table has none of
those problems.

**Handler modules require Services; the table does not.** `DamageEffect`
knows how to reach `CombatService`. `EffectHandlers.luau` requires only
handler modules. This is the same discipline already applied to Event
routing (Part 12), and it is what keeps the Service Locator critique from
applying: a closed enumeration in one server file is not a locator, it is a
switch statement with better ergonomics.

**The discipline that keeps it narrow:** every entry is shaped exactly
`(target, effect, source) -> ()`. The moment something is registered that
isn't "apply this effect to this target" — the moment it becomes the place
any Service reaches any other Service by name because "it's already required
everywhere" — it has stopped being effect dispatch and become genuine
Service Locator. A closed, narrow vocabulary is fine; an open door is not.

#### Boot Coverage Validation

Content referencing an effect type nobody implemented should be a boot-time
crash a developer sees immediately, not a silent no-op a player eventually
notices:

```lua
-- BootValidation.checkEffectCoverage()
-- Walks every definitions module registered at boot -- generically, not a
-- hand-listed set of files. A new definitions file with an `effects` field
-- must not be able to silently reintroduce the gap this check exists to
-- close.
for _, def in ContentLayer.iterateAll() do
    for _, effect in ipairs(def.effects or {}) do
        assert(EffectHandlers[effect.type],
            "no handler for effect type: " .. effect.type)
    end
end
```

This is the same "declared list + deterministic resolution + aggregated
boot-time failure" discipline applied to Event routing (Part 12) and place
manifests (Part 13). Three small explicit implementations of one discipline,
not one shared generic engine — see Part 12 for why unifying them was
considered and rejected.

---

### 11.3 — Worked Example: Parry, End to End

Parry is the case that motivated all of the above, and the first thing to
notice is that **parry is two mechanically separate things.** Conflating
them is exactly what would produce the `ParryService` god object this Part
rules out.

**Parry as defense** — an attack lands during a parry window, damage is
negated. That is one step in `INTERCEPT`:

```lua
-- resolution/steps/intercept/ParryStep.luau
return function(ctx)
    local window = BuffService.get(ctx.target, "PARRY_WINDOW")
    if not window then return end
    if not ParryDefinitions.matches(window, ctx) then return end  -- timing/arc
    ctx.damage   = 0
    ctx.parried  = true
    ctx.parryDef = window.defId
end
```

**Parry as trigger** — a successful parry causes a counter, a stagger, a
debuff. That is not part of resolving the incoming attack. It is declared as
content and dispatched after COMMIT:

```lua
-- ParryDefinitions.PERFECT
onSuccess = {
    { type = "DAMAGE", source = "reflect", scale = 1.5 },
    { type = "STATE",  flag = "STAGGERED", duration = 1.2 },
    { type = "DEBUFF", buff = "POISON", duration = 4 },
}
```

The full trace, for an enemy attacking a player who parries and counters:

```
EventTape → routes eventType=COMBAT → CombatService

── Resolution #1: the incoming attack ──
VALIDATE   attacker can act; player is a legal target
RESOLVE    SOURCE/ATTACKER/DEFENSE compute damage = 85
           INTERCEPT: ParryStep matches → ctx.damage = 0, ctx.parried = true
COMMIT     nothing to drain; BuffService.consume(player, "PARRY_WINDOW")
           dispatch ParryDefinitions.PERFECT.onSuccess through EffectHandlers
ANNOUNCE   outbound diff; Combat.OnParrySuccess

── Resolution #2: the counter (sequential, NOT nested) ──
   DamageEffect calls CombatService.resolveAttack(player, enemy, counter)
VALIDATE → RESOLVE → COMMIT (ResourceService.drain enemy HP) → ANNOUNCE
   StateEffect  → StateService.set(enemy, "STAGGERED", 1.2)
   DebuffEffect → BuffService.apply(enemy, "POISON", 4)
```

The counterattack is a **full second pipeline run with the roles swapped** —
which is the point: a counter, a basic swing, a DoT tick and a zone hazard
all enter the same door. And it is *sequenced, not nested*, because Rule 2
held: `ParryStep` only flagged the context. Resolution #1 fully commits
before #2 begins.

**Where the parry window itself lives:** the `Buff` structure (Part 7)
already declares `duration = "UNTIL_HIT"`, which exists for exactly this.
Use a Buff, not a `StateFlags` entry. The deciding question is whether
anything outside Combat needs to know the entity is parrying — it doesn't,
so it stays in Combat's vocabulary. `StateFlags` is for absolute gates every
domain must check (Part 9); a parry window is a conditional, combat-local
modifier.

**Total cost of parry: one pipeline step, one content definition, three
effect handlers, zero Services.** If building parry ever seems to require a
`ParryService`, the two halves have been fused back together.

---

### 11.4 — Direct Call, Table, or Signal

This is the cross-domain question, and it is separate from everything above.
Three tools exist, they solve genuinely different problems, and reaching for
the wrong one produces exactly the duplication-through-indirection this
document keeps having to catch.

**The test, stated once: would this action still mean what it claims to mean
if the other domain's involvement didn't happen?** If no — granting loot
without it reaching the player's resources isn't "granting loot" in any
degraded sense, it just isn't happening — the relationship is **inherent**.
If yes — a kill means exactly the same thing whether or not
`AchievementService` is watching — it is **optional**.

Keep this distinct from Part 2's conceptual-vs-contingent test. That one
decides where code *lives* (nested sub-domain vs. peer domain), once, at
design time. This one decides how two already-separate peers *talk* for one
specific interaction, and can be answered differently for every pair.

```
Inherent, target known statically   → direct call (require + call)
Inherent, target varies by content  → effect table (11.2)
Optional, any number of reactors    → Signal (Fact, fired last)
```

**Inherent gets a direct call.** `DropService` calling `ResourceService
.grant(...)`. `CombatService` calling `ResourceService.drain(...)` once it
has resolved the final amount. One domain requiring another and calling its
validated public method is not sprawl — the sprawl was always one domain
needing to reach N *unrelated, optional* domains, which Facts solve.
Requiring one domain you inherently depend on is normal composition, and per
Part 10's dependency layering it is free as long as it points downward.

**Optional gets a Fact.** `AchievementService` reacting to `Combat.OnKill`.
A leaderboard reacting to `Player.Resources.Gold.OnChanged`. Zero-to-many
listeners, no return value, fired last, after the originating action has
already fully succeeded.

**The gap Signal genuinely cannot fill** is inherent-but-dynamically-targeted:
the caller needs to know the target's response actually completed, but the
target isn't known statically. Firing a Signal and hoping a listener applied
the damage is not different in kind from the `GoldManager` mistake (Part 8) —
using a zero-to-many broadcast to simulate a guarantee it was never built to
provide. That gap is what 11.2's table fills, and 11.2 is also where its
real cost (lost static traceability, mitigated by boot coverage validation)
is stated honestly.

**The cost of the table, restated so it isn't forgotten:** reading
`ParryService.luau` used to tell you everything it touches. Routing through
a label means the transitive dependency lives one file away, resolved by
string. That is a permanent trade of static traceability for flexibility.
It is worth it only where content genuinely varies the target — never as a
default.

---

### 11.5 — Signal: Facts, and Nothing Else

Every signal represents a **Fact** — something that has already,
unconditionally happened. `Fire()` calls every connected listener, no
exceptions, no privileged recipient, no return value.

```
Signal:
  - announces completed state changes
```

The validated-mutation guarantee does not live on Signal. It lives in
whichever Service method fires the signal as its own last step, using its
own validation, calling its own Entity/Component mutation, with nothing else
in the codebase given any other way to cause that same effect. If
`ResourceService` only exports a validated `grant()` and never exports raw
mutation access, there is no other door into Gold — and no `SetHandler`
concept is needed to create one.

#### Fact Signals and Cross-Domain Composition

`CombatService` confirms a kill. That kill needs to grant gold. It does not
require `ResourceService` and it does not know Gold exists. It fires
`Combat.OnKill(attacker, victimEntity)` as a pure Fact — the kill already
happened, fully, inside Combat's own authority, before the Signal was
touched.

`ResourceService` independently `Connect()`s to `Combat.OnKill`, runs its
*own* business rule (is this enemy lootable, for how much), and calls its own
validated `ResourceService.grant(player, "Gold", 10, "COMBAT_KILL")`.
`AchievementService` does the same thing off the same fact, with zero
knowledge of the others.

If killing a friendly NPC should apply a gold *penalty* instead, that
distinction lives entirely inside `ResourceService`'s listener — Gold's own
domain rule, decided by Gold, triggered by a fact it chose to react to.
`CombatService` never learns that gold penalties exist. This is the standard
**Domain Events** pattern, and it turns an N×M web of direct dependencies
into N publishers and M independent subscribers.

#### Protecting the Fact: Who May Fire

"A listener can trust a fired signal unconditionally" cannot rest on
everyone remembering not to misuse `Fire()`. If anything that requires a
registry gets the same raw Signal object as its owning Service, nothing
stops an unrelated module from firing `Gold.OnChanged(player, 99999)` and
every listener acting on a lie.

**The mechanism: fire capability is a return value, not a second view of the
object.**

```lua
-- The owning Service declares its fact and keeps the only fire-capable
-- reference in a local. Subscribers only ever hold a name.
local OnKill = SignalService.declare("Combat.OnKill")   -- returns the Signal

SignalService.on("Combat.OnKill", fn)   -- subscribe by name; no Fire access
SignalService.validate()                -- boot: every subscribed name was
                                        -- declared; aggregate and throw
```

This resolves an open gap an earlier revision left unanswered (registries
holding live `Signal.new()` objects while simultaneously requiring
owner-only fire). It also removes the need for a `GetListenerHandle()`
dual-view: access control comes from who holds the return value.

**Subscribing by name rather than by module reference is load-bearing for a
reason worth stating explicitly: place separation (Part 13).**
`AchievementService` cannot `require(CombatService)` to subscribe, because
`CombatService` does not exist in the Hub build. A name-keyed broker is what
lets a listener subscribe to a fact whose publisher is absent from its place.
`on()` must therefore be legal before `declare()` and buffer accordingly.

The registry file (`GlobalRegistry`) becomes a **vocabulary** — a flat,
readable list of every legal fact name — rather than a table of live
objects. It keeps the "one file lists every Fact in the game" property
without handing out fire rights.

#### Cardinality

A single skill activation that cosmetically represents multiple hits (Part
8) fires its Signal **once**, carrying the aggregate:

```lua
OnHit:Fire(attacker, target, totalDamage, hitsPerTarget, isCrit, newHp)
```

Server-side listeners are written expecting one fire per real activation
with a `hitsPerTarget` field, not an array to iterate. The client is not among
them — Signal never reaches the client, and the outbound EventTape diff
carrying this same payload is pushed by `CombatService` inherently,
independent of whether this Signal fires or who is listening.

#### Naming

Every signal name reads like a past-tense fact — `OnHit`, `OnDied`, never a
command. If a name in the vocabulary reads like an imperative (`DoAttack`,
`RequestPickup`), a Request or Intention has drifted into Signal's territory
and needs to be pulled back into a direct Service call.

#### Where Rejection Happens Instead

Signal never carries unconfirmed requests, so rejection lives in the plain
Service method call. `EventTape` routes a deserialized Event directly to a
top-level Service method by ordinary function call. The Service validates,
and if it rejects it simply returns (plus an explicit reject message when
the client has pending optimistic state — Part 5, Part 15). **No Signal of
any kind fires for a rejected Request or Intention.** Signal enters only
after the Service has already succeeded.

#### The API

```lua
Signal:Connect(fn)     -- register a listener; returns a handle with
                       --   :Disconnect(). Multiple listeners, any order.
Signal:Fire(...)       -- broadcast to EVERY listener. The only firing
                       --   method. Only the declaring Service holds a
                       --   reference capable of calling this.
Signal:DisconnectAll()
Signal:Destroy()
```

`Connect` returning a handle is not optional polish. Without it, a listener
can only be removed by holding its exact function reference — and anything
that wraps handlers in closures can never disconnect them at all. With
per-run dungeon instances subscribing to module-level signals, that is a
listener leak with no way to clean up.

**Two listener rules, since Signal offers no ordering guarantee:** listener
order is boot order, which is deterministic but implicit and unwritten. A
listener may not mutate state another listener on the same signal reads. If
you ever *need* ordered reactions, that is evidence the relationship was
inherent, not optional — use a direct call or a pipeline instead.

#### Boot Sequence

```lua
-- server/Main.server.luau  (any place)

-- 1. Services boot. Each declares the facts it owns and keeps the
--    fire-capable reference privately; each Connect()s to whatever facts
--    it wants to react to, by name.
CombatService:boot()
ResourceService:boot()
BuffService:boot()
StateService:boot()

-- 2. Everything that was subscribed must have been declared. Fails once,
--    loudly, listing every unresolved name -- not a scattered warn() per
--    entry that is easy to miss in engine output.
SignalService.validate()

-- 3. Same discipline, three separate small implementations (Part 12).
EventRoutingRegistry.validate()      -- every eventType resolves to a Service
BootValidation.checkEffectCoverage() -- every content effect type has a handler
BootValidation.checkPlaceManifest()  -- two-way presence check (Part 13)
```

Subscription must be legal before declaration, since boot order across
Services is not something a listener should have to know. `on()` buffers;
`validate()` is what turns a name that never got declared into a boot
failure instead of a silent no-op.

---

### 11.6 — Rejected Designs, Compressed

Kept because the reasoning that ruled each one out is more valuable than the
conclusion — but compressed, because the narrative of which revision said
what is not. The durable artifact is the *test* that catches it.

| Rejected | Why it failed | Test that catches it |
|---|---|---|
| Command Layer | Nothing lived there that wasn't passing through unchanged | Part 2 — "is it a layer, or a naming exercise" |
| `Signal:SetHandler` / `FireAndNotify` | The guarantee it chased comes free from an ordinary validated Service method; it would have made Signal carry two shapes depending on whether a handler was set | Part 11 — inherent vs. optional |
| `GoldManager` and per-resource Managers | Used a zero-to-many broadcast to simulate a guaranteed completion a direct return already provides | Part 11 — inherent vs. optional |
| Per-domain EventTape pipelines | Ordering cannot be guaranteed across N independent tapes | Part 12 |
| Self-dispatching `Event` objects | A `shared/` data object would depend on a server-only Service | Part 2 — data objects don't route |
| Unified `ModuleResolver` | Three different verbs after resolution (connect / call-with-return / instantiate) | Part 2, Test 3 |
| `EffectResolver.register()` | Registration scatters the vocabulary across N files; a flat table is readable in one screen | Part 12's routing-table decision |
| `SignalHelper` path→folder auto-wiring | Structurally supports only one listener per signal — the degenerate case a direct call already handles — while coupling runtime behavior to folder layout invisibly | Part 2, Test 3 |

**The general lesson underneath several of these, worth keeping: never infer
that a design was intentional or unintentional from what the code currently
does.** Most of this architecture is unbuilt by design (see the Status Note
at the top). Treating an unfinished implementation as proof of abandoned
intent is exactly backwards, and it produced at least one wrong correction
in this document's own history.

**The complementary lesson, learned the other direction: a design that has
been argued three times and built zero times is not settled, it is
unvalidated.** Arguing harder does not pressure-test a shape; a second real
use case does. Where this Part is marked PROVISIONAL, build the first real
case and let it disagree.

---

## Part 12 — The EventTape — Ordering, Deserialization, and Routing to Services

> **Status:** the routing model and centralization decision are SETTLED, and
> the code now matches them — the one-RemoteEvent-per-eventType controller and
> the handler-folder loader are both gone, replaced by `EventRouter` plus
> `EventRoutingRegistry`.
>
> **Implementation detail lives in `EventTape.md`, not here.** That document
> owns the file map, the two end-to-end traces, the wire message shapes, the
> recipe for adding an event type, and the current gap list. This Part stays
> the authority on every *why* below, and `EventTape.md` links back rather than
> restating any of it. Do not duplicate a rule across the two.

### The Centralization Decision — And Why It Was Almost Wrong

This revision considered, at length, splitting EventTape into one RemoteEvent
and one ordering buffer *per top-level domain* (one for Combat, one for
Inventory, one for Resource, and so on). Roblox allows creating as many
`RemoteEvent` instances as needed, and per-domain scoping has real appeal —
routing collapses into "which RemoteEvent fired," each domain can be
independently included or excluded per place (Part 13), and it matches how a
directory-organized Services tree already wants to be shaped.

**It was rejected, and the reasoning matters more than the conclusion:**
EventTape's ordering guarantee was never really about a Roblox wire-level
guarantee in the first place — Roblox does not strongly guarantee order
across different clients even on a single `RemoteEvent`. What actually
produces the guarantee is that everything lands in one shared buffer and is
processed in the order the single server thread actually received it — see
"Ordering Is Arrival Order, Not a Sort" below for exactly what this does and
doesn't promise. That only works if everything lands in the *same* buffer.
Split into N domain pipelines, and you get N internally
consistent orderings with no defined relationship between them — a kill
event and an unrelated gift-claim event landing in the same server frame
would have no way to agree on relative order anymore, because they were
never in the same race to begin with.

And splitting doesn't even save the thing it was trying to save: something
still has to decide `eventType/subType → Service method` regardless of
whether that decision happens via "which RemoteEvent fired" (boot-time) or a
routing table (runtime) — it's a wash, not a win, purchased at the cost of a
real guarantee.

**The calibration that actually matters:** most state mutations are order-
independent (two `ResourceService.grant()` calls to the same resource
commute — addition doesn't care which happened first). The cases where order
genuinely changes the outcome are narrower — Part 1's founding example, two
near-simultaneous combat hits on the same entity where one might kill it
before the other's effect would apply. Centralizing means you never have to
prove, case by case, which category a given interaction falls into — you get
one deterministic global sequence, always, for free.

**The conclusion: one centralized `RemoteEvent`, one `EventTape`, one shared
buffer**, for all traffic. `CombatService` and `ResourceService`
remain fully separate domains on the other side of routing — transport
topology and domain ownership are two independent axes, and centralizing the
pipe does not threaten domain separation at all.

One narrow, deliberate exception, not yet built: Roblox's `UnreliableRemoteEvent`
is a legitimate second channel for traffic that doesn't need EventTape's
ordering or delivery guarantee at all — purely cosmetic effects with no
gameplay consequence. That split is by "does this need the guarantee," not by
domain, and is a later optimization, not a foundational decision.

### Ordering Is Arrival Order, Not a Sort

This corrects something the rest of this Part still describes loosely as a
"buffer-and-sort" step, and it's worth being precise about, because the
precise version is simpler than what's currently built.

**Resolved: the sort is gone, and the reasoning is kept because it is the
argument for never adding one back.** The old `EventTapeSystem` assigned each
incoming tape a timestamp via `os.clock()` and sorted the processing buffer by
it. That sort was provably a no-op, and was removed rather than kept as
defensive-looking code that does nothing: the server is single-threaded and
cooperatively scheduled (Part 6),
`addToBuffer` never yields between receiving a tape and inserting it, so the
buffer is *already* in true arrival order by plain insertion — the timestamp
assigned to each entry is monotonically consistent with the order it's
already sitting in. Sorting a list by a key that already matches its own
order changes nothing. It's not just redundant, either — Lua's `table.sort`
has no stability guarantee for equal keys, and `os.clock()`'s resolution
isn't infinite, so in the rare case two entries land an identical timestamp,
the sort could theoretically *reorder* them relative to true arrival order,
which plain insertion-order processing never risks.

`EventRouter:drain` now processes the buffer in the order it was built, and
says so in a comment, because "there is deliberately no sort here" is the kind
of absence someone helpfully corrects.

**The timestamp outlived the sort it existed for.** `receivedAt` is still
stamped once per tape and forwarded to handlers, and today nothing consumes
it. Worth knowing before assuming it is load-bearing: the latency rewind
(Part 13) derives from `Player:GetNetworkPing()`, a server-measured value, not
from anything a tape carries. It is kept because it costs one `os.clock()` per
tape and is the only server-authoritative arrival time available — but it is
currently vestigial, not a dependency.

**What "ordering guarantee" actually means, now stated precisely:** EventTape
preserves the order the server actually received things in. It does not, and
never did, reconstruct a "true" or "fair" order between two different
clients — there isn't one to recover. Two players' hits landing in the same
server frame get processed in whichever order the server happened to receive
them, and that's the entire guarantee. This is a correction to Part 1's
founding story: EventTape was never solving "figure out the correct order
retroactively," it was always just "don't let anything scramble the order
that already existed." Keep this distinction in mind if a future mechanic
ever seems to need a *fair* cross-client ordering guarantee — EventTape does
not provide one, and nothing described in this document does.

**Optional, and genuinely your call, not a requirement:** if you ever want
event processing to land at one predictable point in the frame — rather than
inline, at whatever arbitrary instant each `RemoteEvent` happens to fire,
potentially interleaved unpredictably with the Scheduler's own ticks (Part
14) — a plain FIFO drain-once-per-tick is still worth keeping, with no
sorting: collect whatever arrived, process it in received order, once per
frame. If you'd rather process each event the instant it lands instead, that
is equally correct given everything above.

### What EventTape Actually Owns

EventTape's job, precisely, is: preserve arrival order, buffer and batch
traffic across a frame, and turn raw wire data into typed `Event` objects. It
does **not** decide what happens as a result of an Event — that decision
belongs entirely to whichever top-level domain Service receives it, and what
that Service does internally with a `subType` is that domain's own business,
not EventTape's concern. EventTape is the generic engine from Part 1's Second
Discovery, still true today: it knows nothing about what event types exist,
and it never needs to change when a new one is added.

### Deserialization — One Set of Rules, Both Directions

**This section previously described a design that no longer exists**, and the
difference is the whole point, so the old shape is worth stating: it preloaded
every `Event` *subclass* off the DataModel by naming convention, and called
each module's own `.deserialize()` to reconstruct itself. That gave every event
type two validation paths — its builder and its deserializer — and only one of
them faced untrusted traffic. A rule added to a builder was silently skipped
for anything arriving from a client, which is the half that actually matters.

What exists now: `EventDeserializer` is a plain stateless module with one
function. It resolves the class from `EventRegistry` and calls the same
`Event.build` the fluent builder calls. There is no per-type `deserialize`,
nothing to preload, and no second path to drift.

The Generic Engine plus Declarative Config framing (Part 2) still holds, just
one level down: `EventSchema` is the engine and each type's `schema` is the
config. `EventDeserializer` only answers *which class is this* — everything
after that is shared with the authoring path by construction.

### Declaring an Event — One File Per Type

**Adding an event type is one file. Nothing else changes.**

That file declares everything about the type: its subTypes, its parameters,
the builder methods that set them, and the accessors that read them back.

```lua
-- types/CombatEvent.luau
CombatEvent.eventType = EventType.COMBAT

CombatEvent.SubType = table.freeze({ MELEE = "MELEE", SKILL = "SKILL", ... })

local schema: EventSchema.Schema = {
    targetId = { type = { "string", "number" } },
    skillId  = { type = "string",
                 requiredFor = { CombatEvent.SubType.SKILL,
                                 CombatEvent.SubType.ULTIMATE } },
}
CombatEvent.schema = schema

local Builder = EventBuilder.extend(CombatEvent)
function Builder:withTargetId(targetId: string | number) return self:_set("targetId", targetId) end
function Builder:withSkillId(skillId: string) return self:_set("skillId", skillId) end
```

**Closed vocabularies are referenced, never retyped.** `eventType` comes from
`EventType`, and `requiredFor` from the class's own `SubType` — both are
constants, not literals. `EventTape.md` has the full step-by-step and the list
of what catches each omission.

Authoring is fluent:

```lua
EventFactory.create(CombatEvent)
    :withSubType(CombatEvent.SubType.SKILL)
    :withTargetId("ENEMY_1")
    :withSkillId("CLEAVE")
    :build()
```

**Why fluent and not a payload table.** The methods *are* the documentation
— type a colon and the editor lists exactly what this event accepts, with the
argument type on each one. A `{ ... }` table gives you nothing until you
already know the field names, and `{ id = "asdf" }` looks identical whether
it is right or wrong. This is the single most important property of the
authoring API and everything else bends around keeping it.

**Why the methods are hand-written.** They could be generated from the
schema, and that was tried. A generated method is invisible to a language
server, so generating them destroys the one thing they exist for. The
duplication that generation would have prevented is closed by a **validator**
instead: `EventRegistry.validate()` asserts, at boot, that every schema field
has a matching `:withX()` and every `:withX()` maps to a real field. Forget one
and the server refuses to start, naming the method you owe it. *Check the
invariant; don't generate around it.*

**Where each rule is enforced, and why it matters:**

| Rule | Enforced | Why there |
|---|---|---|
| One field's type / content check | `:withX()`, immediately | The error names the line that is wrong |
| `required`, `requiredFor`, defaults | `build()` | Cannot be judged until every field is in |
| Everything, again | deserialization | Same engine, so a payload the builder rejects is rejected off the wire too |

That last row is the property worth protecting. A rule enforced only in a
builder applies to hand-built events and is silently skipped for anything
arriving from a client — which is the half that actually matters.

**No Event subclasses.** There is one `Event` instance class. An earlier
model gave each type its own subclass *and* its own builder — two files per
type, forever, each repeating the same shape of checks. Part 7's inheritance
exception for `Event` classes exists for that model and is no longer needed.

### Which Services Get an eventType

Not one per service. This came up repeatedly, so the rule is stated once,
here, rather than inferred from the routing table.

**An eventType is a routing key for traffic arriving over EventTape.** It
exists only where a client Request or a server Intention has to reach a
top-level domain and be authorised there.

| Kind | Gets an eventType? |
|---|---|
| **Domain** service | Only if a client originates the action. `COMBAT`, `INVENTORY` — but not `DungeonService`, `DropService`, `LevelService` or `ZoneService`, because nothing a client sends starts there |
| **Infrastructure** | Only where it owns a client-facing flow. `SESSION` does (ready, teleport request); `DataService` never does |
| **Authority** service | **Never.** A client does not say "grant me gold" — gold moves as a consequence of a domain action the server already decided on. Authority services are leaves: they execute, they do not authorise |
| **Driver** (`AIService`) | **Never.** Intentions are direct Service calls, not EventTape traffic (Part 5) |

**One eventType per top-level domain, and everything nested under that domain
shares it.** `SkillService` lives inside `CombatService`, so a skill
activation is `COMBAT/SKILL` — not its own top-level type. Dispatch *within*
a domain is that domain's own business from the routing step onward, which
is exactly what keeps the routing table one row per domain instead of one row
per subType.

That nesting is structural, not cosmetic. `SkillService` is a **child module
of `CombatService`** (`services/domain/CombatService/init.luau` plus
`SkillService.luau` beside it), not a sibling in `domain/`. Sibling folders
would imply peers that call each other freely; the real relationship is
one-directional — Combat calls into Skill, never the reverse — and the folder
layout should say so. It also means the place manifest declares **one**
public-facing authority for the whole domain: a sub-domain is not a manifest
entry.

**A worked consequence:** `InventoryService` moved from authority to domain
on evidence rather than taste. Part 7's own example has
`InventoryService.pickup` calling `DropService.isInRange` and
`ZoneService.canPickupHere` — and an authority service is a leaf that may not
require a domain service. A service that inherently needs two of them cannot
be one. `Equipment`/`Resource`/`State`/`Stat`/`Buff` stay authority because
their operations are pure mechanics that never consult another domain.

### Routing — Resolves Only to the Top-Level Domain

This is the piece that was actively redesigned across several conversations,
and it's worth recording both what was considered and why the final answer
was chosen, so it never gets re-litigated.

**Rejected option: self-dispatching Events.** The idea was to let each
`Event` subclass know which Service it should call — e.g. `AttackEvent
:dispatch()` calling `CombatService.OnAttack(self)` directly. This was
rejected for a concrete, structural reason, not a stylistic one: `Event`
classes live in `shared/`, loaded on both client and server, while Services
are server-only. An `Event` object reaching upward to call a Service would
either break on the client (the `require` for the Service doesn't resolve)
or force Services to become dual-environment-safe purely to satisfy a data
object's convenience — undermining the place-based security model in Part
13, which depends on server-only code never being loaded anywhere a client
could reach it.

**Rejected option: a folder of one-line handler modules.** An earlier draft
considered a `handlers/` folder where each file returns `{ eventType, handler
}`, auto-loaded the same way `EventTapeSystem` currently loads them (and, as
of this revision, still literally does — this is flagged as unfinished work
below). This works, but produces file-per-type ceremony for something that
is, in truth, just a lookup table — and it scatters the full picture of
"which event goes to which service" across N files instead of one place a
developer could open and read end to end.

**Rejected option: a unified `ModuleResolver` covering Signal wiring, Event
routing, and Component loading behind one generic, flexible engine.**
Considered during this revision, and rejected once it became clear the three
don't share behavior past "look up a module" — Signal wiring connects a
persistent listener (fire-and-forget, many listeners per signal), Event
routing calls a function once and cares about its return value (exactly one
recipient, accept/reject matters), and Component loading (Part 7,
`ComponentLoader`) enumerates whatever's present and instantiates it (no
declared list at all, the opposite direction from the other two). Unifying
them would require a callback/strategy parameter per call site — which is
itself the "config has become code in disguise" smell Part 2 already warns
against. Per Part 2's own threshold (two or three genuinely different cases:
write them explicitly; ten or more sharing real structure: build the
engine), this is the "write them explicitly" bucket. What *is* shared across
all three, and should be, is the discipline, not the mechanism: validate
against a declared list at boot, fail loud and aggregated. See Part 11.2's
boot coverage check for the same conclusion applied to effect dispatch, and
Part 19 for why the Signal side of this went further and deleted its
resolver entirely rather than making it deterministic.

**The actual answer: a single flat, server-only routing table**, resolving
only as far as the top-level domain, matching the same declarative-table
style `GlobalRegistry` already uses successfully for Signals:

```lua
-- server/eventTape/EventRoutingRegistry.luau
-- Server-only. One flat table, one entry per top-level domain. Grows by
-- one line when a new domain is added — not one line per subType.
-- This is the single place a developer can look to see the entire map of
-- "which Service handles which incoming top-level eventType."

local CombatService    = require(script.Parent.Parent.services.CombatService)
local InventoryService = require(script.Parent.Parent.services.InventoryService)
local ResourceService  = require(script.Parent.Parent.services.ResourceService)

return {
    COMBAT    = CombatService.OnAttack,
    INVENTORY = InventoryService.OnAction,
    RESOURCE  = ResourceService.OnAction,
}
```

`EventTapeSystem` reads this table instead of loading a folder of separate
modules — **this is flagged as unfinished work**, since the code as it
stands today still loads a `handlerFolder` per the rejected pattern above,
and `EventTapeController` still creates one `RemoteEvent` per `eventType`
rather than the single centralized one decided above. Both need to change
when this is actually implemented; neither is a live design question anymore.

For each deserialized `Event`, `EventTapeSystem` looks up the top-level
`eventType` in this table and calls the mapped function directly — a plain
function call, exactly the same shape as any other Service method call, and
explicitly **not** a Signal. Dispatch *within* a domain — e.g. `CombatService`
deciding whether a `MELEE` or `RANGED` subType goes to a different internal
handler — is that domain's own business from this point forward, and may
reasonably use its own directory-based auto-wiring internally (see Part 13),
validated the same way, but is no longer EventTape's concern.

This table living in `server/`, not `shared/`, is what makes the upward
dependency on Services legitimate — server-side code is exactly where a
reference to a Service belongs. `Event` classes stay exactly as dumb and
purely-shared as `EventDeserializer` already assumes they are.

**A mechanical note for whenever a version of this registry needs to work
across multiple places sharing one source tree (Part 13):** it must be pure
declarative data — names or paths — not eager `require()`s of module
references at the top of the file. A place that doesn't include a given
Service (e.g. Hub not including `CombatService`) would error immediately on
an eager `require()` for something that was never included in its build.
Resolution has to happen lazily, per place, only for entries that are
actually present in that place's manifest.

### The Full Corrected Pipeline

This is the complete, current, true model — the one to trust over any other
description anywhere else in earlier drafts of this document:

```
Client
  ↓
RemoteEvent  (transport only — ONE centralized instance, see above)
  ↓
EventTape  (ordering, buffering — never decides anything)
  ↓
Deserialize  (EventDeserializer builds the typed Event object; the Event
              validates its own shape — local self-consistency only)
  ↓
Route  (EventRoutingRegistry maps top-level eventType → Service method; a
        plain function call, never a Signal)
  ↓
Service  (owns game rules and orchestration; this is where a Request or
          Intention can be rejected — see Part 5; internal subType dispatch
          happens here, not in EventTape)
  ↓
Entity mutation  (via Component setters; the Component enforces its own
                  local invariant, per Part 3 and Part 7)
  ↓
Signal:Fire()  (fired by the Service, ONCE per real activation — even if it
                represents several cosmetic hits, Part 8 and Part 11 — only
                after mutation succeeded; announces the confirmed fact)
  ↓
Replication / listeners  (HUD updates, effects, achievement checks, combo
                          detection, etc. — react to truth, never judge it)
```

Every part of this document that discusses combat, resources, equipment, or
any other domain assumes this exact shape. If any other section appears to
describe a different shape, this Part and Part 5 are the ones to trust.

### Outbound Traffic — EventTape's Other Direction

EventTape is also used, in the outbound direction, to deliver a stream of
resulting effects to clients in guaranteed order — damage numbers, animation
triggers, sound cues, all needing to land at the client in the sequence they
actually occurred. This still uses the same ordering machinery described
above; it is simply traffic flowing server-to-client instead of client-to-
server.

**Correction, applying Part 11.4's Direct Call, Table, or Signal test:**
this outbound push is pushed *directly* by the originating Service, as its
own inherent last step — the same domain that resolved the action, not a
Signal listener reacting to it afterward. Telling the client what happened
is part of what the action already means, the same reasoning Part 8 applies
to `ResourceService.grant`/`.drain`. Signal is never involved in getting
something to the client at all — Signal doesn't cross the client/server
boundary, and nothing client-side can ever be a Signal listener. Whatever
Fact the originating Service *also* fires (for genuinely optional
server-side reactions) is a separate, later, unrelated step — not the
mechanism the client update depended on.

**This is specifically what the Damage Number System (Part 15) consumes.**
The current HP *value*, for something like a health bar fill, is a plain
replicated Attribute per Part 15's HUD pattern — Roblox attribute replication
only guarantees the client eventually sees the final value, not every
intermediate one, which is fine for a value the client just needs to display
correctly. But the *discrete hit event* — "this activation dealt this much
total damage, represented as this many cosmetic hits" — is not a value to
watch, it's a thing that happened, and that needs an explicit stream. That's
exactly the outbound EventTape direction, and it works identically for any
resource that might want popup-style feedback later (a "+50 Gold" popup would
use the same mechanism), not something HP needed a bespoke service for.

**Synchronized playback for shared multi-client moments.** Some outbound
broadcasts need more than ordering — they need multiple clients to perceive
something at the same *relative* moment despite differing latency. The
multiplayer combo system is the confirmed case (both participants' shared
animation needs to be sync'd off the server's clock, not local receipt time,
or it visibly desyncs between them), and the domain ultimate and weapon
finisher cinematics almost certainly need the same treatment. The pattern:
the outbound payload carries a server timestamp anchor (`playAt = serverTime`),
and each receiving client schedules playback relative to that anchor instead
of playing immediately on receipt. This should be designed once, as a shared
shape any synchronized-cinematic broadcast can use, rather than solved
separately for combos, ults, and finishers. Not yet implemented — flagged
here as a known, real piece of design work.

---

## Part 13 — The Security Model — Places, Absence, and Two-Way Validation

> **Status:** SETTLED. The absence-over-disconnection argument and the
> two-way boot check are the two ideas worth keeping. UNBUILT: the
> role-based service tree and the per-place manifests do not exist yet.

### Three Places, Not Two

An earlier version of this section only accounted for two places, Hub and
Dungeon. The game design confirms a third: **Farm Zone** — its own place,
its own `project.json`, reached by its own teleport, with its own DataStore
persistence checkpoint (per the Core Gameplay Loop and Section 14 of the
design document). Every Service Registry entry (Part 10) is now scoped to
which of the three places it's allowed to exist in, and any future security
reasoning in this document should default to checking against all three, not
two.

### What the Client May Report

```
ALLOWED — intent only:
  "I pressed attack"
  "I clicked enemy ID X"
  "I activated skill slot 2"

NEVER — values or state:
  "I dealt 450 damage"
  "My HP is 80"
  "I was away for 3 hours"
  "I earned 200 gold"
```

### Mitigate, Don't Chase — And Never At The Cost Of Feel

> **Status:** SETTLED 2026-08-23. Stated once here because it calibrates
> everything above, and because an absolutist reading of that table produces
> bad decisions on its own.

The table is absolute about **values**, and it should be. But some things the
client controls are not values it reports — they are facts about its own body
that it genuinely owns, because Roblox gave it network ownership. A player's
limb positions are the live case (`HitDetection.md` 7.4: every one of a
player's ten hurtbox zones rides a client-driven limb).

For those, "never trust it" is not an available option. The available options
are *ban the whole capability* or *bound it*, and the standing answer is:

> **Bound it. Aim to make cheating expensive and unrewarding, not impossible —
> and never buy a little more certainty with a lot less responsiveness.**

**Three things this licenses, all of which look like weakened security until
the alternative is priced:**

| | |
|---|---|
| **Clamp rather than reject** | pull an implausible value into a plausible envelope instead of refusing it. Rejecting punishes a laggy honest player harder than it punishes a cheater, who simply stays inside the bound |
| **Cost counts as a mitigation** | an exploit that takes real engineering to build and maintain, for a payoff that is purely cosmetic or purely defensive, mostly does not get built. That is a genuine deterrent, not a hopeful one |
| **Detection is a later layer, not a prerequisite** | a bound that catches the casual case ships now; watching for someone who beat it is a separate, optional job that never blocks the first one |

**The error asymmetry, which is the part that is easy to get backwards.** Every
bound can be wrong in two directions and they are not equally bad:

```
too loose  ->  permits a bit more cheating
too tight  ->  silently breaks the game for honest players on bad connections
```

**A wrong bound punishes the honest before it inconveniences the dishonest.**
Pick generously. This is the same asymmetry already driving *"defense is
generous, offense is exact"* and the deliberately over-wide broadphase margin,
and it points the same way in all three.

**What this does NOT license**, so it is not read as a general relaxation:
nothing here weakens the NEVER list. A client still may not report a value, and
the server still computes every outcome. This is about capabilities the client
*already has* by construction — not about extending it new ones.

### Latency-Tolerant Hit Registration

When the server receives a hit report, it checks where the enemy was some
window in the past, not where it is now, to account for round-trip latency —
a player who clicked on an enemy that had already moved by the time their
click reached the server should still register the hit, because from their
perspective the enemy was there. Without this, players on any real network
connection miss hits constantly and the game feels broken.

**How far back to rewind is derived from server-observed latency, never a
client-supplied value** — this follows directly from the existing rule
against trusting client-reported elapsed time (Part 6), applied to latency
instead of AFK duration for the same reason: a client that could claim its
own latency would have an obvious incentive to lie about it, either to widen
its own rewind window or to make its shots register more favorably. Roblox
exposes an actual server-side measurement for this — `Player:GetNetworkPing()`
returns a real, server-observed round-trip time, not a self-reported claim —
so this is buildable as stated, not aspirational. The specific rewind-window
math (how many milliseconds of buffer, how position history is stored and
queried) is implementation detail; the one architectural commitment is that
the input to that math is always server-measured, never client-supplied.

**`HitDetection.md` owns the whole of that implementation** — the rewind
arithmetic, the position history, the hit volumes, and the DETECT phase it
adds between VALIDATE and RESOLVE. It also amends the client-report table
directly above with one conditionally-allowed field; read it before relying
on that table being complete.

This is the player-side half of managing perceived latency. The server-side
half — for when an NPC is the one attacking a player — is the Telegraph/
Execute pattern described fully in Part 5. Together they cover both
directions of "who is attacking whom," for the same underlying reason:
server authority is correct and necessary, but naive server authority feels
bad without a deliberate mechanism to smooth over network delay.

### Absence Is Stronger Than Disconnection

If `CombatService` is loaded in the Hub but its listeners are disconnected, a
determined exploiter who bypasses the disconnect has a live code path. The
handler is in memory.

If `CombatService` is never loaded in the Hub because `hub.project.json`
excludes it, there is no handler to exploit. No code path. Nothing in memory.

This is also the concrete reason `EventRoutingRegistry` (Part 12) must live
in `server/`, never in `shared/` — anything a client can load, a client can
be tricked into revealing the internal shape of, even if it can't call it
usefully. Keeping the routing table server-only means the mapping of event
types to Services is never present on the client at all.

### The Replication Boundary — What "Shared" Actually Means

**`ReplicatedStorage` is not a shared folder. It is a broadcast.** Everything
in it is replicated to every client, and an exploiter can read and decompile
any ModuleScript there — **whether or not a LocalScript ever requires it**,
because the instance and its bytecode replicate regardless of use. Only
`ServerStorage` and `ServerScriptService` are never replicated.

This is worth stating explicitly because an earlier revision of this document
said the Content Layer "lives in `src/shared/definitions/`", and following
that literally put every drop rate, boss stat block, resource floor and
behaviour tag into a folder any client could dump.

The correct threat model, stated precisely so it is neither over- nor
under-sold: a client **cannot** change server behaviour by editing its local
copy — the server runs its own authoritative copy, so this is not an
exploit vector. What it is, is **information disclosure**: drop rates,
rarity weights, boss thresholds, and the complete list of the game's
internal event names. For a game with rare drops that is a real loss, and
it also costs join time and client memory to replicate data no client uses.

**Three trees, and the test for which one something goes in:**

| Tree | Maps to | Contents | Test |
|---|---|---|---|
| `src/shared/` | `ReplicatedStorage` | Event classes, EventTape, the Signal class, RemoteEvents, UI templates, animation manifests | Does the **client** genuinely execute this? |
| `src/serverShared/` | `ServerStorage.Shared` | Components, definitions, the server signal vocabulary | Server-only, but shared **between places** |
| `src/<place>/server/` | `ServerScriptService` | Services, entities, routing, resolution, boot | Server-only and specific to this place |

The middle tree is the one that is easy to miss. Code shared between the
experience's *places* is not the same thing as code shared with *clients* —
those are different axes, and `ReplicatedStorage` only ever answers the
second one. Each place's `.project.json` maps the same `src/serverShared`
into its own `ServerStorage`, which is how places share server code without
any of it crossing to a client.

**Default to `serverShared`.** Move something into `src/shared/` only when a
client demonstrably executes it, and treat each addition as a deliberate
disclosure. Putting a definitions table there "so the HUD can read the
name" leaks the whole table; ship the display name in the outbound payload
instead.

### Which Services Exist Where — The Persistence Test

Place scope is not picked service by service on instinct. The test:

**Does this service read or write data that survives a teleport? If yes, it
exists in every place, and it is identical in every place.**

Save data written in the Hub is read in the Dungeon. If `LevelService`'s
growth curve differs by place, saves silently diverge and cannot be
un-diverged afterward. That risk is what makes this a hard rule rather than
a preference.

What falls out of it, and it is not a coincidence: **the authority layer
(Part 10) is universal precisely because it is the only thing that touches
persisted state.** Domain services can be place-scoped because they never
persist directly — they route through the authority layer. `ShopService`
moves gold, but through `ResourceService.drain`, so Shop stays Hub-scoped
while the persistence stays universal.

Combat is the cleanest case in the other direction: HP is server-memory only
and never crosses a teleport (Part 10), so Combat persists nothing and is
free to be Dungeon-only.

### A Service Is Never *Different* Per Place

There is never a `CombatService` in the Hub that behaves differently from
the one in the Dungeon. A service is **present or absent** — never two
implementations behind one name. Two implementations diverge, and the
divergence is invisible precisely because the name is the same.

Cross-place variation goes in exactly one place: **content**. Same code,
different declarative data. If the Dungeon ever gets a shop, it is the same
`ShopService` included in a second place with a different catalog entry in
the Content Layer — not a `DungeonShopService`.

### Never Mock a Missing Service

A tempting shortcut: in the Hub, where combat doesn't exist, stand up a
harmless `NullCombatService` so ability requests "resolve" into nothing.
Don't. It breaks the thing this Part is built on.

- **It reintroduces the code path.** The whole argument above is "there is
  no handler to exploit, nothing in memory." A mock is a handler in memory,
  in the exact place the model claims has none — and it will grow, because
  the first time someone wants buffs to work in the Hub, the harmless no-op
  gains a branch.
- **Auto-resolving to success is worse than rejecting.** The client
  reconciliation contract (Part 15) is built on pending actions being
  confirmed or rejected. A place that always confirms trains every
  client-side path on a world where requests never fail — and the first
  place that actually rejects is the Dungeon, in combat, under latency.

**What to do instead — the concern splits cleanly in two:**

*A cosmetic ability in a place that has no combat is a pure client feature.*
The client knows what place it is in. It plays the animation locally and
**never sends the request**. That is not a mock service, it is a local
animation: zero server architecture, nothing in the routing table.

*A client that sends `COMBAT` in the Hub anyway is a security event.* The
Hub's routing table has no `COMBAT` entry, so the request is unroutable and
gets rejected — one generic line, identical in every place, no mock:

```lua
local handler = EventRoutingRegistry[event.eventType]
if not handler then
    return reject(player, event.id, "UNROUTABLE")
end
```

The feature is client-side. The absence is a security property. They are
unrelated concerns, and the mock idea only looks appealing when they get
fused.

### One Shared Services Tree, Scoped Per Place

Services live in one shared source tree, never duplicated per place. Each
place's `.project.json` decides which subset of that tree is actually
included in its build — the same Rojo mechanism already used for
`hub.project.json` / `dungeon.project.json`, extended to a third
`farmZone.project.json`. This preserves the absence guarantee: a Service
excluded from a place's `.project.json` structurally does not exist there.

**Organize folders by role; declare place membership in the project files.**

```
src/server/services/authority/   ResourceService, StateService, StatService,
                                 BuffService, EquipmentService, InventoryService
src/server/services/domain/      CombatService, DungeonService, DropService,
                                 ShopService, ZoneService, LevelService, ...
src/server/services/infra/       SessionService, DataService, CinematicService
src/server/services/drivers/     AIService, AFKService
```

An earlier revision organized these folders **by place** (`server/hub/`,
`server/dungeon/`, `server/farmZone/`, `server/common/`). That works only
while every service is either universal or exactly one place — which is true
of today's registry and stops being true the moment a service belongs to two
of three. A Dungeon shop, already a live possibility (Part 10), has no folder
under that scheme; you would need `server/hubAndDungeon/`, and then another
folder for the next such case.

Folder layout is a *code* concern and should stay semantic. Place membership
is a *build* concern and belongs in the build files. Enumerating modules per
`.project.json` is more verbose, but the verbosity is safe here specifically
because of the two-way boot check below — a typo fails loudly at boot rather
than silently shipping a place with a missing system.

**Each place declares its own required subset — not "try to load everything,
skip what's missing."** Two situations need opposite handling:

- A Service a place *does* declare as required, but it's missing from the
  build — that's a bug (a `.project.json` misconfiguration, a typo), and
  should hard-fail at boot, same as any other declared-and-missing check in
  this document (Part 16).
- A Service a place *never* declared — skip is correct, but should be
  actively **verified absent**, not assumed absent. If it's somehow present
  anyway (a leaked `.project.json` inclusion), that should also hard-fail.

This two-way check — declared-and-missing errors, present-but-undeclared also
errors — turns "absence is stronger than disconnection" from an assumption
you trust into a guarantee you verify every time the server boots.

---

## Part 14 — The Update Loop — The Scheduler

> **Status:** SETTLED, UNBUILT. Small enough to build in an afternoon
> whenever the first ticking Service exists.

Previous versions recommended each service subscribe to `RunService.Heartbeat`
independently. A reviewer flagged this correctly: most systems don't need 60Hz
updates, and independent subscriptions at full frame rate waste CPU.

The revised approach: one central Scheduler that runs each system at its
required frequency.

```lua
-- server/Scheduler.server.lua
local Scheduler = {}

-- Declare update frequencies per system
local schedule = {
    { service = BuffService,      hz = 60  },  -- expiry must be frame-accurate
    { service = ResourceService,  hz = 20  },  -- regen: 20Hz is more than enough
    { service = AIService,        hz = 10  },  -- every entity with an aiState;
                                               --   per-profile pacing (bosses 10Hz,
                                               --   pets 4Hz) is AIService's own
                                               --   business, not the Scheduler's
    { service = AFKService,       hz = 1   },  -- AFK recalc: once per second
}

-- Each service gets a dt and only ticks when its interval is due
local accumulators = {}
for _, entry in ipairs(schedule) do
    accumulators[entry.service] = 0
end

RunService.Heartbeat:Connect(function(dt)
    for _, entry in ipairs(schedule) do
        accumulators[entry.service] += dt
        local interval = 1 / entry.hz
        if accumulators[entry.service] >= interval then
            accumulators[entry.service] -= interval
            entry.service:tick(interval)
        end
    end
end)
```

One Heartbeat connection. Each service ticks at its declared frequency.
Adding a new ticking system: one line in the schedule table.

**Per-entity gating is the Service's own job, not the Scheduler's.** The
Scheduler only knows "call `AIService:tick(interval)` at 10Hz" — it has no
concept of individual bosses, pets, dungeon instances, or state flags. When
Part 9's `StateService` says a specific boss is FROZEN or DYING, it's
`AIService:tick()` itself that iterates its own list of active AI entities
and skips the ones currently flagged, exactly the same way it would skip any
other entity not due for a decision this tick. The Scheduler stays completely
unaware of this — it never needs to change no matter how many new per-entity
gating conditions get added later, which is the point of keeping it generic.

**This is also why per-creature pacing does not belong here.** Bosses want
decisions ~10 times per second; pets are invisible at 4Hz. That is one
`hz` (or `decisionInterval`) field on the AI profile in the Content Layer,
skipped by `AIService:tick()` for entities not yet due — not a second
scheduler row and not a second Service. An earlier revision listed
`BossAIService` and `PetAIService` separately here; see Part 10 for why they
are one Service with per-profile decision modules.

BuffService at 60Hz checks expiry accurately. AI at 10Hz makes decisions ten
times per second — more than enough for responsive boss behavior, and
comfortably inside the ~100ms slop tolerance already built into the
Telegraph/Execute pattern's timing (Part 5). ResourceService regen at 20Hz is
smooth.

If the optional FIFO drain from Part 12 is used, it drains once, before any
scheduled service ticks run for that frame — so a Service's tick always sees
whatever EventTape delivered this frame already applied, never mid-flight.

---

## Part 15 — The Client Architecture — Prediction, Reconciliation, and What the Client Owns

> **Status:** PROVISIONAL, UNBUILT. This is the least pressure-tested
> Part in the document — prediction and reconciliation have never met a real
> latency case here. Expect the first real implementation to disagree with
> some of it, and let it.

This Part was thin in earlier revisions — mostly the HUD-watches-Attributes
pattern and a brief mention of optimistic animation. This revision adds the
actual contract for client-side prediction, since the game design leans on
responsiveness (immediate animation, immediate damage numbers, immediate HP
bar movement) in a way that needs more than "play it and hope."

### The Golden Rule, Unchanged

The server is the source of truth for anything that can affect game state.
The client is a display layer — but a display layer that's allowed to guess
ahead of the server for responsiveness, as long as it can gracefully correct
itself when the guess is wrong.

### What the Client Owns

```
Visual state:     animations, particles, camera position
Predicted state:  optimistic display before server confirms
Display values:   read from replicated Attributes — never authoritative
```

### The HUD

The HUD watches replicated Attributes for values (current HP, Gold, etc.). It
never writes. It never calculates the authoritative value.

```
Server:     entity.resources:set("Gold", 1250)
            → Attribute "Gold" replicated to client

Client HUD: Attribute changed fires
            → GoldDisplay:update(1250)
```

If the HUD breaks, gold is fine. If gold logic changes, the HUD still works.
Debugging scope: either the server isn't replicating, or the display code has
a bug. It cannot be a game logic bug because the HUD has no game logic. This
is the right pattern for *values a player needs to see correctly* — it is
**not** the right pattern for *discrete events a player needs to perceive
individually*, which is the distinction the next section exists to draw.

### The Controller/Manager Relationship

Client-side, a Controller (e.g. `HealthBarController`) needs a way to call
back into the Manager that owns its underlying logic and state (e.g.
`HealthBarManager`) — for example, to read current values when first
displaying something, rather than waiting for the next Signal announcement.
`BaseManager` is responsible for handing that reference down when it
initializes a Controller. See Part 19 for the current bug in this handoff
and its one-line fix.

### Optimistic Prediction and Reconciliation

This is the actual client-side counterpart to Part 5's Request/Intention/Fact
model, and it wasn't fully specified before this revision.

**The animation contract:**

```
Client:
  1. Player presses attack
  2. Play the attack animation immediately, optimistically — before the
     server has responded at all
  3. Fire one Event via the centralized RemoteEvent (Part 12), with its
     own UUID (Part 5)
  4. Record eventId → currently-playing animation handle in a small local
     "pending actions" map

Server:
  5. Validate, resolve (Part 5, Part 8)
  6a. VALID → push the outbound EventTape confirmation, tagged with the same
      eventId, carrying totalDamage / hitsPerTarget / isCrit / newHp. (The Fact
      Signal also fires, separately and server-side only — it is NOT what
      reaches the client. Signal never crosses the wire; see Part 11.5.)
  6b. INVALID → send an explicit small reject message, also tagged with the
      same eventId — see the note below on why this differs from Part 5's
      general "rejected Requests get no response" rule

Client:
  7. Look up eventId in the pending-actions map
  7a. Confirmed → let the animation finish naturally; fabricate the
      cosmetic damage-number cascade and HP bar drain from the aggregate
      result (Part 8, Part 12)
  7b. Rejected → cancel or reverse the animation immediately
  8. Remove the entry from the pending-actions map either way
```

**Why this is a deliberate, narrow exception to Part 5's silent-rejection
rule:** Part 5 says a rejected Request produces no Signal and no response —
just a server-side warning log. That's correct when nothing is waiting on an
answer. But a client with an animation already playing optimistically *is*
waiting on an answer, and silence is ambiguous to it — it can't distinguish
"rejected" from "still processing" from "the response was lost in transit,"
and would have to fall back to a timeout before correcting, which means a
mispredicted animation could keep playing for a visible, awkward stretch
before it's fixed. So: for player-Request flows specifically that have
pending client-side optimistic state, the server sends an explicit small
reject message. Everything else in Part 5 (Intentions, and Requests with no
optimistic client state riding on them) keeps the original silent-rejection
behavior.

**Cleanup and timeouts, stated generally rather than per-case:** any pending
optimistic client action needs a bound. If no server response arrives within
some short window (dropped packet, extreme latency), the client should treat
it as an implicit failure, revert the animation, and remove the pending-
actions entry on its own, rather than waiting forever. The specific timeout
value and exact per-feature cleanup behavior is implementation detail, not
architecture — but the *shape* (every pending action needs a bound; it does
not get to leak indefinitely) is a real rule that applies everywhere this
pattern is used, and should not be re-derived separately for every feature
that uses it. The one broad case worth naming explicitly: if a player leaves
entirely, all of their pending actions and playing animations should be torn
down as part of normal cleanup — not handled as a special case of this
pattern.

### Client-Side Value Prediction

Beyond animation, the client can also predict the *number* it expects a hit
to resolve to, not just the fact that a hit is happening — showing a damage
number and starting the HP bar's drain animation before the server's answer
arrives, then reconciling if the server's real number differs.

This requires the damage formula itself to be **shared code**, not
server-only — both sides need to run the literal same calculation for the
client's guess to have any chance of matching the server's answer. This is a
deliberate, narrow carve-out from Part 13's normal server-only-combat-logic
default, and it's safe specifically because every input the formula needs
(the attacker's own stats, the target's displayed defense) is already
something the client legitimately has access to for display purposes — no
hidden value or secret RNG seed needs to be exposed to make this work. If a
future formula ever needs an input the client shouldn't see, that input
can't be predicted client-side and this pattern doesn't apply to it.

**Reconciliation when the prediction is wrong** (e.g. the target gained an
armor buff between the client's click and the server's resolution — the
server, being authoritative, applies its own state at the moment it actually
resolves, which may have changed since the client guessed): the *displayed
number* can pop immediately, since it's cheap to correct visually and
players don't scrutinize an exact digit. The *HP bar's animated drain*,
however, should be paced deliberately slower than the number pop — this
buys time for the server's authoritative correction to arrive before the bar
would visibly need to snap or pop to match it, which is the part a visible
correction actually looks bad on.

### The Damage Number Pool

Pre-allocated pool of 80 ScreenGui TextLabels. Never created at runtime. Recycled.
This is what actually consumes the outbound EventTape stream described in
Part 12 — the server sends one aggregate result per activation
(`totalDamage`, `hitsPerTarget`, `isCrit`), and this system is responsible for
fabricating a staggered, cosmetic cascade of `hitsPerTarget` individual numbers
from it, not for receiving `hitsPerTarget` separate server messages.

```
On load:          create 80 TextLabels, all in available pool

On spawn:         pull from available
                  if empty: steal oldest active, cancel its tween
                  convert world pos to screen pos ONCE via WorldToScreenPoint()
                  tween upward, fade, return to available on complete

Stagger:          spawn each number 30ms apart via task.delay
                  40 numbers × 30ms = 1.2s cascade
                  this IS the MapleStory feeling

Distance cull:    skip if enemy > 80 studs from camera
                  during full-map ult, only 15-20 enemies are relevant

During ult:       suppress other players' numbers entirely
                  ult should be the only visual event
```

---

## Part 16 — Error Philosophy, Logging, and Testing

> **Status:** PROVISIONAL. The error philosophy is settled; the testing
> strategy has never been run against real code and should be treated as a
> starting position, not a plan.

### Error Philosophy

Every service should have a consistent failure strategy. The options, from mildest
to most severe:

| Strategy | When to use it |
|---|---|
| `return false, reason` | Expected failures (inventory full, out of range) |
| `warn()` with Event ID | Unexpected but non-critical (invalid source, rejected Request) |
| `error()` | Programmer errors that should never reach production (nil entity passed to StatService) |
| Retry | DataStore failures — always retry with backoff before giving up |
| Kick player | Repeated suspicious behavior from same client after warnings |
| Rollback | Not currently needed at this scale — log and move on |

The rule: **fail loudly in development, fail gracefully in production.**
During development, use `error()` aggressively so bugs surface immediately.
Before shipping, audit errors and decide which should become `warn()` + graceful return.

Services should never silently swallow failures. Every rejection should produce
at minimum a `warn()` with the originating Event's id so the failure is traceable.

**Boot-time validation is the same philosophy, applied once, at startup,
instead of per-call.** Part 13's two-way place-manifest check, Part 10's
declared-Service-registry check, and Part 11's Signal-wiring check are all
instances of this same rule: aggregate every failure and fail loudly, all at
once, rather than letting individual `warn()` calls scatter through engine
output where they're easy to miss.

### Logging

Every significant service action should produce a structured log line:

```lua
-- Structured log format
Logger.log({
    service   = "ResourceService",
    action    = "grant",
    eventId   = event.id,   -- always traceable back to the originating Event
    entityId  = entity.identity:getId(),
    resource  = resourceId,
    amount    = amount,
    source    = source,
    result    = "success" | "rejected",
    reason    = reason or nil,
})
```

Minimum logging requirements per service:

- **ResourceService**: every grant, drain, rejection, and onFloor/onCeiling trigger
- **CombatService**: every hit, miss, kill, and parry
- **StateService**: every flag set/cleared, and which Service requested it
- **DataService**: every save attempt, success, and failure
- **SessionService**: every join, leave, and teleport
- **DungeonService**: every instance spawn, boss spawn, and cleanup
- **LevelService**: every level-up

When something goes wrong at 2am, logs with Event IDs are the difference between
a 10-minute fix and a 3-hour debugging session.

### Testing

Because every `Event` is a plain typed object with a UUID, built and validated
entirely before it ever reaches a Service, Services can be tested without a
live Roblox game.

**Unit tests** — test one service in isolation:
```lua
-- Test that ResourceService rejects negative amounts
local player = makeFakePlayerEntity()
local ok, reason = ResourceService.grant(player, "Gold", -50, "TEST")
assert(ok == false)
assert(reason == "INVALID_AMOUNT")
```

**Integration tests** — test a full flow across multiple services:
```lua
-- Test that killing an enemy grants gold and triggers achievement check
local player = makeFakePlayerEntity()
local enemy  = makeFakeEnemyEntity({ loot = { Gold = 100 } })
CombatService.processKill(player, enemy)
assert(player.resources:get("Gold") == 100)
assert(AchievementService.wasChecked("FIRST_KILL"))
```

**Deterministic combat tests** — verify damage formula consistency:
```lua
-- Same inputs should always produce same outputs
local dmg1 = CombatService.calculateDamage(attacker, defender, "NORMAL")
local dmg2 = CombatService.calculateDamage(attacker, defender, "NORMAL")
assert(dmg1 == dmg2)
```

**State-gate tests** — verify StateService flags are actually respected by
every source that's supposed to check them:
```lua
-- An invulnerable target should take zero damage regardless of source
local target = makeFakeEnemyEntity()
StateService.set(target, "INVULNERABLE", true)
local dealt = CombatService.resolveDamage(attacker, target, 100)
assert(dealt == 0)
```

**Replay tests** — record a sequence of Events, replay them through the
routing table, verify final state matches. This is the most powerful test
for combat bugs: you can reproduce a reported exploit exactly by replaying
the Event sequence.

---

## Part 17 — Data Migration and Definition Validation

> **Status:** PROVISIONAL, UNBUILT. Migration matters the moment real
> save data exists and not one minute earlier.

### Definition Validation at Startup

Every definition table should be validated before gameplay begins.
A bad definition discovered mid-game is far worse than a crash at startup.

```lua
-- server/boot/ValidateDefinitions.lua
-- Runs before any service boots. Fails fast on invalid content.

local function validateResourceDefinitions()
    for id, def in pairs(ResourceDefinitions) do
        assert(type(def.id) == "string",       id .. ": id must be string")
        assert(type(def.category) == "string", id .. ": category required")
        assert(def.floor == nil or type(def.floor) == "number",
                                               id .. ": floor must be number or nil")
        -- validate category is a known value
        assert(table.find({"VITAL","CURRENCY","PROGRESSION","TIMED","CONSUMABLE"}, def.category),
               id .. ": unknown category " .. def.category)
        -- etc.
    end
end

-- Run all validators at boot — crash loudly if anything is wrong
validateResourceDefinitions()
validateWeaponDefinitions()
validateEnemyTemplates()
validateBuffDefinitions()
validateLootTables()
validateEventRoutingRegistry()   -- every declared eventType resolves to a
                                  -- real Service method (Part 12)
validatePlaceManifest()          -- two-way check from Part 13: every
                                  -- declared Service is present, nothing
                                  -- undeclared is present
checkEffectCoverage()            -- every effect type referenced by content
                                  -- has exactly one entry in the effect
                                  -- table (Part 11.2)

print("[Boot] All definitions validated successfully.")
```

Validation failures should print the specific field that failed and what was
expected. "definition validation failed" is useless. "RaidTokens: ceiling must
be number or nil, got string" tells you exactly what to fix.

### Data Migration

Player save data will change shape as the game grows. You will add new fields,
rename existing ones, and remove deprecated ones. Without a migration system,
returning players load corrupted or incomplete save states.

The pattern: every save includes a schema version number. On load, if the saved
version is older than the current version, run migration functions in sequence.

```lua
-- DataService handles migration transparently on load
local CURRENT_SCHEMA_VERSION = 3

local migrations = {
    -- v1 → v2: added petRoster field
    [1] = function(data)
        data.petRoster = data.petRoster or { equipped = {}, afkAssignments = {} }
        return data
    end,
    -- v2 → v3: renamed "money" to "Gold" in resources
    [2] = function(data)
        if data.resources and data.resources.money then
            data.resources.Gold = data.resources.money
            data.resources.money = nil
        end
        return data
    end,
}

function DataService.load(player)
    local raw = DataStore:GetAsync(player.UserId)
    if not raw then return DataService.defaultData() end

    local version = raw.schemaVersion or 1
    while version < CURRENT_SCHEMA_VERSION do
        raw = migrations[version](raw)
        version += 1
    end
    raw.schemaVersion = CURRENT_SCHEMA_VERSION
    return raw
end
```

Rules for migrations:
- Never delete a migration function once it's been deployed — players on old
  versions need to run it
- Each migration is numbered sequentially and runs in order
- Migrations should be simple and defensive — handle nil fields gracefully
- Test migrations against real save data samples before deploying
- Remember HP is never part of saved data at all (Part 8) — no migration
  ever needs to touch it.

---

## Part 18 — Build Order

> **Status:** PROVISIONAL. A plan, not a decision. Reorder freely as
> reality intervenes — the phases exist to prevent building Phase 4 systems
> during Phase 1, not to be honored literally.

The architecture is complete enough to extend in any direction.
Do not build what you don't need yet. The extension points are there.

The only thing that kills solo game projects is running out of energy before
the game is fun. Phase 1 answers one question: does hitting an enemy feel good?
If yes, everything else is worth building. If no, no amount of architecture helps.

### Phase 1 — The Feel
**Goal: hitting an enemy feels exceptional.**
- Fix the known Signal and BaseManager bugs first (Part 19) — nothing above
  this phase works correctly until Signal genuinely broadcasts to all listeners
- Implement the centralized EventTape pipeline and EventRoutingRegistry as
  actually decided in Part 12 (the code currently still reflects an earlier,
  rejected per-eventType-RemoteEvent model — this needs to change as part of
  Phase 1, not be inherited as-is)
- Damage number pool: 80-cap, 30ms stagger, distance cull, tick sounds
- Single-target combat with server-side hit validation and latency tolerance
- One skill activation = one Event, one calculation, one aggregate Signal
  fire (Part 8, Part 11) — do not build per-hit computation
- Client-side optimistic animation with the eventId pending-actions
  correlation and explicit reject message (Part 15)
- Layer separation: server Entity + client display + HUD as listener

### Phase 2 — The Loop
**Goal: log out, return, feel like something happened.**
- ResourceService + ResourceDefinitions (Gold, EXP)
- AFKService: server-side elapsed time × farmStat, 8hr cap — Farm Zone only
  (Part 13)
- PetEntity with FarmStats, equipping, basic passive effects
- Inventory, basic gear, farm zone teleport
- DataService with save-before-teleport, migration support from day one
- Login summary screen

### Phase 3 — The Dungeon
**Goal: a complete run with real tension.**
- Instanced dungeon rooms with mob waves
- Power-up drops per wave clear with escalating pressure mechanic
- Boss FSM (`AIState`, Part 7) with parry, stagger — this is content-level
  design, not foundational architecture, and can be built out at whatever
  pace makes sense
- `StateService` and `StateFlags` (Part 9) — needed starting here, since
  FROZEN first becomes real in Phase 4's domain ultimate, but the mechanism
  itself is cheap to stand up alongside the FSM
- Attack-based shield on select bosses, with the real declared hit-count
  mechanism from Part 8 — not a per-hit-damage mechanic

### Phase 4 — The Spectacle
**Goal: the game becomes what the GDD describes.**
- Weapon system with unique attack patterns and weapon ultimates
- Pet ultimates with domain camera system and opt-in/opt-out flow —
  FROZEN/INVULNERABLE/IMMOBILIZED via StateService, server-clock-anchored
  synchronized playback (Part 12, Part 15)
- Multiplayer combo system — same synchronized-playback pattern
- Boss strength test with asymmetric weapon inputs
- Mythic weapon skill trees
- Weapon finisher system with per-weapon death cinematics — DYING via
  StateService, same synchronized-playback pattern, no opt-out per the
  design (Section 12 of the GDD)

### Phase 5 — Polish
**Goal: everything feels intentional.**
- Animations (bring in or reignite an animator — by now the game is real and
  playable, they have something to animate for)
- Sound design pass — especially finisher audio stings per weapon type
- Visual effects pass on skills, boss attacks, and finisher residue details
- Mythic pet drop announcement system
- Mythic finisher visual upgrades over base tier versions
- Post-run finisher kill feed

---

## Part 19 — Known Implementation Gaps

> **Status:** current as of this revision. This Part exists to keep the
> document honest about the gap between the architecture above and the code
> that actually exists. It goes stale faster than anything else here — when
> it disagrees with the repository, the repository is right.

### Closed Since The Previous Revision

Everything this Part previously listed as open is now done. Kept as one
compressed list for a single revision, so a stale copy of this document
doesn't send someone to "fix" something that no longer exists — then delete
it outright.

**The Signal layer now matches Part 11.** `SignalService` has
`declare`/`on`/`validate`; `Signal:Connect` returns a connection with
`:Disconnect()`; `Signal:Fire` snapshots its listener list and `pcall`s each
listener. `SignalHelper`, `GlobalRegistry`, and `SignalEnum` are **deleted**,
not repaired — the registry became a vocabulary of legal fact names and fire
capability became `declare()`'s return value, which left the auto-wiring and
the derived name list with nothing to own.

**The EventTape layer now matches Part 12.** `EventTapeController`,
`EventTapeManager`, and `EventTapeSystem` are deleted, replaced by one
`EventRouter` plus a declarative `EventRoutingRegistry`. There is one
centralized `RemoteEvent`, `eventType` rides as a data field, and the
buffer is processed in insertion order with no sort. Each event class owns
its own subTypes and its own schema.

**`BaseManager` and `ComponentLoader` are deleted**, along with the
per-property Manager/Controller/System trio and the duplicated `hub/` tree —
per the client document's Part 10.2 and its rejected-designs table.

**The untrusted boundary is now actually bounded.** `EventTape` had careful
per-field validation and no throughput limit at all — a per-tape cap bounds one
burst, but a tape is one frame's batch, so it permitted thousands of events per
second. There is now a per-player token bucket (50/sec sustained, 100 burst),
`OVERSIZED` and `RATE_LIMITED` are both sent rather than declared-and-unused,
and tape-level refusals answer once per tape rather than once per event so a
refusal cannot be turned into amplification.

**The inbound path has been driven end to end in Studio**, including a
fabricated payload sent straight to `FireServer` past the builder — it died at
the registry lookup before any Service saw it. `EventTape.md` §7 records what
was observed.

### Still Open

- **The client rewrite is not started.** `ClientManager`, `UIManager`,
  `UIRootGUI`, `CameraSystem`, and `InputSystem` are still the legacy tree,
  left running so the existing HUD renders. None of the client document's
  Part 5 (Widget / Binding / Renderer), Part 6 (Router / Presenter), Part 7
  (IntentMap / context stack), or Part 8 (Prediction) exists. `Main.client
  .luau` says so at the call site.
- **Only one place exists.** `dungeon.project.json` is the sole build;
  `hub.project.json` and a Farm Zone build do not exist. Part 13's two-way
  place-manifest check therefore has nothing to check against yet, and the
  absence guarantee is currently a property of there being one place rather
  than of anything verifying it.
- **Every Service is a stub.** The registry tree under
  `services/authority`, `domain`, `infra` and `drivers` exists and loads, but
  no Service validates or mutates anything. `CombatService:OnAttack` is a
  `print` that proves the inbound path end to end.
- **Nothing calls the outbound *confirmation* path.** `EventRouter:confirm`
  and `:push` exist and are unused, so `RejectReason.ILLEGAL` is never sent —
  and, more sharply, **a successful action never resolves on the client.** Its
  pending entry sits until the 10-second `TIMEOUT` sweep, which makes success
  currently indistinguishable from a lost packet. Rejection is the only
  outcome that resolves promptly, and it has been observed working end to end.
  See `EventTape.md` §8 for the full gap list, maintained there rather than here.

### What Is Explicitly Not A Bug

- **`EventDeserializer` doing nothing but resolve a class and call
  `Event.build`.** That is the whole job, and the thinness is the point: the
  authoring path and the wire path deliberately end at the same constructor,
  so a rule cannot apply to hand-built events and be skipped for anything
  arriving from a client. It does not need a parallel "routing" concept
  bolted on — routing lives in `EventRoutingRegistry`, server-side.
- **`EventFactory.create` being a one-line forward.** It is a named entry
  point, not a decision-maker; the caller passes the concrete class, which is
  the only question a factory could have asked. Keeping it generic over the
  class is what preserves autocomplete on the `:withX()` chain — a
  string-keyed registry lookup would read as more factory-like and destroy
  the property the fluent API exists for.
- **Signal having exactly one kind of registrant.** There is no split between
  "the handler" and "the observers," and no `SetHandler` to reintroduce. See
  Part 11's rejected-designs table before assuming otherwise.
- **`src/gameModes/dungeon/` still being a place-shaped root.** Inside it the
  server tree is already role-based (`services/authority`, `domain`, `infra`,
  `drivers`) per Part 13. Flattening the outer `gameModes/` wrapper is worth
  doing when a second place actually exists, not before.

---

## Part 20 — Quick Reference

> **Status:** derived. Every row here restates a decision made somewhere
> above. If a row disagrees with its own Part, the Part wins and this table
> is stale — fix it here rather than reasoning from it.

### "Where does this code belong?"

| This thing | Layer |
|---|---|
| RemoteEvent handler body | Remote/EventTape |
| Event construction and payload validation | `EventFactory.create(XEvent):withX():build()` — one schema per type, validated identically on the wire (Part 12) |
| "Which top-level domain does this Event go to?" | `EventRoutingRegistry` (server-only flat table, Part 12) |
| "Which sub-service within a domain handles this subType?" | That domain's own internal business, not EventTape's — Part 12 |
| "Is skill unlocked?" check | Service (CombatService / SkillService) |
| "Is amount > 0?" check | Service (ResourceService) |
| "Is this entity invulnerable / dying / frozen right now?" | `StateService` (Part 9), checked by every source before mutating |
| Damage calculation | The `DamageResolution` pipeline inside CombatService — one calculation per activation, not per cosmetic hit (Part 8, Part 11) |
| A new damage modifier (crit, armor, lifesteal, a shield) | A step in the relevant pipeline phase — never a new Service, never a new `if` inside CombatService (Part 11.1) |
| "Is this attack legal at all?" | VALIDATE, in the Service, **before** the pipeline runs. A pipeline step may never reject (Part 11.1) |
| A consequence a definitions file declared (`{type="DEBUFF"}`) | The effect table, dispatched after COMMIT (Part 11.2) |
| Telling the client what a hit actually did | A diff assembled from what the COMMIT calls **returned**, pushed once (Part 11.1) |
| `entity.vitals.hp = n` | Entity (called by Service only) |
| Inventory capacity check | Component invariant (Inventory:add) |
| `DataStore:SetAsync` | Data (DataService only) |
| Gold counter display | Client (reads replicated Attribute) |
| Damage number cascade | Client (fabricated from one aggregate outbound message, Part 15) |
| Buff expiry timer | Scheduler → BuffService:tick() |
| Final attack value | `StatService.compute(entity, "attack")` |
| Enemy definition (HP, stats) | Content (EnemyTemplates) |
| Boss telegraph before an attack | BossAIService mutates AIState directly → pushes the outbound EventTape confirmation itself (clients seeing the telegraph is inherent, not optional — Part 5's latency compensation depends on it) |
| "Tell the client what just happened" | The originating Service pushes outbound EventTape / sets a replicated Attribute directly, as its own inherent step — never via Signal, which never reaches the client (Part 12) |
| "Announce that X just happened, for anyone optionally interested" | `Signal:Fire()` — called by the Service, after mutation and after the client has already been told, once per activation, never load-bearing (Part 11) |
| Optimistic client animation cancel/confirm | Client pending-actions map, keyed by Event UUID (Part 15) |

### "Which service owns this?"

| Action | Service |
|---|---|
| Grant gold | `ResourceService.grant(player, "Gold", n, source)` |
| Drain HP | `ResourceService.drain(entity, "HP", n, source)` — n is always the final, fully-resolved amount |
| Set/check a status flag | `StateService.set(entity, "INVULNERABLE", true)` / `StateService.has(entity, "DYING")` |
| Apply buff | `BuffService.apply(entity, buff)` |
| Final attack stat | `StatService.compute(entity, "attack")` |
| Equip weapon | `EquipmentService.attach(player, "weapon", item)` |
| Add to bag | `InventoryService.add(player, item)` |
| Level up | `LevelService.onLevelUp(player)` |
| Save data | `DataService.save(player)` |
| Spawn boss | `DungeonService.spawnBoss(instanceId, bossType)` |
| Finisher camera | `CinematicService.triggerFinisher(caster, boss, weaponType)` |
| Buy shop item | `ShopService.purchase(player, itemId)` |
| Check current zone | `ZoneService.canPickupHere(player)` |
| Decrement Attack-Based Shield | `CombatService` decides when; `ResourceService.drain(boss, "ShieldHits", n, source)` does the bookkeeping (Part 8) — not StateService, not a separate component |

### "Request, Intention, or Fact?"

| Request | Intention | Fact |
|---|---|---|
| Client-originated | Server-AI-originated | Resolved outcome |
| Legality check, inside the Service | Sanity check, inside the Service | No check — already happened |
| e.g. player attacks | e.g. boss decides to attack | e.g. 200 damage dealt, entity mutated |
| Routed via `EventRoutingRegistry` to a direct Service call | Direct Service call, no EventTape involved | `Signal:Fire(result)`, once per activation |
| Event object carries a UUID, also used for client-side optimistic correlation (Part 15) | Event object carries a UUID (or is generated server-side) | No new object — the Signal call references the same mutation |
| Rejection: explicit reject message if client has pending optimistic state (Part 15), otherwise silent per Part 5 | Rejection: silent, warn + log only | N/A |

### "Generic Engine or explicit code?"

Count the instances. If two or three things are wildly different: write them explicitly.
If ten or more things share a clear structure: build the engine.
Examine whether the engine reduces complexity overall — not whether you *could* build one.
If a "layer" would only ever receive something and immediately hand it forward
unchanged, it isn't a layer — see the Command Layer story in Part 5. If a data
object would need to reach upward to call the thing that reacts to it, that's
routing logic wearing a data object's clothes — see the self-dispatching Event
story in Part 12. If two systems resolve modules by name but do genuinely
different things with what they find (connect vs. call-with-return vs.
instantiate), that's the "write them explicitly" bucket even if the lookup
step looks similar — see the rejected unified `ModuleResolver` in Part 12.

### "Direct Call, Table, or Signal?"

Ask: would this action still mean what it claims to mean if the other
domain's involvement didn't happen? See Part 11 for the full reasoning.

| Relationship | Target known statically? | Tool |
|---|---|---|
| Inherent (the action *is* this) | Yes | Direct call — `require` and call the validated public method |
| Inherent (the action *is* this) | No, varies by content | The effect table (Part 11.2) — flat static map of label → one handler, `(target, effect, source) -> ()`, synchronous, can return a result |
| Optional (may react, doesn't have to) | N/A | Signal — Fact, fired last, zero-to-many listeners, no return value |

Note the second row is *forced*, not preferred: you cannot hardcode a call
for a consequence that arrived as data from a definitions file. If the target
does not genuinely vary by content, use the first row.

### "Is this a naming smell?"

| Name | Problem | Fix |
|---|---|---|
| `EconomyService` | Named after data | `ResourceService` |
| `GoldService` / `RaidTicketService` / `EventCurrencyService` | Named after one currency instance — this actually slipped into this document's own worked examples mid-conversation before being caught | Subsumed by `ResourceService` — every currency is a `ResourceDefinitions` entry, see Part 8 |
| `HPService` | Named after one resource instance, and the reason it seemed necessary (client notification) is already solved generically by outbound EventTape (Part 12) | Subsumed by `ResourceService`; the notification need is EventTape's job, not a bespoke service's |
| `ShieldState` (as a component) | Named after one Combat mechanic's bookkeeping, when the bookkeeping itself (floor, ceiling, break-at-zero) is identical in shape to every other resource | Subsumed by `ResourceService` as a `ShieldHits` entry — see Part 8's revision |
| `CurrencyService` / `ProgressionService` | Named after `category`, not behavior — looks like progress over per-currency services, but forks the engine by a different, equally arbitrary line | `category` stays a field inside one `ResourceDefinitions` entry — see Part 8 |
| `GoldManager` / `ResourceManager` (as a client-notification relay) | A Manager invented to listen for a Fact and forward it — using Signal to simulate a guaranteed completion that a direct return already provides | Subsumed into `ResourceService.grant`/`.drain`/`.set`'s own last steps — see Part 8's "What Client Notification Is Not" |
| `PlayerService` | Not a behavioral domain | Split into SessionService, StatService, etc. |
| `PetService` | An entity-type service — named after a noun that is neither a behavior nor a component. Its four responsibilities each belonged elsewhere | Dissolved: equip/unequip → `Equipment` + spawn rule; ultimate routing → `CombatService`; AFK assignment → `AFKService`; cooldowns → `SkillService`. See Part 10 |
| `PetRoster` (as a component) | Named after one entity type's version of bookkeeping that is identical to `Equipment` — bounded slots, one occupant each, a capacity ceiling | `Equipment.new({ "pet1", ... })`. The real difference is the spawn side effect, which is a game rule and belongs to a Service — see Part 7 |
| `BossAIService` + `PetAIService` | Two services for one behavior — tick, read `aiState`, gate on StateService, emit an Intention. Only the decision function differs, and that is content | One `AIService` with per-profile decision modules; pacing is a profile field. See Part 10 and Part 14 |
| `DamagePipelineService` / `ParryService` / `ShieldService` | A Service per mechanic. Pipeline is a *role*, not a Service (Part 3), and a mechanic is a step or an effect | A pipeline step in `DamageResolution`, or an entry in the effect table. See Part 11 |
| `GameManager` | Placeholder, not a domain | Find the behavior and name that |
| `Utils` | Graveyard | Move each piece to the service that owns it |
| `CommandFactory` / `CommandService` | A layer invented to hold a concept, nothing actually happens inside it | Fold into the routing step in Part 12 |
| `Signal:SetHandler` / `Signal:NotifyListeners` | Reached for the effect table's guarantee using Signal's mechanism. The validated-mutation property it chased comes free from an ordinary Service method that is the only door into its own state | `Signal:Connect` / `Signal:Fire` — pure Fact broadcast; validated mutation lives in the firing Service method, not on Signal. See Part 11's rejected-designs table |
| `EffectResolver.register(type, fn)` | Registration scatters the effect vocabulary across N files and adds boot-order questions, for a closed set of maybe eight entries | A flat static `EffectHandlers` table, readable in one screen — the same shape already settled for `EventRoutingRegistry`. See Part 11.2 |
| `StateService` vs `StatService` | Not wrong, but one letter apart with unrelated jobs — see Part 4 | Always use the full word, never abbreviate either in comments or conversation |
