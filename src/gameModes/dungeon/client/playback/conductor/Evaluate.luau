-- src/gameModes/dungeon/client/playback/conductor/Evaluate.luau
--
-- THE STATELESS HALF OF THE CONDUCTOR. Applying a Score to real instances at a
-- given moment, capturing what was there first, and putting it back.
--
-- Nothing here remembers anything between calls. Hand `at()` any moment and it
-- writes what the Score says for that instant -- it has no idea whether it is
-- being played forwards, scrubbed backwards by an editor, or called once.
--
-- ============================================================================
-- WHY THIS IS ITS OWN FILE
-- ============================================================================
--
-- Two reasons, and the second is the load-bearing one.
--
-- IT BREAKS A REQUIRE CYCLE. `Playback` needs to evaluate every frame, and
-- `Conductor` needs to hand out `Playback`s. If evaluation lived in Conductor,
-- Playback would require Conductor and Conductor would require Playback. With
-- the stateless half extracted, both point here and nothing points back.
--
--     init.luau  ->  Evaluate      the public door
--     Playback   ->  Evaluate      one running Score
--     Evaluate   ->  (nothing)     a leaf
--
-- AND IT IS THE PART THE EDITOR NEEDS. Scrubbing is `Evaluate.at(score, root,
-- 0.4)` -- no playback, no transport, no state to reset. The editor and the
-- game reaching the same function is what makes the tool trustworthy; a second
-- preview path means you tune against something the game will not reproduce,
-- which is what kills homemade animation tools. Not difficulty. Divergence.

local Evaluate = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ScoreTypes = require(ReplicatedStorage:WaitForChild("types"):WaitForChild("Score"))

-- ============================================================================
-- EASING
-- ============================================================================
--
-- Bends `progress` through a curve before it is used. Both sides stay 0 -> 1;
-- only the shape between them changes.
--
-- FOUR, NOT FIFTY-TWO. Roblox exposes thirteen families x four directions, and
-- writing all of them before any content asks is the speculative-engine trap
-- this project keeps catching. Linear and Cubic cover essentially every combat
-- effect; adding a family is one line.
--
-- An unknown name falls back to LINEAR rather than erroring -- a typo'd ease
-- should make an effect look slightly wrong, never kill the frame it is drawn
-- in.
local EASING: { [string]: (number) -> number } = {
    LINEAR = function(t: number): number
        return t
    end,

    CUBIC_IN = function(t: number): number
        return t * t * t
    end,

    CUBIC_OUT = function(t: number): number
        local u = 1 - t
        return 1 - u * u * u
    end,

    CUBIC_IN_OUT = function(t: number): number
        if t < 0.5 then
            return 4 * t * t * t
        end
        local u = -2 * t + 2
        return 1 - (u * u * u) / 2
    end,
}

local function applyEase(progress: number, ease: string?): number
    local fn = ease and EASING[ease] or EASING.LINEAR
    return fn(progress)
end

-- ============================================================================
-- PATH RESOLUTION
-- ============================================================================
--
-- "Blade.Trail" -> root.Blade.Trail. An empty string is the root itself.
--
-- PATHS, NOT REFERENCES, because a Score is text in git and the same document
-- plays on every clone of a prefab. An Instance reference cannot be serialised
-- and would bind one Score to one copy.
--
-- THE COST IS A SILENT FAILURE, and it is the most likely bug in this system:
-- rename a part inside the prefab and the path resolves to nothing, the track
-- animates nothing, and NOTHING ERRORS. That is why the warning below fires
-- once rather than never or every frame.
-- EXPORTED so `Baseline` can use the same resolution and the same guarded
-- property access. Two copies of a dotted-path walk is two things that can
-- disagree about what "Blade.Trail" means.
function Evaluate.resolve(root: Instance, path: string): Instance?
    if path == "" then
        return root
    end

    local current: Instance? = root
    for segment in string.gmatch(path, "[^%.]+") do
        if not current then
            return nil
        end
        current = current:FindFirstChild(segment)
    end

    return current
end

