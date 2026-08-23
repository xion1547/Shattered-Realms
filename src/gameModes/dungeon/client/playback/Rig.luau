-- src/gameModes/dungeon/client/playback/Rig.luau
--
-- ONE BODY'S ANIMATION TRACKS. Builds them, caches them, rebuilds them when the
-- body changes, and plays them. See Animation.md Part 7.
--
-- PURE PLAYBACK. This file never decides WHETHER to play something -- InputSystem
-- and Presenters decide, this renders. It holds no gameplay number, reads no hit
-- volume, and could be deleted without changing who takes damage.
--
-- ============================================================================
-- WHY THIS IS CALLED Rig AND NOT Animation
-- ============================================================================
--
-- Animation.md Part 7 sketches this module as `Animation.luau`. That name is
-- wrong here for two reasons that both bite at a require site:
--
--   1. `Animation` IS A ROBLOX CLASS -- the near-empty Instance whose only
--      meaningful property is AnimationId. This module builds those; being
--      named after them makes `local Animation = require(...)` ambiguous with
--      `Instance.new("Animation")` in the same file.
--   2. Animation.md Part 1 opens by warning that three separate things already
--      wear the word "animation" (the asset, the id, the track). A fourth is
--      not free, and Architecture Part 4 has a whole section on exactly this
--      class of collision.
--
-- What this module actually owns is ONE BODY'S set of tracks, and it is the
-- body that makes them invalid when it changes. `Rig` names that.
--
-- ============================================================================
-- THE FAILURE THIS FILE EXISTS TO PREVENT
-- ============================================================================
--
-- DEATH PRODUCES A NEW RIG WITH A NEW ANIMATOR, and every track cached from the
-- old body is dead the instant it is replaced. Not erroring -- dead. Calling
-- :Play() on one does nothing at all, forever, silently.
--
-- So respawn and loadout change go through THE SAME `_rebuild`. Animation.md
-- 7.3 states the rule and the reason: if they are two code paths, one of them
-- rots, and the one that rots is whichever is exercised less. Respawn happens
-- constantly and loadout change is rare, so the rare one would break and nobody
-- would notice for a month.

local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimationManifest = require(
    ReplicatedStorage:WaitForChild("definitions"):WaitForChild("AnimationManifest"))

local Rig = {}
Rig.__index = Rig

-- How long to wait for the CDN before calling an asset unresolved.
--
-- GENEROUS ON PURPOSE. This number only ever decides when to PRINT something --
-- a track that resolves late still plays fine, because `_verify` runs off the
-- main flow and nothing waits on it. So the two errors are not symmetric: too
-- short cries wolf at every player on a slow connection, too long just means a
-- real problem is reported a few seconds later than it could have been.
local RESOLVE_TIMEOUT = 10
local RESOLVE_POLL = 0.25

-- The loadout used when nobody has said otherwise. One class exists.
local DEFAULT_LOADOUT = "WARRIOR"

function Rig.new(player: Player?)
    local subject = player or Players.LocalPlayer
    assert(subject, "[Rig] needs a Player")

    local self = setmetatable({
        player = subject,
        loadout = DEFAULT_LOADOUT,

        -- name -> AnimationTrack, valid only for the CURRENT body.
        _tracks = {},

        -- name -> Animation instance. Kept alive deliberately: an Animation
        -- that is garbage collected takes its loaded track with it, and the
        -- symptom is a track that plays for a while and then stops working.
        _animations = {},

        _animator = nil,
        _connections = {},

        -- Bumped on every rebuild. A `_verify` pass belonging to a previous
        -- body compares this and bails rather than reporting on tracks that
        -- have already been thrown away -- otherwise dying mid-verification
        -- prints failures about a corpse.
        _generation = 0,

        _destroyed = false,
    }, Rig)

    return self
end

-- ============================================================================
-- LIFECYCLE
-- ============================================================================

function Rig:start()
    assert(not self._destroyed, "[Rig] destroyed")

    -- CharacterAdded fires for every respawn AND may already have fired before
    -- this runs, which is why the current character is handled separately
    -- rather than trusted to arrive. Missing the first one leaves a player
    -- who cannot animate until they die once -- a bug that reproduces only on
    -- a fast join.
    table.insert(self._connections, self.player.CharacterAdded:Connect(function(character)
        self:_bind(character)
    end))

    if self.player.Character then
        self:_bind(self.player.Character)
    end
end

