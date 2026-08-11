# Gameplay Design Document — Work In Progress

> Companion to `Architecture-Reference.md` and `Client-Architecture.md`, but
> deliberately separate. This document is about **what the game is and why
> it's fun** — not how it's built. Status tags per section reflect confidence
> level, not build order.

---

## Core Pillars

The game combines:
- **MapleStory** — moment-to-moment combat feel, progression satisfaction,
  the "hitting things and getting stronger" loop.
- **Monster Hunter** — the boss *is* the content. Telegraphs, phases, weak
  points. Fights feel like events, not damage checks.
- **Dungeon crawler + procedural generation** — the structure that paces
  players between boss-events, not the point of the game itself.

**Design principle established early and referenced throughout:** the
dungeon layer can afford to be relatively simple *because* the boss layer is
doing the heavy lifting on "why does this feel good." Don't over-invest in
dungeon depth at the expense of boss quality.

**Party structure (clarified this session):** dungeons support up to a
**4-player party**, but the game is explicitly tuned so a **solo player is
never dependent on a working group** — no mandatory healer role, no "shit,
I need a support" blocker, no getting stuck waiting in the hub. "Solo-
friendly" means *no forced dependency*, not *no multiplayer*. See Section 13
for how difficulty scales with party size.

**Monetization stance (stated, not yet designed in detail):** free to play,
everything eventually earnable for free. Paying buys *speed*, not access.
Gacha/gambling mechanics are wanted (Honkai Star Rail as reference point) —
see Section 11 for the real constraints on this. This promise explicitly
extends to top-rarity relics (Section 6) and boss summons (Section 9) — the
best combat kits and companions stay pity-reachable, never pay-only.

---

## 1. Dungeon Structure

**Status: Early, mostly conceptual.**

- Procedurally generated rooms, organized by **theme**.
- Each theme has its own monster pool.
- Higher player level unlocks stronger room variants within the same theme
  (different rooms can appear, not just stat-scaled versions of the same
  ones).
- Dungeon ends in a boss fight.
- **Architecture note:** `DungeonTheme` should be a declarative config table
  (monster pool, room variants, level thresholds) — the *generation engine*
  that walks a theme is the one thing written once. New themes should be
  "write a table," not "write a system."
- **Healing:** players heal to full after clearing a room. **No healing
  mid-combat**, from any source. This is a deliberate constraint, not a gap
  — see Section 5 for why classes don't run on mana/stamina either.

---

## 2. Boss Design — Core Loop

**Status: Directionally solid.**

Standard bosses use full Monster Hunter-style combat: telegraphs, phases,
weak points, no interactive cutscene layer. This is the baseline every boss
gets, and it doesn't require any of the systems below to be fun on its own.

**"Special" bosses** — a *small, deliberately rare* subset — get the full
treatment described in sections 3–4. Not every boss. Roughly 3-4 total was
floated as a sane scope, not 15-20.

**Sequencing principle agreed on:** build every boss as a normal fight
first. Prototype the cutscene-sequence engine on one favorite boss only.
Validate it's fun and the system generalizes before investing further —
don't front-load the expensive tech before knowing the base fight is good.

---

## 3. Interactive Cutscene Sequences (Special Bosses Only)

**Status: Directionally solid, scope-checked.**

God of War-style interactive combo sequences, reusable across every special
boss via a generic **landmark** system.

- Room has designated **landmark points**, positioned based on boss
  archetype (ground-melee, ground-giant, flyer, swarm — not just a binary
  flyer/non-flyer split).
- During the sequence: hit landmarks, trigger combo continuations, chain
  through the room (drag boss around, parry chains, hit vulnerable spots).
- **Length target: 5-10 seconds max.** Long enough to feel earned, short
  enough to stay a highlight rather than becoming the whole fight.
  Frequency matters more than length — this should be a punctuation mark
  (finisher / phase transition trigger), not the entire encounter.
- **Reusability is the point:** one interaction *engine* (hit points, camera
  behavior, combo escalation, prompt timing), with per-boss config being
  landmark positions + animation clips + a few boss-specific beats. New
  boss = author landmarks + pick clips, not build a new system.
- **Also drives the Archer's dodge-burst payoff (Section 5)** — same
  engine, triggered by a perfect-dodge condition instead of a landmark
  hit-count, auto-playing rather than requiring in-cutscene input. One more
  config, not a new system.

