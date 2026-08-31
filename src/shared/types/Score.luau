-- src/shared/types/Score.luau
--
-- THE SHAPE OF A SCORE. Types only -- this module holds no data and no
-- behaviour, and nothing requires it at runtime except for the annotations.
--
-- IT LIVES OUTSIDE `definitions/scores/` ON PURPOSE. The loader walks that
-- folder and treats every ModuleScript in it as a score; a type module sitting
-- among them would be loaded as content and reported as malformed. Types are
-- not content, so they do not live in the content folder.
--
-- ============================================================================
-- WHY A SCORE IS INERT DATA AND NOT AN OBJECT
-- ============================================================================
--
-- No metatable, no `__index`, no methods. A Score is a Definition in
-- Architecture Part 3's sense: it owns the IDEA, is read once by whatever
-- plays it, and is never mutated. Attaching `__index` to it would be copying
-- the Component pattern to something that is not a component -- there is
-- nothing to look up, because a Score has no behaviour of its own.
--
-- The Conductor is the behaviour. This is what it reads.

local Score = {}

-- ============================================================================
-- EASING
-- ============================================================================
--
-- A CLOSED VOCABULARY, spelled as strings rather than `Enum.EasingStyle`.
-- Content should never have to type `Enum.EasingStyle.Cubic` -- that is an
-- implementation detail leaking into a data table, and it is the same reason
-- `AuraDefinitions` spells particle shapes as plain strings.
--
-- DELIBERATELY SHORT. Roblox offers thirteen families x four directions, and
-- writing all of them before any content needs them is the mistake this project
-- keeps catching. Linear and Cubic cover essentially every combat effect; add a
-- family when an effect actually wants one.
export type Easing =
    "LINEAR"
    | "CUBIC_IN"
    | "CUBIC_OUT"
    | "CUBIC_IN_OUT"

-- ============================================================================
-- WHAT A KEY CAN HOLD
-- ============================================================================
--
-- THIS UNION IS THE AWKWARD PART OF TYPING A SCORE, and it is worth being
-- honest about rather than pretending it is clean.
--
-- A track drives ANY property of ANY instance, so a value is whatever that
-- property accepts. The union below covers what is actually reachable today.
-- It will grow, and every time it grows the Conductor needs a matching
-- interpolation branch -- which is the real reason to keep the list explicit
-- rather than typing it `any`. `any` would compile and then silently accept a
-- type nothing knows how to lerp.
--
-- THE SPLIT THAT MATTERS IS NOT IN THE TYPE, IT IS IN THE BEHAVIOUR:
--
--   INTERPOLATES   number, Vector2, Vector3, Color3, UDim, UDim2, CFrame
--   SNAPS          boolean, string, EnumItem, and anything else
--
-- A boolean cannot be half-true, so `Enabled` snaps at its key. Lerping one
-- produces garbage or an error depending on the type.
--
-- THERE IS NO `isInterpolatable` CHECK, and looking for one is a dead end: the
-- Conductor's `lerpValue` returns the FIRST value unchanged for anything it
-- cannot interpolate, which IS the snap. One function, no branch, no flag on a
-- key. See `conductor/Evaluate.luau`.
export type Value =
    number
    | boolean
    | string
    | Vector2
    | Vector3
    | Color3
    | UDim
    | UDim2
    | CFrame
    | EnumItem

-- One moment on one track.
--
-- `ease` DESCRIBES ARRIVING AT THIS KEY, not leaving it. So interpolating from
-- key A to key B uses B's ease, and the first key's ease is never read.
--
-- Stated because it is genuinely ambiguous and both conventions exist. This one
-- matches Roblox's own `Pose`, which carries the EasingStyle for getting INTO
-- that pose -- and matching the engine beats being internally consistent with
-- ourselves and different from everything around us.
--
-- Absent means LINEAR.
export type Key = {
    t: number,
    v: Value,
    ease: Easing?,
}

