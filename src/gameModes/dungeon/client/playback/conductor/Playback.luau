-- src/gameModes/dungeon/client/playback/conductor/Playback.luau
--
-- ONE RUNNING SCORE. Owns the transport: elapsed time, the frame connection,
-- and the baseline to put back when it stops.
--
-- Constructed by `Conductor.play` and returned to the caller, so this is the
-- object a calling system actually holds:
--
--     local playback = Conductor.play(score, fx)
--     playback:stop()
--     playback:isPlaying()
--
-- ============================================================================
-- WHY THIS IS A REAL OBJECT WHEN A SCORE DELIBERATELY IS NOT
-- ============================================================================
--
--   a Score      inert data. Read once, never mutated, no behaviour. A
--                Definition (Architecture Part 3) -- no metatable, nothing to
--                look up.
--   a Playback   state that changes every frame, plus the behaviour that
--                changes it. That is what a metatable is FOR.
--
-- ============================================================================
-- AND WHY IT IS ITS OWN FILE
-- ============================================================================
--
-- It was declared inside Conductor.luau first. That is fine right up until
-- someone reads `playback:stop()` at a call site, or sees "Playback" in a
-- warning, and goes looking for the file -- there wasn't one. A class with
-- state, a lifecycle and a public API that exists only as a local inside
-- another module is findable by whoever wrote it and nobody else.
--
-- The codebase already splits this way everywhere: SpatialComponent,
-- HurtboxComponent and IdentityComponent are each one file.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Evaluate = require(script.Parent:WaitForChild("Evaluate"))
local Baseline = require(script.Parent:WaitForChild("Baseline"))
local Actions = require(script.Parent:WaitForChild("Actions"))
local ScoreTypes = require(ReplicatedStorage:WaitForChild("types"):WaitForChild("Score"))

local Playback = {}
Playback.__index = Playback

export type Options = {
    -- HOW THE SCORE REACHES A RIG. Required only if the Score has clip tracks;
    -- a pure effect needs nothing. A Score with clips and no player warns once
    -- and plays its property tracks anyway, because a missing animation must
    -- never take an effect down with it.
    clipPlayer: ScoreTypes.ClipPlayer?,

    -- Scales the whole transport -- every property track AND every clip, since
    -- the Conductor sets each clip's rate when it starts it. That is what keeps
    -- one authored swing serving a slow greatsword and a fast dagger.
    speed: number?,

    onFinished: (() -> ())?,
}

type State = {
    score: ScoreTypes.Score,
    root: Instance,
    options: Options,

    baseline: { Baseline.Claim },

    elapsed: number,
    connection: RBXScriptConnection?,
    finished: boolean,

    -- Clip index -> the AnimationTrack it started. The handle needed to stop it
    -- later. Recorded even when `letFinish` is set, because a CANCELLED Score
    -- stops everything regardless -- an interrupted attack must not leave an
    -- arm mid-swing.
    started: { [number]: AnimationTrack },

    -- Clip index -> "its moment has passed", whether or not it actually
    -- started. SEPARATE FROM `started` ON PURPOSE, and the reason is a bug
    -- that was written first: a clip that fails to start has no AnimationTrack
    -- to record, and marking it by assigning nil to `started` REMOVES the key
    -- rather than setting it -- so the failure would be retried, and warned
    -- about, every single frame for the rest of the Score.
    attempted: { [number]: boolean },

    -- Trigger index -> "already fired". Same fire-exactly-once problem as
    -- clips, and the sharper version of it: a clip fired twice replaces itself,
    -- a burst fired twice emits twice as many particles.
    fired: { [number]: boolean },
}

-- METHODS TAKE `self: State`, NOT the exported type, and call each other as
-- `Playback.stop(self)` rather than `self:stop()`.
--
-- Both are for the same reason: the exported type does not exist until every
-- method is on the table (see the note above the export at the bottom).
-- `State` describes the FIELDS, which is all a method needs of itself.
--
-- Callers outside this file still write `playback:stop()`. This is only how the
-- module talks to itself.