### Summon Assist
- Your collected boss summon (see Soul Fragments, Section 9) can
  participate in / autoplay these sequences.
- Autoplay has a **chance to fail**. On fail, a short intervene-window opens.
- Miss the window → sequence ends. Ending currently modeled as a **generic
  fail animation**: boss grabs player, rushes them to center of room, plays
  a swappable theme-specific finisher (flyer slams, beast-type pins, caster
  detonates at range, etc.). One shared skeleton, swappable last beat —
  keeps per-boss fail-state authoring cheap.
- **Open question, not yet decided:** binary fail (one miss ends the
  sequence) vs. degrading fail (miss weakens the sequence, repeated misses
  end it). Binary is simpler; degrading is more forgiving for a system meant
  to feel like a comfortable assist most of the time.

### Ending Beat
- Originally conceived as a keyboard-mash contest (God of War style).
- **Flagged as worth reconsidering:** mash contests reward reflexes/hardware
  over skill reads, and are an accessibility concern (RSI, motor
  impairments). A timing/parry-window contest (react on the beat) was
  suggested as a same-slot replacement that reads as more skillful. **Not
  decided — worth revisiting.**

---

## 4. Phase Transitions (Distinct From Interactive Sequences)

**Status: Newly clarified this session — important distinction.**

Two categories of "interactive moment," not one:

| | Combo Sequences (Section 3) | Phase Transitions |
|---|---|---|
| Trigger | Player performs the interaction | A state condition is met (e.g. wing HP hits 0, **or stagger meter fills — see Section 5**) |
| Can fail? | **Yes** — that's the point, tension | **No** — already resolved by the time it plays |
| Player input during? | Yes, actively performing | None required |
| Purpose | Test | Reward / consequence beat |

**Example given:** an angel boss — destroy its wings (a landmark, hit-count
gated) → guaranteed, non-failable transformation cinematic → boss becomes
demonic, gets a new theme/moveset.

- Mechanically the **same landmark/cutscene engine** as Section 3, just fed
  by a different trigger type: a `failable = true/false` flag on the
  sequence definition, not a separate system.
- **The stagger meter (Section 5) is a second natural trigger source** for
  this system, alongside HP-thresholds and part-breaks — "stagger meter
  filled via parry/redirect/dodge-burst" feeds the exact same
  non-failable-cinematic path, no new architecture required.
- Precedent: this is closer to Monster Hunter's part-breaking (sever a wing,
  boss loses flight permanently) or Shadow of the Colossus (find weak point,
  strike it, boss reacts, fight advances) than to Elden Ring's HP-threshold
  phase 2s. Genuinely rarer in games than plain phase transitions *because*
  it's more expensive — unique hitbox per part, unique destroy + transform
  animations, often a new moveset. This is real, irreducible content cost;
  the landmark system just prevents it from also being new *engineering*
  cost per boss.
- **Open question:** does hitting the trigger interrupt whatever's currently
  happening immediately, or queue until the current beat resolves?
  Immediate feels more causal/reactive; queued is safer pacing but muddies
  the "I caused this, right now" feeling. **This same open question now
  also applies to the Archer's dodge-burst cinematic (Section 5) — one
  engine-level decision, not two.**

### Armor Shedding vs. Part Breaking — Two Systems, Not One

**Status: New — distinction drawn deliberately. Both are wanted.**

Both read to a player as "pieces are coming off the boss," and they are
different systems with different costs. The tell is **agency**:

| | Armor shedding | Part breaking |
|---|---|---|
| Trigger | boss HP crosses a threshold | *that specific part* absorbed enough damage |
| Player agency | none — it arrives on schedule | total — you chose to focus the tail |
| Needs per-part hit detection | no | yes |
| Cost | near zero — a phase transition wearing a costume, and `Phases` already holds HP thresholds | real, but see `HitDetection.md` — smaller than it looks |

**Keep both, and give them different jobs so they don't land as the same
beat twice.** Part breaking is what the player *earns*; armor shedding is
what the fight *gives* on schedule. A boss can run both.

**Broken armor should change how that part takes damage**, not only how it
looks — break the carapace and later hits there hurt more. That is what makes
focusing a part a real decision rather than a cosmetic one, and it is the
loop Monster Hunter is actually built on.