-- ============================================================================
-- A TRACK -- ONE PROPERTY, OVER TIME
-- ============================================================================
--
-- `target` IS A PATH STRING, NEVER AN INSTANCE, and this is not negotiable.
--
-- The document is text in git and the same one plays on every spawned copy of
-- a prefab -- a boss that does not exist yet, then the next one. An Instance
-- reference cannot be serialised and would bind one Score to one clone.
-- `Conductor.play(score, root)` resolves these against whatever root it is
-- handed.
--
-- Dots walk children: `"Blade.Trail"` is `root.Blade.Trail`. An empty string
-- means the root itself.
--
-- THE COST, so it is not a surprise: the Score is coupled to a hierarchy SHAPE.
-- Rename a part inside the prefab and the path resolves to nothing, the track
-- animates nothing, and NO ERROR IS RAISED. Boot validation walking every
-- Score's paths against its declared prefab is the only defence, and it is the
-- reason that check is worth building rather than assuming.
export type Track = {
    target: string,
    property: string,
    keys: { Key },
}

-- ============================================================================
-- A CLIP TRACK -- a rig animation scheduled inside the Score
-- ============================================================================
--
-- `clip` is a manifest KEY, never an asset id. Putting a cloud identifier in a
-- Score would couple the document to Roblox's numbering and defeat the point of
-- having a manifest.
--
-- `at` is a moment in the SCORE's time, not the clip's. A clip at `at = 0.2`
-- starts two tenths of a second into the Score -- which is what makes a wind-up
-- effect BEFORE the swing expressible at all.
--
-- ============================================================================
-- WHY CLIPS ARE THEIR OWN LIST INSTEAD OF A TAGGED UNION IN `tracks`
-- ============================================================================
--
-- A union would preserve the "one list of rows" mental model, and it buys
-- nothing: a clip track and a property track share no fields, so every reader
-- would branch on a tag immediately and Luau would need narrowing at each one.
-- Two lists, two loops, no tag.
--
-- "ONE TRANSPORT" IS ABOUT THE CLOCK, NOT THE DATA LAYOUT. Both lists are
-- driven by the same `elapsed`, which is the property that actually matters.
--
-- ============================================================================
-- THE SCORE OWNS THE CLOCK. THIS IS THE CORRECTION.
-- ============================================================================
--
-- An earlier version of the Conductor had it backwards: the Score FOLLOWED an
-- externally-started clip, reading `AnimationTrack.TimePosition` as its clock.
-- That was justified as making drift impossible, and it broke three things:
--
--   1. THE DELAYED SLASH. A 0.4s clip, 800ms of silence, a burst at 1.2s --
--      Timeline.md's headline example. If the clip is the clock, the clock ends
--      at 0.4s and the burst never fires.
--   2. TWO CLIPS. No answer for whose clock wins.
--   3. ANYTHING BEFORE THE CLIP. A wind-up at t=0.1 has no moment to live at.
--
-- And the drift argument dissolved once the Conductor started the clip itself:
-- it sets the speed and knows the start moment, so there is nothing to diverge
-- FROM. Drift only existed because something else owned the clock.
export type ClipTrack = {
    clip: string,
    at: number,

    -- Playback rate. The Conductor sets it when starting the clip, which is
    -- how one authored swing serves a slow greatsword and a fast dagger without
    -- being re-authored -- see Animation.md 9.8.
    speed: number?,

    -- WHAT HAPPENS WHEN THE SCORE ENDS BEFORE THE CLIP DOES.
    --
    -- Default is to STOP IT, because that is predictable and because `duration`
    -- is authored precisely so you can cover a follow-through deliberately.
    --
    -- Set true when the animation should outlive its effects -- a long recovery
    -- after a short flourish. It does NOT survive a cancelled Score: a
    -- cancelled attack must not leave an arm swinging.
    letFinish: boolean?,
}

-- ============================================================================
-- THE SCORE
-- ============================================================================
--
-- `duration` IS AUTHORED, NOT DERIVED FROM THE LAST KEY, and the difference is
-- the entire reason a Score is more than a bag of tweens.
--
-- **Silence is legal.** An anime-style delayed slash is a 0.4s flourish, then
-- 800ms where nothing plays, then a burst at 1.2s. The transport keeps running
-- across the gap because it belongs to the Score, not to any track -- so
-- `duration` can be longer than the last key, and that is a normal thing to
-- author rather than an inconsistency.
--
-- Deriving it from the last key would make the gap unexpressible: playback
-- would end the instant the last track finished, and the burst at 1.2s would
-- never fire.
export type Score = {
    duration: number,
    tracks: { Track },

    -- Optional. A Score with no clips is a pure effect; a Score with no
    -- property tracks and one clip is just a clip with a transport around it.
    -- Both are legal.
    clips: { ClipTrack }?,

    -- Optional. One-shot actions at moments -- particle bursts, sounds.
    --
    -- THE THREE LISTS ARE ONE TIMELINE. They are separate arrays because a
    -- property track, a clip and a trigger share no fields, and a tagged union
    -- would make every reader branch immediately for nothing. "One transport"
    -- is about the CLOCK -- all three are driven by the same `elapsed` -- not
    -- about the data layout.
    triggers: { Trigger }?,
}