-- Switches loadout and rebuilds. Safe to call with the current loadout; that
-- is a plain rebuild, which is occasionally what you want after editing the
-- manifest during a live session.
function Rig:setLoadout(loadout: string)
    assert(type(loadout) == "string", "[Rig] loadout must be a string")
    self.loadout = loadout
    self:_rebuild()
end

function Rig:destroy()
    self._destroyed = true

    for _, connection in ipairs(self._connections) do
        connection:Disconnect()
    end
    table.clear(self._connections)

    self:_clearTracks()
    self._animator = nil
end

-- ============================================================================
-- PLAYING
-- ============================================================================

-- Plays a manifest animation and RETURNS ITS TRACK.
--
-- THE RETURN VALUE IS THE SEAM TO THE CONDUCTOR, and it is the whole reason
-- this returns anything at all. A Score's clock can be "follow this
-- AnimationTrack" (Timeline.md), which needs the live handle -- `.TimePosition`
-- to read, `.Stopped` to end on, `:GetMarkerReachedSignal` for cosmetic beats.
-- Without the handle a caller would have to start its own stopwatch, which is
-- precisely the failure the Conductor exists to prevent.
--
-- Returns nil rather than erroring when the track is not available -- the body
-- is mid-respawn, or the asset is not uploaded yet. A missing animation must
-- never take an attack down with it: the swing is a server fact and the clip is
-- a picture of it, so the picture failing is a cosmetic problem.
function Rig:play(name: string, fadeOverride: number?): AnimationTrack?
    local track = self._tracks[name]
    if not track then
        return nil
    end

    local row = AnimationManifest.get(name)
    local fade = fadeOverride or row.fadeTime or 0.1

    -- RESTARTED, NOT RESUMED. Clicking attack twice should replay the swing
    -- from the top; without the stop, the second :Play() on an already-playing
    -- track is ignored and the input reads as dropped.
    if track.IsPlaying then
        track:Stop(0)
    end

    track:Play(fade)
    return track
end

function Rig:stop(name: string, fade: number?)
    local track = self._tracks[name]
    if track and track.IsPlaying then
        track:Stop(fade or 0.1)
    end
end

function Rig:stopAll(fade: number?)
    for _, track in pairs(self._tracks) do
        if track.IsPlaying then
            track:Stop(fade or 0.1)
        end
    end
end

-- The live handle without starting it. For anything that needs to inspect or
-- follow a track it did not start.
function Rig:track(name: string): AnimationTrack?
    return self._tracks[name]
end

function Rig:isReady(): boolean
    return self._animator ~= nil
end

-- ============================================================================
-- BUILDING
-- ============================================================================

function Rig:_bind(character: Model)
    if self._destroyed then
        return
    end

    -- The Humanoid may not exist the instant CharacterAdded fires. Waiting on
    -- the child rather than assuming it is what makes this survive a slow
    -- character load, which is the normal case on a busy server.
    local humanoid = character:FindFirstChildOfClass("Humanoid")
        or character:WaitForChild("Humanoid", 10)

    if not humanoid then
        warn("[Rig] no Humanoid on this character after 10s -- no animations "
            .. "will play on this body")
        return
    end

    -- THE ANIMATOR MUST ALREADY EXIST, not be created here. An Animator created
    -- by a LocalScript does not replicate, so tracks loaded through it would
    -- play on this screen and nowhere else -- five of six players would see a
    -- statue (Timeline.md 2.4, Animation.md Part 3). Roblox puts one inside
    -- every character's Humanoid; if it is genuinely absent, that is a fault to
    -- report rather than paper over.
    local animator = humanoid:FindFirstChildOfClass("Animator")
        or humanoid:WaitForChild("Animator", 10)

    if not animator then
        warn("[Rig] no Animator inside this Humanoid. NOT creating one -- a "
            .. "client-created Animator does not replicate, so the animation "
            .. "would be invisible to everyone else")
        return
    end

    self._animator = animator
    self:_rebuild()
end

