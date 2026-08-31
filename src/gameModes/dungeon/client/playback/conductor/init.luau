-- src/gameModes/dungeon/client/playback/conductor/init.luau
--
-- THE CONDUCTOR. Plays a Score. See Timeline.md.
--
-- Roblox ships exactly one animation player and it bends joints. That is the
-- entirety of what it does. A beam widening, a light dimming, a prop sliding,
-- a particle burst landing on a beat -- none of it has an engine behind it.
-- Not a limited one. NONE. This is that engine.
--
--     local playback = Conductor.play(score, fx)
--     local playback = Conductor.play(score, fx, { clipPlayer = rig })
--     Conductor.evaluate(score, fx, 0.4)      -- one moment, no transport
--
-- ============================================================================
-- THE SCORE OWNS THE CLOCK
-- ============================================================================
--
-- You author `duration`. Everything -- property tracks and clip tracks alike --
-- is scheduled inside it, and the Conductor drives all of it from one
-- `elapsed`. That is what "one transport" means.
--
-- IT USED TO BE THE OTHER WAY ROUND and that was wrong. An earlier version had
-- the Score FOLLOW an externally-started clip, reading its `TimePosition`.
-- Three things broke: a Score could not outlive its clip (killing the delayed
-- slash, which is Timeline.md's headline example), two clips had no answer for
-- whose clock wins, and nothing could be scheduled BEFORE the clip started.
--
-- The drift argument that justified it dissolved once the Conductor started the
-- clip itself -- it sets the rate and knows the start moment, so there is
-- nothing to diverge from. See `types/Score.luau` for the full note.
--
-- ============================================================================
-- THE THREE FILES
-- ============================================================================
--
--   init.luau      this. The public door, and nothing else.
--   Evaluate       stateless: apply a Score at a moment. Paths, easing, lerp.
--   Baseline       who owns which property, refcounted, and what it looked
--                  like before anyone touched it.
--   Playback       one running Score: elapsed, the frame connection, stop.
--
-- Dependencies point one way and nothing points back:
--
--     init      ->  Evaluate, Playback
--     Playback  ->  Evaluate, Baseline
--     Baseline  ->  Evaluate
--     Evaluate  ->  (nothing)
--
-- That is why the stateless half is its own module rather than living here.
-- Playback has to evaluate every frame; if evaluation lived in this file the
-- two would require each other.
--
-- ============================================================================
-- CLIENT ONLY, AND NOT AS A PREFERENCE
-- ============================================================================
--
-- Roblox has playback state for an ANIMATION, so a server-started clip
-- replicates as one message: "track 123 at time T". It has no playback state
-- for a beam, so a server-run Score could only replicate each value as it
-- changes -- roughly 120 replications x every player for a half-second effect
-- with four tracks.
--
-- So we copy Roblox's own trick by hand. The Score already lives on every
-- client (ReplicatedStorage), and the server sends a NAME. `PreRender` does not
-- even exist on the server, which makes this structural rather than a rule
-- somebody has to remember.
--
-- ============================================================================
-- WHAT IS DELIBERATELY NOT HERE YET
-- ============================================================================
--
-- Scoped to Timeline.md Part 13's step one, on purpose -- everything below has
-- been argued and never run, and a prototype is what turns that into a design.
--
--   TRIGGERS         one-shot events ("emit 30 particles", "play a sound").
--                    They need a fire-exactly-once rule a value track does not,
--                    so they are their own step.
--   SERVER ANCHOR    `elapsed = GetServerTimeNow() - anchor`, for moments two
--                    players must see identically. A third clock, one line, and
--                    nothing needs it until a combo or a cutscene exists.
--   BAKING           precomputing every frame at load. A real optimisation for
--                    a long Score and pure overhead for a half-second one.
--   PATH VALIDATION  walking every Score's targets against its prefab at boot.
--                    The only defence against the silent failure in Evaluate.
--
-- ============================================================================
-- IF DELETING THIS WOULD CHANGE WHO TAKES DAMAGE, THE DESIGN IS WRONG
-- ============================================================================
--
-- A Score holds cosmetic values and no gameplay data. Nothing here decides a
-- hit, and a Score that stalls, errors, or never plays must not alter a single
-- outcome. That is what lets this run on the client at all.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Evaluate = require(script:WaitForChild("Evaluate"))
local Playback = require(script:WaitForChild("Playback"))
local ScoreTypes = require(ReplicatedStorage:WaitForChild("types"):WaitForChild("Score"))

local Conductor = {}

export type Options = Playback.Options
export type Playback = Playback.Playback

-- Applies a Score at ONE moment. No transport, no state.
--
-- PUBLIC BECAUSE THE EDITOR SCRUBS WITH IT. What you see while tuning is
-- produced by the same code the game runs -- a second preview path means you
-- tune against something the game will not reproduce.
function Conductor.evaluate(score: ScoreTypes.Score, root: Instance, t: number)
    Evaluate.at(score, root, t)
end

-- Starts a Score on `root` and returns the running playback.
--
-- `root` is whatever the Score's `target` paths are relative to: a cloned
-- effect prefab, a weapon, a character. The same Score plays on any of them as
-- long as the paths resolve.
function Conductor.play(score: ScoreTypes.Score, root: Instance, opts: Options?): Playback
    return Playback.new(score, root, opts or {})
end

return Conductor