**First boss concept supports both directly:** the seraph's armor is drawn
already fracturing, with light running through the cracks — shedding is a
matter of widening what is already there. Its six wings are the natural
break targets, and wing destruction is already this section's worked
example for a non-failable transformation.

---

## 5. Combat Mitigation System — Dodge, Parry, Redirect, Block

**Status: New this session — core combat identity, direction set.**

Every boss attack falls into a category, and mitigation options are gated
by category. This is the primary lever that makes **class choice matter
per-fight**, not just a stat difference — a fight leaning heavily magical
genuinely asks for a different roster pick than one leaning heavy-physical.

### Universal Layer
- **Every class has basic dodge.** Negates damage, no other effect, no
  resource cost. This is the floor — always viable, never flashy, keeps
  every class playable in every matchup even without their bespoke kit.
- **No mana or stamina system.** Class kits run entirely on **cooldowns**.
  Deliberate choice to keep the fighting chaotic and resource-pool-free;
  pacing is controlled by cooldown timers, not a meter to manage.
- **Stagger:** all damage, from any class, contributes to the boss's
  stagger meter. **Parry-capable classes get a higher stagger multiplier**
  on a successful parry/redirect/block than on a normal hit — mitigation
  skill compounds into offense, not just safety.

### What Successful Mitigation Feels Like

**Status: New — the moment-to-moment loop, decided.**

Mitigation that works should read as *nothing happened to you*, not as a
special event of its own:

- **Damage is negated, not reduced.** A successful parry, redirect or block
  takes the hit to zero.
- **No reaction animation on the player.** No stagger, no knockback, no
  interrupt — the attack passes through and you keep doing what you were
  doing. The tell that it worked is the *boss's* reaction, not yours.
- **A short invulnerability window follows** any mitigation that actually
  blocked damage. This is what makes a correct read feel rewarded, and it
  covers the recovery frames of the animation you just committed to.

**Flagged — needs a number, not a redesign:** invulnerability on a successful
parry means chained parries grant *continuous* invulnerability. Every game
with this loop caps it somehow — i-frames shorter than the parry cooldown, or
a window that refuses to refresh on a second parry inside it. Decide which
when the numbers get tuned.

**The differentiated reaction lives on the boss, and only on stagger.** A
parry that merely negates gets the generic "your attack was turned aside"
beat. A parry that *staggers* gets a bespoke reaction, chosen from two values:

| Value | Where it comes from |
|---|---|
| Which limb or weapon the boss swung with | declared on the attack itself |
| Which sector the parrier stood in | the angle between the boss's facing and the player, quantised to 4–8 sectors |

Parry the tail sweep and the tail recoils; parry the same claw from its
outside and it gets spun rather than rocked. Because this is stagger-only,
the authoring cost is roughly six to ten animations rather than a full
limb × angle matrix — and any combination without a bespoke clip falls back
to the generic stagger, which is the wanted behaviour anyway.

**This deliberately does not use per-limb hitboxes.** A parry intercepts the
boss's *attack*, not its body, so anatomy is the wrong question: standing
near a leg while parrying an overhead claw should recoil the claw. Reasoning
in full in `HitDetection.md`.

### Boss-Side Mitigation

**Status: Direction set; one piece deliberately rejected.**

- **Bosses can redirect magic.** The Mage's redirect verb pointed the other
  way — the boss absorbs an incoming magical attack and returns it as its own
  element. Identical machinery; mitigation was never a player-only concept.
- **Bosses get a generic parry**, used occasionally, resolving into a
  one-sided punish: grabbing the player's weapon and throwing them. A tempo
  and positioning punish rather than a damage check.
- **No clash sequences on parry — rejected on direction, not cost.** A parry
  clash is a duel beat, and this game is about fighting monsters, not people.
  For Honor is explicitly not the target. It happens to also be the expensive
  option: a clash is a live two-sided negotiation with synchronised animation
  state on both parties under latency, whereas a throw is a one-sided effect.

**Animation clashing is reserved for phase changes and interaction sequences
(Sections 3–4).** Those are scripted — the outcome is settled before the
animation plays, both parties are locked, and nothing is negotiated live.
That is exactly what makes them affordable where a parry clash is not.