-- Throws away every cached track and builds the current loadout's set.
--
-- THE ONE PATH. Respawn calls it through `_bind`; a loadout change calls it
-- directly. See the header for why there is not one of each.
function Rig:_rebuild()
    if self._destroyed or not self._animator then
        return
    end

    self._generation += 1
    local generation = self._generation

    self:_clearTracks()

    local rows = AnimationManifest.forLoadout(self.loadout)
    local pendingUpload = {}

    for name, row in pairs(rows) do
        if row.assetId == AnimationManifest.NOT_UPLOADED then
            table.insert(pendingUpload, name)
            continue
        end

        local animation = Instance.new("Animation")
        animation.Name = name
        animation.AnimationId = row.assetId

        local ok, track = pcall(function()
            return self._animator:LoadAnimation(animation)
        end)

        if ok and track then
            -- Set here as a backstop. The authored value inside the asset is
            -- the source of truth and normally wins on its own; this covers a
            -- clip someone forgot to set in the editor, which otherwise looks
            -- exactly like a failed load.
            if row.priority then
                track.Priority = row.priority
            end

            self._animations[name] = animation
            self._tracks[name] = track
        else
            animation:Destroy()
            warn(string.format(
                "[Rig] LoadAnimation failed for '%s' (%s): %s",
                name, row.assetId, tostring(track)))
        end
    end

    -- NOT UPLOADED IS NOT AN ERROR, and saying so once beats saying nothing.
    -- Silence here would leave "my swing does nothing" with no visible cause,
    -- and a warn per row would train everyone to ignore the channel while the
    -- game is still being built.
    if #pendingUpload > 0 then
        table.sort(pendingUpload)
        print(string.format(
            "[Rig] %d animation(s) not uploaded yet, skipped: %s",
            #pendingUpload, table.concat(pendingUpload, ", ")))
    end

    -- OFF THE MAIN FLOW. Verification waits on the CDN, and nothing should
    -- stall a respawn to find out whether an asset resolved. The tracks are
    -- already usable; this only decides what gets printed.
    task.spawn(function()
        self:_verify(generation)
    end)
end

function Rig:_clearTracks()
    for _, track in pairs(self._tracks) do
        -- Stop before discarding. A track dropped mid-play on a body that
        -- still exists keeps animating with nothing holding a handle to stop
        -- it -- a limb stuck mid-swing and no way to reach it.
        if track.IsPlaying then
            track:Stop(0)
        end
        track:Destroy()
    end
    table.clear(self._tracks)

    for _, animation in pairs(self._animations) do
        animation:Destroy()
    end
    table.clear(self._animations)
end

-- ============================================================================
-- VERIFICATION -- the only symptom the ownership trap produces
-- ============================================================================
--
-- `AnimationTrack.Length` reads 0 until the asset has fully loaded, and stays 0
-- forever if it never does. That makes it both the duration source AND the "did
-- this resolve" test (Animation.md 7.4).
--
-- WHAT IT CATCHES, and this is the expensive one: an animation uploaded under
-- the WRONG OWNER loads with a permission error and produces exactly this --
-- a track that exists, plays without erroring, and animates nothing. Every
-- upload must be under the group that owns the experience (AssetPipeline Part
-- 9); a personal-account asset does not transfer, it gets re-uploaded.
--
-- Aggregated into ONE message rather than a warn per row, because the
-- realistic failure is "the owner is wrong" and that fails every row at once.
-- Twelve identical warnings communicate no more than one and bury everything
-- else in the output.
function Rig:_verify(generation: number)
    local deadline = os.clock() + RESOLVE_TIMEOUT

    -- Best effort, and explicitly not relied upon. PreloadAsync takes
    -- INSTANCES, not id strings, which is why the Animation objects are kept.
    -- It reduces first-play stutter and is documented as not fully eliminating
    -- it, so the poll below is what actually answers the question.
    local instances = {}
    for _, animation in pairs(self._animations) do
        table.insert(instances, animation)
    end

    if #instances > 0 then
        pcall(function()
            ContentProvider:PreloadAsync(instances)
        end)
    end

    while os.clock() < deadline do
        -- The body changed underneath us. Reporting now would name tracks that
        -- no longer exist, on a rig nobody is using.
        if self._destroyed or generation ~= self._generation then
            return
        end

        local unresolved = {}
        for name, track in pairs(self._tracks) do
            if track.Length <= 0 then
                table.insert(unresolved, name)
            end
        end

        if #unresolved == 0 then
            return
        end

        task.wait(RESOLVE_POLL)
    end

    if self._destroyed or generation ~= self._generation then
        return
    end

    local unresolved = {}
    for name, track in pairs(self._tracks) do
        if track.Length <= 0 then
            table.insert(unresolved, string.format(
                "%s (%s)", name, AnimationManifest.get(name).assetId))
        end
    end

    if #unresolved > 0 then
        table.sort(unresolved)
        warn(string.format(
            "[Rig] %d animation(s) still report Length 0 after %ds -- they will "
                .. "play without erroring and animate NOTHING.\n"
                .. "    Most likely: the asset is not owned by the group that "
                .. "owns this experience. Re-upload under the group.\n"
                .. "    Unresolved: %s",
            #unresolved, RESOLVE_TIMEOUT, table.concat(unresolved, ", ")))
    end
end

return Rig