-- ============================================================================
-- THE RULE THAT KEEPS A SCORE FROM BECOMING A PILE OF SPECIAL CASES
-- ============================================================================
--
--     THE CONDUCTOR CONTROLS TIMING. THE ASSET CONTROLS BEHAVIOUR.
--
-- A Score says WHEN something happens. It does not say what a particle looks
-- like on its way out.
--
-- THE TEST: does this describe how ONE PARTICLE BEHAVES, or WHEN THE EFFECT
-- HAPPENS? The first is emitter configuration and already has its own animation
-- system; the second is a Score.
--
--   THE ASSET OWNS, set once in Studio     THE SCORE OWNS
--   ------------------------------------   ------------------------------
--   Lifetime, Speed, SpreadAngle, Drag     Enabled -- when it produces
--   the Size / Color / Transparency        Emit(n) -- a burst
--     CURVES on the emitter                a Beam's Width0
--   Texture, Squash, Rotation              a light's Brightness
--
-- **A ParticleEmitter is ALREADY an animation engine** -- it animates its own
-- particles over their lifetime through those curves, edited live in the
-- Properties panel with a graph widget Roblox provides. Keying `Rate`,
-- `Lifetime` and `Speed` frame by frame on the timeline re-implements that
-- badly and turns a Score into a config file with timestamps.
--
-- WHAT THIS RULE IS NOT: "never key a property." A beam widening and a light
-- dimming are exactly what property tracks exist for. The line is not
-- properties-versus-not, it is per-particle-behaviour versus when.
--
-- ============================================================================
-- A SPAN IS TWO KEYS. THERE IS NO SEPARATE "CLIP WITH AN END".
-- ============================================================================
--
-- "The emitter runs from 0.4 to 1.3" looks like it needs a start-and-end
-- concept, and it does not -- the relevant properties are booleans:
--
--     { target = "Blade.Sparks", property = "Enabled",
--       keys = { { t = 0.4, v = true }, { t = 1.3, v = false } } }
--
--     { target = "Whoosh", property = "Playing",      -- Sound.Playing
--       keys = { { t = 0.5, v = true }, { t = 0.9, v = false } } }
--
-- So a duration is already expressible, and adding a second span concept beside
-- property tracks would be two ways to say one thing.
--
-- **And an effect outliving its animation needs nothing either**: extend the
-- Score's `duration` past the clip, and already-emitted particles survive on
-- their own `Lifetime` after the emitter stops.
--
-- ============================================================================
-- A TRIGGER -- something that HAPPENS at a moment, rather than a value
-- ============================================================================
--
-- `ParticleEmitter:Emit(30)` is a METHOD CALL. There is no value to interpolate
-- toward and no "half emitted" state, so a property track cannot express it at
-- any key density.
--
-- FAKING IT WITH `Rate` DOES NOT WORK, and it is the obvious thing to try:
-- keying Rate 0 -> 60 -> 0 across one frame emits however many particles that
-- frame's `dt` happened to buy -- zero on a fast frame, a dozen on a slow one.
-- Frame-rate dependent, and wrong in a way that looks like a tuning problem.
--
-- THIS IS THE MECHANISM BEHIND "one particle, emit once, disappear":
--
--     Rate = 0 on the emitter, forever
--     one trigger at the moment you want the burst
--
-- ============================================================================
-- FIRES EXACTLY ONCE, AND THAT IS THE WHOLE DIFFICULTY
-- ============================================================================
--
-- A value track is re-read every frame and is idempotent -- asking twice for
-- Transparency at t=0.4 gives the same answer twice. A trigger is not: firing
-- it twice emits twice.
--
-- So the naive "is now past this key" test fires it again on every frame that
-- follows. Playback tracks which triggers have fired, and marks them BEFORE
-- attempting -- the same rule the wedge driver learned, that a retry loop
-- advances its counter before doing the work that can fail.
--
-- SCRUBBING DOES NOT FIRE TRIGGERS. Dragging a playhead back and forth across
-- t=0.3 would emit every time it crossed. Press Play to see them.
export type Trigger = {
    target: string,
    at: number,

    -- A CLOSED VOCABULARY, dispatched by a table -- the same shape as
    -- `Overlap.BY_SHAPE` and `EffectHandlers`. Content never spells a method
    -- name, so a typo is a boot-visible unknown action rather than a silent
    -- call into nothing.
    --
    -- DELIBERATELY TWO ENTRIES. Moonlite's equivalent is 611 lines for four
    -- classes, and most of it is machinery for cases nothing here has. Add an
    -- action when an effect actually wants one.
    action: "EMIT" | "SOUND",

    -- EMIT only. How many particles. Absent means the emitter's own
    -- `Rate`-independent default of 1.
    count: number?,
}