### Attack Categories
- **Physical (basic/light):** parryable by heavy-weapon class only.
- **Physical (heavy/momentum):** parryable **only** by a heavy weapon with
  a parry ability. Slow, high-risk timing window. A **light/fencer-type
  weapon cannot parry a heavy-momentum attack** — must dodge instead. This
  gives attack *weight*, not just type, a second axis players read off
  telegraphs.
- **Magical:** cannot be parried by anyone. **Only the Mage's redirect can
  interact with it** (see below); everyone else dodges.
- **Void (rare, top-tier only):** cannot be parried, redirected, *or*
  blocked — the one attack category Shield cannot answer either. Meant to
  stay rare and heavily telegraphed, since the fairness has to live
  entirely in the tell — there's no mitigation to fall back on. This is a
  spectacle beat, not a routine check.

### Class Mastery Verbs
Each class gets basic dodge, plus one bespoke verb — the roster's "mastery
high" is spread across genuinely different skills, not five reskins of the
same timing check:

- **Heavy weapon (parry):** dedicated parry ability, slow/high-risk timing.
  Parrying a heavy-momentum attack causes **instant stagger**. Highest
  stagger multiplier in the roster; the reward for the riskiest read.
- **Mage (redirect):** absorb a magical attack, blast it back as an
  elemental attack of the mage's own type. **The absorbed attack is fully
  consumed** — not just negated, deleted from the fight, so it can't hit
  anyone else in the party either. Contributes to stagger. **Open
  question:** does redirect require matching the boss's element to the
  mage's own type (a read-and-match puzzle) or does any element redirect as
  the mage's type (pure timing check)? Not yet decided.
- **Archer (dodge-burst):** a **perfect-timed** dodge (tight window, not
  any successful dodge) triggers a short (~2s) solo cutscene — a big burst
  of energy, cooldown-gated so it stays a reward rather than a spam proc.
  Reuses the Section 3 cutscene engine. Contributes to stagger. Archer can
  dodge both physical and magical attacks (broadest applicability, no
  bespoke mitigation beyond timing).
- **Shield (charge-block):** can block *everything* — including the top
  physical-momentum and magical attacks nobody else can touch — using a
  **charge meter** (battery, slow passive regen). **Cost is tiered by
  attack severity, not flat:** cheap charge cost for routine attacks (shield
  can eat these all day), expensive cost for the top-tier "unblockable by
  others" attacks (only a couple before running dry). Continuous/beam
  attacks **drain charge per-tick** rather than a flat cost, giving those
  attacks a mechanically distinct feel. Tiering is deliberate — a flat cost
  would make Shield the objectively safest pick for every fight and
  undercut the whole point of attack-category gating. Cannot block **Void**
  attacks. Lowest stagger multiplier of the parry-capable classes — its
  value is survival, not offense. Protects self only (not party members) —
  consistent with the no-mandatory-role party design (Section 13).
- **Dagger (combo/DOT):** no parry, redirect, or block access — pure agile
  melee, combos into bleed/DOT stacks and debuffs. **Mastery verb not yet
  finalized** — leading candidate is a stacking combo/bleed-uptime
  escalation meter (payoff similar in spirit to Archer's dodge-burst, but
  built from sustained combo pressure rather than a single timed input).
  Dagger's real risk is spatial, not a reaction check: it has to stay in
  melee range, including against attacks it has no way to mitigate, so its
  pressure is proximity-based rather than timing-based. **Not yet decided.**

---

## 6. Relics & Playable Characters

**Status: New this session — direction set, numbers not designed.**

- Playable characters are obtained as **relics** through the gacha system
  (Section 11) — a weapon that, when equipped, transforms the player into
  the character who wielded it. Each relic carries lore: whose weapon it
  was, who they were. In Shattered Realms specifically, equipping a relic
  causes an in-fiction transformation into that history.
- **Weapon and character are one unit, not separate systems** — deliberately
  avoids generic weapon + generic character combos in favor of every pull
  being a specific, authored kit with its own animations and identity.
- **Roster, not single-equip:** players bank multiple relics and **swap
  which one is active between fights** (not locked to whichever was pulled
  most recently). This follows directly from the attack-category gating in
  Section 5 — a fight leaning magical genuinely calls for a Mage in the
  roster, so being stuck on one relic would make bad matchups unplayable
  rather than just harder.