-- WARNED ONCE PER TRACK, EVER, keyed by the track table itself -- a stable
-- identity for the life of the Score. Weak keys so a discarded Score does not
-- pin its tracks in memory.
--
-- A warning printed every frame is a warning nobody reads and an output window
-- nobody can use. A warning printed never is the silent failure above.
local warned: { [any]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function warnOnce(track: any, message: string)
    if warned[track] then
        return
    end
    warned[track] = true
    warn(message)
end

-- ============================================================================
-- DYNAMIC PROPERTY ACCESS
-- ============================================================================
--
-- The two genuinely dynamic operations, extracted so they can be passed to
-- `pcall` BY REFERENCE rather than wrapped in a closure.
--
-- NOT ONLY STYLE: `pcall(function() ... end)` allocates a fresh closure every
-- call, and `at()` runs once per track per frame -- so the wrapped version
-- produces garbage on a fixed schedule for the life of the game. That is the
-- same objection that keeps `SpatialComponent`'s ring buffer preallocated.
--
-- The `:: any` casts are honest rather than a workaround. This engine stores
-- { instance, property, value } and assigns; it has no idea what a
-- ParticleEmitter is, which is exactly why the type checker cannot help here
-- and exactly why adding an effect never touches this file.
--
-- BOTH RETURN `any`, INCLUDING THE ASSIGNMENT, which has nothing to return.
-- Luau types `pcall(f, ...)` as `(boolean, R...)` where `R...` is f's DECLARED
-- returns, so a void function makes `local ok, err = pcall(f)` fail to
-- type-check -- even though pcall genuinely hands back the error string at
-- runtime. Declaring one return gives that string somewhere to land.
function Evaluate.assign(instance: Instance, property: string, value: any): any
    (instance :: any)[property] = value
    return nil
end

function Evaluate.read(instance: Instance, property: string): any
    return (instance :: any)[property]
end

-- ============================================================================
-- INTERPOLATION -- AND WHY SNAPPING IS THE SAME FUNCTION
-- ============================================================================
--
-- Returns `a` unchanged for anything that cannot be interpolated, which IS the
-- snap behaviour: the previous key's value is held until the next key's moment
-- arrives, and then that one becomes `a`. No branch, no second code path, no
-- "is this snappable" flag on a key.
--
-- WHY BOOLEANS AND ENUMS MUST NOT LERP: there is no half-enabled Trail and no
-- three-quarters-Neon material. Interpolating one produces garbage or an error
-- depending on the type, and the error would be per-frame.
--
-- STORE ROTATION AS A CFrame, NEVER THREE ANGLES -- the real trap in this list.
-- Three loose numbers interpolate 350 -> 10 degrees the LONG way round,
-- travelling 340 degrees backwards. `CFrame:Lerp` slerps and takes the short
-- path. The rule that avoids it: store the richest type the engine gives you
-- and lerp THAT, rather than decomposing into numbers and lerping the pieces.
local function lerpValue(a: any, b: any, t: number): any
    local kind = typeof(a)

    if kind == "number" then
        return a + (b - a) * t
    end

    -- Each of these ships its own `:Lerp`. Using theirs rather than a
    -- component-wise version by hand is not laziness -- Color3:Lerp and
    -- CFrame:Lerp are not naive component lerps, and hand-rolling either gets
    -- a subtle case wrong for free.
    if kind == "Vector3"
        or kind == "Vector2"
        or kind == "Color3"
        or kind == "CFrame"
        or kind == "UDim2"
    then
        return a:Lerp(b, t)
    end

    -- UDim has no :Lerp. Offset is rounded because it is an integer pixel
    -- count -- a fractional one gets truncated somewhere further down and
    -- produces a one-pixel jitter nobody can trace.
    if kind == "UDim" then
        return UDim.new(
            a.Scale + (b.Scale - a.Scale) * t,
            math.round(a.Offset + (b.Offset - a.Offset) * t))
    end

    -- boolean, string, EnumItem, asset id, anything else: SNAP.
    return a
end

-- ============================================================================
-- FINDING THE PAIR OF KEYS A MOMENT SITS BETWEEN
-- ============================================================================
--
-- Returns (a, b). A nil `b` means "hold a" -- the moment is either before the
-- first key or past the last.
--
-- ASSUMES KEYS ARE SORTED BY `t`. A linear scan rather than a binary search on
-- purpose: a track has a handful of keys, and a binary search would be harder
-- to read for no measurable gain at this size.
--
-- BEFORE THE FIRST KEY HOLDS THE FIRST VALUE rather than doing nothing. A track
-- whose first key is at t=0.08 still describes what the property should be at
-- t=0.00. Doing nothing would leave it at whatever the prefab shipped with for
-- the first 80ms, which reads as a flicker.
local function keysAround(keys: { ScoreTypes.Key }, t: number): (ScoreTypes.Key?, ScoreTypes.Key?)
    local count = #keys
    if count == 0 then
        return nil, nil
    end

    if t <= keys[1].t then
        return keys[1], nil
    end

    for i = 1, count - 1 do
        if t < keys[i + 1].t then
            return keys[i], keys[i + 1]
        end
    end

    return keys[count], nil
end

-- ============================================================================
-- THE ENGINE
-- ============================================================================

-- Applies a Score at ONE moment. No state, no accumulator, no notion of having
-- been playing. `Playback` is a loop around this function and nothing more.
function Evaluate.at(score: ScoreTypes.Score, root: Instance, t: number)
    for _, track in ipairs(score.tracks) do
        local instance = Evaluate.resolve(root, track.target)

        if not instance then
            warnOnce(track, string.format(
                "[Conductor] target '%s' does not exist under %s -- this track "
                    .. "animates nothing. Renamed part, or a prefab that does "
                    .. "not match the Score?",
                track.target, root:GetFullName()))
            continue
        end

        local a, b = keysAround(track.keys, t)
        if not a then
            continue
        end

        local value: any
        if b then
            local span = b.t - a.t
            -- Two keys at the same moment would divide by zero. Treat it as
            -- "already arrived" rather than erroring: duplicate timestamps are
            -- an authoring slip, not something worth killing a frame over.
            local progress = if span > 0 then (t - a.t) / span else 1
            value = lerpValue(a.v, b.v, applyEase(progress, b.ease))
        else
            value = a.v
        end

        -- pcall'd because a bad property name or a wrong value type errors, and
        -- this runs every frame: unguarded, one typo in content becomes an
        -- unreadable wall of identical errors rather than one warning.
        local ok, err = pcall(Evaluate.assign, instance, track.property, value)

        if not ok then
            warnOnce(track, string.format(
                "[Conductor] could not set %s.%s = %s (%s): %s",
                track.target, track.property, tostring(value), typeof(value),
                tostring(err)))
        end
    end
end

-- Baseline capture and restore moved to Baseline.luau on 2026-08-23. They are
-- not stateless: ownership of a property is SHARED between overlapping
-- playbacks and has to be refcounted, which is state this file must not hold.

return Evaluate