-- Starts any clip whose moment has arrived and has not fired yet.
--
-- A CLIP IS AN EVENT, NOT A VALUE AT A MOMENT, which is why this lives in
-- Playback and not in Evaluate. "What is Transparency at t=0.4" has an answer
-- for any t; "start the swing" happens once or not at all. That is also why
-- scrubbing an editor's playhead shows property state only -- there is no
-- meaningful half-started animation to display.
local function fireDueClips(self: State)
    local clips = self.score.clips
    if not clips then
        return
    end

    local player = self.options.clipPlayer

    for index, clipTrack in ipairs(clips) do
        if self.attempted[index] or clipTrack.at > self.elapsed then
            continue
        end

        -- MARKED BEFORE THE ATTEMPT, NOT AFTER. A clip that fails must not be
        -- retried next frame, and the same rule the wedge driver learned: any
        -- retry loop advances its counter BEFORE doing the work that can fail,
        -- or a failure repeats sixty times a second forever.
        self.attempted[index] = true

        if not player then
            warn(string.format(
                "[Conductor] score wants clip '%s' but no clipPlayer was "
                    .. "supplied -- property tracks still play",
                clipTrack.clip))
            continue
        end

        -- THE SCORE'S SPEED MULTIPLIES THE CLIP'S. The Conductor owns the
        -- transport, so it owns every rate inside it -- which is exactly what
        -- makes drift impossible without the Score having to watch anything.
        local rate = (clipTrack.speed or 1) * (self.options.speed or 1)

        local ok, animationTrack = pcall(player.play, player, clipTrack.clip, rate)

        if ok and animationTrack then
            self.started[index] = animationTrack
        elseif not ok then
            warn(string.format(
                "[Conductor] could not start clip '%s': %s",
                clipTrack.clip, tostring(animationTrack)))
        end
        -- ok and nil means the clip is simply not uploaded yet. That is a
        -- normal state during development and the clip player has already said
        -- so once -- nothing to add here.
    end
end

-- Fires any trigger whose moment has arrived and has not fired yet.
--
-- SAME STRUCTURE AS CLIPS, AND FOR THE SAME REASON: both are events rather
-- than values, so both need a fired-set and both mark BEFORE attempting.
--
-- The asymmetry worth knowing: a clip fired twice replaces itself and looks
-- like a stutter. A burst fired twice emits twice as many particles and looks
-- like the effect was authored that way.
local function fireDueTriggers(self: State)
    local triggers = self.score.triggers
    if not triggers then
        return
    end

    for index, trigger in ipairs(triggers) do
        if self.fired[index] or trigger.at > self.elapsed then
            continue
        end

        self.fired[index] = true

        local instance = Evaluate.resolve(self.root, trigger.target)
        if not instance then
            warn(string.format(
                "[Conductor] trigger target '%s' does not exist under %s",
                trigger.target, self.root:GetFullName()))
            continue
        end

        -- pcall'd because an action reaches into the Roblox API and a wrong
        -- target type can throw. One bad trigger must not take down the frame
        -- the rest of the Score is drawn in.
        -- `result` is Actions.run's RETURN VALUE when ok, and the error string
        -- when not -- pcall's two meanings for one slot. Hence two branches
        -- rather than one.
        local ok, result = pcall(Actions.run, instance, trigger)

        if not ok then
            warn(string.format(
                "[Conductor] trigger %s on '%s' errored: %s",
                trigger.action, trigger.target, tostring(result)))
        elseif result == false then
            warn(string.format(
                "[Conductor] unknown trigger action '%s' -- known: EMIT, SOUND",
                tostring(trigger.action)))
        end
    end
end

-- Extracted so it can be passed to `pcall` by reference rather than wrapped in
-- a closure. Same reason as `Evaluate`'s property helpers.
local function stopTrack(animationTrack: AnimationTrack)
    animationTrack:Stop()
end