- **Rarity ladder ties directly to kit depth**, giving top rarity a
  *qualitative* difference in feel, not just bigger numbers:
  - **Common / Rare** — basic dodge only.
  - **Epic** — unlocks the class's bespoke mastery verb (parry / redirect /
    dodge-burst / charge-block / combo-DOT).
  - **Mythic** — unique i-frame ability on top of a fully bespoke kit,
    reserved specifically so top rarity feels different in kind, not just
    stronger. Per the monetization stance (Core Pillars), mythic relics
    stay pity-reachable — never a pay-only pool.
- **Starter character:** a strong, free starting relic is planned so new
  players have a fully-capable kit from hour one, not a placeholder.
- **Open question:** does the gacha pool include generic (non-relic)
  character pulls at all, or is every pull relic-bound? Leaning toward
  relic-only — a generic pull path was floated but felt "a little bland."
  Not fully closed off.

---

## 7. Domain Expansion / Shattered Realms (Event Boss Arenas)

**Status: Strong idea, mechanism simplified significantly this session.**

Event bosses can appear via a rare, chance-triggered replacement: reaching a
normal dungeon's boss room, by low-probability roll, replaces the room with
an event boss encounter instead. Emergent-rare (you don't know when it'll
happen) rather than scheduled-rare (calendar event) — a stronger hook.

**Evolution of the arena mechanism (kept for the reasoning, not just the
conclusion):**
1. First idea: domain fully replaces the room. Simple, but loses any
   connection to the dungeon theme it interrupted.
2. Second idea: domain *distorts/corrupts* the existing room instead of
   replacing it — stronger thematically (this specific dungeon got
   invaded), but combinatorially expensive: every boss's domain would need
   to intelligently react to N dungeon themes (N × M problem).
3. **Landed on:** the room **sinks into a black void** first (generic,
   theme-blind dissolve effect, same every time) → once empty, the **event
   dungeon's own modular geometry expands into the cleared space** → boss's
   domain overlays it. This collapses the problem to N × 1: every boss only
   ever needs to know how to occupy one known, controlled shell, not react
   to whichever of M themes it interrupted.
- The *entry into* the void can still be themed (walls cracking, floor
  tearing, reality bending in a way that matches the interrupted dungeon)
  for a themed cinematic beat, even though the fight space itself is
  generic. Best of both — contextual dread at the reveal, zero reactive
  -room engineering cost.
- **Open question, leaning toward "yes, worth it":** is the void-sink
  instant, or a drawn-out multi-second beat (walls crumbling, HUD
  suspended)? Drawn-out costs more but is likely where a large share of the
  "domain expansion" awe actually lives — and unlike per-boss room
  corruption, it's built once and reused for every event boss forever.
- **Future-proofing noted, not yet needed:** the void-shell could support a
  small handful of fixed layout variants (open arena / vertical / corridor)
  picked by boss archetype, without reopening the N×M problem, whenever
  variety becomes worth the cost.

---

## 8. Event Bosses & Farmable Afterlife

**Status: Solid, low-risk design.**

- Event bosses appear during a themed live event window (via the domain
  mechanism above), full spectacle, full cutscene sequence.
- **After the event ends, all content is kept — full sequence and all** —
  just moved into a **level-gated farmable dungeon**, with **rarity of
  drops** (not fight difficulty) being the thing that gets harder to
  farm post-event.
- Rationale: avoids the FOMO-vs-goodwill tension. Event urgency during the
  window, no permanent loss for players who miss it. Every event boss is a
  permanent addition to the game's total content, not a one-off cost.
- Fight itself stays identical forever — no maintaining two difficulty
  versions of the same encounter.

---

## 9. Soul Fragments & Boss Summons

**Status: Core progression hook, well-formed.**

- Defeating a boss has a **rare chance** to drop a **soul fragment** for
  that specific boss.
- Collecting enough fragments of a boss lets you **summon that boss to
  fight alongside you** in future encounters against other bosses —
  including, mechanically, boss-vs-boss (trivial under the architecture
  since NPC AI is just a component any entity can carry — a summoned boss
  just targets other hostiles instead of the player).
- Summon can also assist/autoplay interactive cutscene sequences (see
  Section 3).
- **Distinct from Relics (Section 6):** relics are *playable characters*
  you become; boss summons are *companions* that fight alongside whichever
  relic you're playing. Separate systems, separate gacha/drop pools.