-- ============================================================================
-- HOW THE CONDUCTOR REACHES A RIG
-- ============================================================================
--
-- The Conductor knows nothing about Animators, manifests, or characters. It is
-- handed something that can turn a manifest key into a playing AnimationTrack,
-- and that is the entire contract.
--
-- INJECTED RATHER THAN REQUIRED, so the engine stays generic: the same
-- Conductor drives a player's character, a boss, a door, or a sword prop
-- without learning what any of them are. It is also what keeps the Conductor
-- from depending on a module that is currently flagged for replacement.
--
-- `play` returning nil is normal and not an error -- the clip may not be
-- uploaded yet. A missing animation must never take an effect down with it.
export type ClipPlayer = {
    play: (self: any, name: string, speed: number?) -> AnimationTrack?,
    stop: (self: any, name: string) -> (),
}

-- ============================================================================
-- WHAT ONE LOOKS LIKE -- an example, and NOT content
-- ============================================================================
--
-- Kept as a comment on purpose. A real-looking Score sitting in
-- `definitions/scores/` would be loaded as content and would be a lie: every
-- number in one of these is a judgement about something you are LOOKING at,
-- and none of them can be typed in advance.
--
--     local Example: Score.Score = {
--         duration = 0.65,          -- longer than the last key: the tail is
--                                   -- deliberate silence, not an oversight
--         tracks = {
--             {
--                 target = "Blade.Trail",     -- root.Blade.Trail
--                 property = "Enabled",
--                 keys = {                    -- a boolean SNAPS. no ease.
--                     { t = 0.00, v = false },
--                     { t = 0.08, v = true },
--                     { t = 0.50, v = false },
--                 },
--             },
--             {
--                 target = "Glow",            -- root.Glow
--                 property = "Brightness",
--                 keys = {                    -- a number INTERPOLATES
--                     { t = 0.00, v = 0.0 },
--                     { t = 0.12, v = 3.0, ease = "CUBIC_OUT" },
--                     { t = 0.55, v = 0.0, ease = "CUBIC_IN" },
--                 },
--             },
--         },
--     }
--
-- THE NUMBERS ABOVE ARE MEANINGLESS AND ARE MEANT TO BE. They illustrate the
-- shape. `0.12` and `3.0` are not defaults, recommendations, or a starting
-- point -- they are placeholders in a document nobody watched run.
--
-- ============================================================================
-- WHEN A REAL SCORE GETS WRITTEN, AND WHY IT IS NOT NOW
-- ============================================================================
--
-- A Score is authored by LOOKING, in the same order everything else in this
-- project is:
--
--   1. the mesh exists
--   2. it is attached to something that moves
--   3. the animation is authored, uploaded, and plays
--   4. THEN a trail, a glow and a burst get timed AGAINST that swing
--
-- Step 4 is the first moment any number here can be judged. Writing one at
-- step 0 is guessing at the output of a workflow nobody has run -- the same
-- error as writing a skill's `volume` before the hitbox has been watched, and
-- it was made here first on 2026-08-23 and caught immediately.
--
-- What CAN be built before any of that: the Conductor itself, tested against a
-- throwaway fixture. The engine does not need real content to be correct, and
-- a fixture belongs beside the tests rather than in `definitions/`.

return Score