-- The real teardown, and IDEMPOTENT on purpose: a playback can finish on its
-- own and then be stopped by a caller that has not noticed, and releasing the
-- same claims twice would decrement a refcount this playback no longer holds --
-- restoring a property somebody else is still driving.
--
-- `cancelled` distinguishes the two ways a Score can end, and the distinction
-- only matters to `letFinish`.
--
-- DECLARED BEFORE `step`, WHICH CALLS IT, AND THAT IS NOT COSMETIC. A `local`
-- declared after a function body cannot be captured by it -- the name would
-- resolve to a nil global at runtime instead. Written the other way round
-- first, and it would have failed on the first Score that reached its own
-- duration.
local function finish(self: State, cancelled: boolean)
    if self.finished then
        return
    end
    self.finished = true

    if self.connection then
        self.connection:Disconnect()
        self.connection = nil
    end

    -- STOP THE CLIPS THIS SCORE STARTED.
    --
    -- `letFinish` buys an animation the right to outlive its effects -- a long
    -- recovery after a short flourish -- but ONLY on a natural end. A cancelled
    -- Score stops everything: an interrupted attack must not leave an arm
    -- swinging on its own.
    local clips = self.score.clips
    if clips then
        for index, animationTrack in pairs(self.started) do
            local clipTrack = clips[index]
            if clipTrack and clipTrack.letFinish and not cancelled then
                continue
            end
            pcall(stopTrack, animationTrack)
        end
    end
    table.clear(self.started)
    table.clear(self.attempted)
    table.clear(self.fired)

    Baseline.release(self.baseline)

    if self.options.onFinished then
        self.options.onFinished()
    end
end

function Playback.step(self: State, dt: number)
    if self.finished then
        return
    end

    -- THE SCORE OWNS THE CLOCK. Always. It does not read any clip's
    -- TimePosition, and no clip can end it early -- see the correction note in
    -- `types/Score.luau` for the three things that broke when it did.
    self.elapsed += dt * (self.options.speed or 1)

    fireDueClips(self)
    fireDueTriggers(self)
    Evaluate.at(self.score, self.root, self.elapsed)

    -- DURATION IS AUTHORED, NOT THE LAST KEY'S TIME. A Score may end in
    -- deliberate silence -- a 0.4s flourish, 800ms of nothing, a burst at 1.2s
    -- -- and ending at the last key would make that gap unexpressible.
    if self.elapsed >= self.score.duration then
        finish(self, false)
    end
end

-- MEANS CANCEL.
--
-- A caller reaching for `stop()` is interrupting something -- the attack was
-- rejected, the entity died, the player swapped weapons. Reaching `duration`
-- naturally goes through `finish(self, false)` from `step` instead, which is
-- the only path where `letFinish` applies.
function Playback.stop(self: State)
    finish(self, true)
end

function Playback.isPlaying(self: State): boolean
    return not self.finished
end

-- EXPORTED, AND DECLARED AFTER THE METHODS ON PURPOSE.
--
-- `typeof(setmetatable(...))` reads whatever is on `Playback` AT THIS POINT IN
-- THE FILE. Put this above the methods and it resolves to a table of fields
-- with no methods -- so `playback:stop()` silently stops type-checking while
-- still running fine, which is the worst kind of wrong.
--
-- Same trap, same fix, same reason as `IdentityComponent.Identity`.
export type Playback = typeof(setmetatable({} :: State, Playback))

-- BUILD THE STATE, WIRE IT, THEN ATTACH THE METATABLE ON THE WAY OUT.
--
-- The order is a type-checking fix, not a style choice. Written the other way
-- -- `local self = setmetatable({...}, Playback)` -- the local infers as the
-- metatable'd type, and passing it to a method declared `self: State` fails
-- with "expected this to be 'State'". Building the plain table first means
-- `state` is unambiguously a `State`, which is what the methods want.
--
-- Connecting before `setmetatable` is safe: `PreRender` cannot fire until the
-- next frame, and `Playback.step(state, dt)` reaches the function through the
-- module table anyway rather than through the metatable.
function Playback.new(score: ScoreTypes.Score, root: Instance, options: Options): Playback
    local state: State = {
        score = score,
        root = root,
        options = options,
        baseline = Baseline.acquire(score, root),
        elapsed = 0,
        connection = nil,
        finished = false,
        started = {},
        attempted = {},
        fired = {},
    }

    -- THE ONE CLOSURE IN THE WHOLE CONDUCTOR, AND IT CANNOT BE REMOVED.
    -- `:Connect(Playback.step)` would call `step(dt)` with the delta as the
    -- first argument, because a Roblox signal passes its own arguments and
    -- knows nothing about method binding. One forwarding line is the whole cost.
    --
    -- PreRender, not Heartbeat: it fires before the frame is drawn, so a value
    -- written here is visible on the SAME frame rather than one late. It is
    -- also the modern name for RenderStepped, and CLIENT-ONLY -- which is one
    -- more reason a Score cannot accidentally be run on the server.
    state.connection = RunService.PreRender:Connect(function(dt: number)
        Playback.step(state, dt)
    end)

    return setmetatable(state, Playback)
end

return Playback