- **Design principle, stated explicitly and worth protecting into
  monetization decisions later:** *"a summon you achieve, not buy."* Any
  future pay-to-speed-up mechanic should stay scoped to baseline
  grind/AFK progression and never touch gauntlet drop rates or fragment
  odds — the moment it does, "achieved" quietly becomes "bought, slower."

---

## 10. Boss Gauntlet Mode

**Status: Actively being designed — highest current priority alongside
loot. World boss mode explicitly shelved in favor of this (see Section 14).
Solo-only by design (see Section 13) — the momentum-stacking resource curve
below depends on a single-run tension that party healing/support would
undercut.**

**Core concept:** fight bosses back-to-back, no full reset between fights.
Occasionally paired bosses (harder tiers). Summon can assist throughout a
run. This is the primary **soul fragment farming activity** — target
farming a specific boss instead happens via the normal dungeon (see below).

**Why back-to-back is a different experience, not just "more fights":**
removing the between-fight reset turns it into a resource-management test
layered on top of mechanical skill — how deep can you go before your
resources run out — rather than repeating the same single-encounter
question. This is the actual differentiator from dungeon mode, and the
reason gauntlet doesn't need to out-reward dungeon to justify existing — it
tests something dungeon structurally can't.

**Boss selection: randomized, not player-targetable.**
- Rolls from the boss pool each run (once 10+ bosses exist).
- Includes a chance at **extremely rare bosses** that don't spawn in normal
  dungeons at all (can overlap with event bosses).
- **Pity system planned** on the rare-boss roll itself, to avoid
  unbounded bad luck gating progress — same principle as gacha pity (see
  Section 11), applied to encounter access rather than item drops.
- Rare boss is intended to be **extremely difficult** — notably stronger,
  correspondingly strong unique summon reward. This is meant to be the
  genuine top-of-game test.
- **Rare boss defeat/rematch resolved this session:** losing to the rare
  boss during a gauntlet run does **not** require re-climbing pity to try
  again. Two paths exist:
  1. **Re-enter the gauntlet** — the rare boss has a chance to appear again
     as the **final** encounter of a run (i.e. the last-slot boss roll
     specifically carries the rare-boss chance).
  2. **Rematch directly in the main lobby**, any time, no run required, to
     spend the pity token you've already earned.
  - This splits **discovery** (the gauntlet encounter — high stakes,
    momentum-fueled, the real Monster Hunter-style "rarest monster" tension)
    from **mastery** (the lobby rematch — no run cost, purely "I know this
    fight now, let me clear it"). Losing in the gauntlet is meant to sting;
    losing in the lobby costs only time.
  - **Open question:** should a gauntlet-run first win grant a better
    reward (unique title, better summon roll) than a lobby win? Without
    some asymmetry, the lobby path could become the only one anyone
    bothers with, and the climb toward it stops mattering.
  - **Open question:** does a lobby win fully reset the pity token, or does
    it take multiple clears? Leaning toward full reset on first clear, to
    keep the token meaningfully scarce.
- Target-farming a *specific known* boss stays the dungeon's job — this is
  what justifies gauntlet's full randomness rather than needing to make it
  targetable too.

**What's still missing — identified as the actual design gap this
session, not yet solved:**

Fighting good bosses repeatedly is not automatically fun without additional
structure. Five ingredients identified, checked against the current design:

1. **Escalating risk without a reset** — ✅ have this (no heal between
   fights).
2. **A meaningful in-run decision point** — ❌ **currently missing, flagged
   as the highest-leverage gap.** Right now the run is pure sequence
   (fight → fight → fight) with zero player agency beyond combat.
   **Proposed merge (this session):** don't build doors and momentum as two
   separate systems — the door choice *is* how momentum is acquired.
   Between fights, offer a choice of buffs to gamble on, and the buff pool
   *is* the momentum stack:
   - **Safe door** — small guaranteed stat bump, lower next-fight
     difficulty.
   - **Wildcard door** — bigger momentum swing (strong buff or mild curse),
     chance at bumping the rare-boss pity roll.
   - **Risky door** — big momentum stack, raises next fight's difficulty
     beyond the normal round-scaling curve.
   This also covers ingredient 4 (legible failure) close to for free — if
   momentum is visible stacked buff icons, the player can always see why
   a run is going well or badly, without separate UI work.
3. **In-run momentum/stacking mechanic** — merged into ingredient 2 above.
   **Balance idea floated:** make momentum buffs risk-bearing themselves
   (matched drawbacks — more damage/less HP, faster attacks/longer summon
   cooldown), so going deep means getting more volatile, not just stronger.
   Keeps late rounds tense without leaning entirely on a hand-tuned
   difficulty curve.
4. **Legible failure** — see ingredient 2's momentum-as-visible-stacks
   solution above.
5. **Sequence-level replayability** — ✅ effectively covered by the
   randomized boss pool already; each run is a different story even with
   the same boss roster.

**Compounding power vs. boss scaling — real balance risk flagged, not yet
resolved mathematically:**
- If per-run stat gains compound enough to make late rounds (9-10)
  trivial, the back half of the run — where the rarest bosses and best
  rewards live — stops testing anything.
- **Proposed fix, not yet tuned:** boss difficulty (HP/damage) scales by a
  curve tied to round number, applied as a config multiplier on top of the
  base boss — not a new system, just a value on the round.

**Boss mutations — scope-checked, kept intentionally narrow:**
- Random modifiers on gauntlet bosses as they appear: size, element, other
  stat/visual variation.
- **Explicitly scoped to stats + element + visual scale only.** A mutation
  that changes *moveset or behavior* (e.g. a "flying" mutation on a
  normally grounded boss) was identified as the point where this stops
  being cheap config and starts requiring bespoke per-boss engineering
  again (new attack patterns, new landmark placement). Keeping mutations
  on the stat/cosmetic side is what keeps "10 bosses × 5 mutations" a
  content multiplier instead of 50 things to actually build.

---

## 11. Loot & Gacha System

**Status: Direction set, numbers not yet designed.**

- Gacha-style pull system for **relics** (Section 6), **pets**, and
  equipment, modeled on Honkai Star Rail's structure specifically: hard
  pity (guaranteed top rarity within a fixed pull count), soft pity (odds
  climb well before hard pity), 50/50-plus-guaranteed-next on featured
  pulls, pity that persists across banner rotations.
- **Pets can carry parry-on-activation abilities** — a third mitigation
  entry point alongside the player's own class kit. **Open question:**
  should a pet's proc respect the same tight-timing skill floor as a
  player parry, or be more automatic (passive chance-to-block)? If
  automatic, it should probably negate *less* damage than a player's
  perfectly-timed input — otherwise a pet-heavy build quietly out-values
  actual parry skill.
- Explicitly **not** interested in predatory patterns: no manufactured
  near-misses, no artificial time-pressure panic-buying, no obfuscated
  currency pricing.
- **Regulatory reality, worth remembering when actually building this (not
  a reason to avoid the feature, just a compliance checklist item):**
  Roblox currently requires public odds disclosure on any paid random item
  (purchasable with Robux or Robux-derived currency), a policy driven by
  South Korean law but applied globally. Several jurisdictions (Belgium
  notably) restrict or ban paid loot boxes outright; the dividing line in
  most regulation is whether the pull currency itself can be bought with
  real-money-adjacent currency, not randomization alone. Author has
  accepted odds disclosure as a given and is not concerned about
  jurisdictions that ban the mechanic entirely.
- **Not yet decided:** one gacha currency track vs. two (free-earned ticket
  vs. premium currency); how rarity tiers map onto existing boss/fragment
  tiers (though relic rarity → kit depth is now decided, see Section 6);
  whether gacha *is* the loot system or one part of a larger one that
  also includes direct dungeon/gauntlet drops.

---

## 12. AFK Progression

**Status: Scope boundary set, solid.**

- Server-side offline/AFK progression system, explicitly designed so
  players who can't play actively aren't locked out of getting stronger.
  Noted as a genuinely popular, proven pattern in the Roblox ecosystem.
- **Hard boundary agreed on:** AFK produces baseline power — gold,
  equipment, XP, materials. **AFK never produces soul fragments or gacha
  pets/relics/weapons.** Those stay exclusive to active play
  (gauntlet/bosses). This prevents the two progression tracks from
  competing with each other — without it, the optimal strategy would trend
  toward not playing at all, undermining the boss content the game is
  actually built around.

---

## 13. Party Size & Difficulty Scaling

**Status: New this session — direction set, curve not tuned.**

- Dungeons support **up to a 4-player party**. The game is tuned so a solo
  player is never dependent on a working group — no mandatory healer role,
  no run-blocking if teammates play their class poorly. A **buff-type
  class** (self and party buffs) exists instead of a healer, strong enough
  to fully solo bosses on its own.
- **Scaling principle:** boss strength increases **slightly** with more
  players, but a full party should, in general, still be an **easier**
  experience than solo — more players adds more damage/mitigation coverage
  than the difficulty bump takes away. Curve not yet worked out
  numerically.
- **Gauntlet mode is solo-only** (Section 10) — the momentum/resource-curve
  tension the mode is built around depends on a single player's choices
  compounding over a run; party healing/support would undercut the "how
  deep can you go" test that makes gauntlet distinct from dungeon mode.
- Mitigation abilities that protect against damage (Shield's charge-block,
  in particular) protect **the user only**, not party members — consistent
  with the no-mandatory-role design; no class's kit should make it the
  "correct" pick a party can't function without.

---

## 14. World Boss Mode — SHELVED

**Status: Explicitly deprioritized this session. Kept here for reference
in case revisited later.**

- Original concept: 10+ concurrent players take down a massive boss
  together, mechanically distinct from dungeon bosses (too large for
  personal cutscene interactions).
- Key ideas from the design pass, worth keeping if revisited:
  - Interactions would need to be **diegetic/real-time-visible** rather
    than camera-locked cutscenes, since a crowd can't be sidelined the way
    a 3-person dungeon party can.
  - Damage-threshold weak-spot breaks and relic-destruction-triggers-
    theme-change were considered "generic" but are actually the *correct*
    mechanic at this scale — same break-landmark concept as Section 4,
    fed by aggregated group damage instead of one player's input.
  - Real, unsolved system work (not per-boss content) would be: group
    contribution/credit tracking, solo-viability scaling (leaned toward
    "stays huge, no hard timer, solo just takes longer" over "scales down
    to solo size"), and cross-client sync on trigger events.
- **Reason shelved:** author's read of the Roblox player base is
  solo-dominant — players rarely organize into 10-person groups
  organically, making the core premise (a crowd naturally assembling) shaky
  without matchmaking/aggregation work that isn't currently worth building.
  Boss gauntlet was judged a better use of the same development time for a
  primarily-solo audience.

---

## Open Threads / Not Yet Designed

Running list of things flagged during discussion but not yet resolved:

- [ ] Dagger's mastery verb — combo/bleed-uptime escalation meter is the
      leading idea, not finalized.
- [ ] Mage redirect: must absorbed element match the mage's own type
      (read-and-match puzzle) or does any element redirect as the mage's
      type (pure timing check)?
- [ ] Shield charge cost tiers by attack severity — direction set, exact
      values not tuned.
- [ ] Boss difficulty scaling curve vs. per-run compounding stats in the
      gauntlet (math not yet worked out).
- [ ] Party-size difficulty scaling curve (harder with more players, but
      net easier overall) — direction set, not tuned numerically.
- [ ] Cutscene ending beat: mash contest vs. timing/parry contest — leaning
      away from mash, not decided.
- [ ] Summon autoplay fail state: binary vs. degrading.
- [ ] Phase transition / dodge-burst cutscene trigger: immediate-interrupt
      vs. queued — same open question now applies to both systems.
- [ ] Void-sink transition: instant vs. drawn-out beat — leaning
      drawn-out.
- [ ] Domain shell variants (multiple layouts by boss archetype) — not
      needed yet, cheap to add later given current design.
- [ ] Gacha currency structure: one track vs. two.
- [ ] Whether gacha *is* the loot system or one part of a larger one.
- [ ] Whether the gacha pool includes any non-relic-bound character pulls,
      or every character pull is relic-bound (leaning relic-only).
- [ ] Pet parry-on-activation: skill-timed vs. automatic proc, and how
      much it should negate relative to a player's own timed parry.
- [ ] Gauntlet: does a gauntlet-run rare-boss win deserve a better reward
      than a lobby-rematch win, to keep the harder path worth choosing?
- [ ] Gauntlet: does a lobby rematch win fully reset the rare-boss pity
      token, or take multiple clears?
- [ ] What gauntlet actually rewards structurally (beyond fragments) once
      loot system exists in some form.
- [ ] "Every 30 minutes a world boss spawns"-style online-incentive hook —
      explicitly deferred, not designed.
