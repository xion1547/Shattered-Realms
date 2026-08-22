-- src/serverShared/components/SpatialComponent.luau
--
-- Where an entity is, and where it recently was. See HitDetection.md.
--
-- THE FIRST COMPONENT THAT REFERENCES A ROBLOX INSTANCE, which is a
-- departure worth naming rather than slipping in. Part 3 requires a
-- Component's truth be "checkable by looking at itself alone", and this one
-- satisfies that: it can answer "am I anchored, and where" without
-- consulting any Service, any registry, or any other entity.
--
-- The component owns local truth: the anchor, the tracked parts, and the ring
-- buffer of past poses. WHEN to sample and HOW FAR to rewind are game rules
-- and belong to SpatialService -- exactly the split StateFlags and
-- StateService already have.
--
-- ============================================================================
-- IT TRACKS SEVERAL PARTS, NOT ONE, AND WHY THAT DID NOT BECOME A NEW COMPONENT
-- ============================================================================
--
-- A body used to be one position. With a hitzone list it is several: a wing
-- and a torso are in different places at different moments, so "where was this
-- entity at time t" has one answer per tracked part.
--
-- The alternative considered was a child component owning per-limb history,
-- keeping this file's "whole entity" identity clean. Rejected on the
-- PetRoster -> Equipment precedent in Architecture Part 7: COMPARE THE
-- BOOKKEEPING. Per-limb history needs a preallocated ring that never grows,
-- ordered samples, interpolated lookup by timestamp, and clearing on rebind --
-- which is this component exactly, with an explicit key instead of an implicit
-- one. A child would have to duplicate every one of those invariants.
--
-- It also gets the lifecycle for free rather than by wiring: one clearHistory
-- clears every ring, one setAnchor rebuilds them all, and there is no teardown
-- to keep in sync because there is one owner.
--
-- WHAT THIS FILE IS *NOT*: HurtboxComponent holds SHAPE -- a capsule of radius
-- r offset from a named limb, true regardless of where the body is or when.
-- This holds POSITION OVER TIME. The test that separates them: does it change
-- while the game runs? Shape does not. Position does.
--
-- ============================================================================
-- ONE TIMELINE, MANY POSE ARRAYS
-- ============================================================================
--
-- Every tracked part is sampled on the SAME tick at the SAME instant, so they
-- share one `times` array and one `cursor`. Per-part copies would be eleven
-- sets of identical numbers, plus eleven counters that must never diverge --
-- a class of bug that cannot exist when there is one.
--
-- THE BUFFER IS PREALLOCATED AND NEVER GROWS. Not premature optimisation:
-- this is written by a 30Hz tick for every entity in the world, forever, and a
-- buffer that reallocated would be the one piece of the combat path producing
-- garbage on a fixed schedule.

local SpatialComponent = {}
SpatialComponent.__index = SpatialComponent

-- Two parallel arrays rather than an array of { t = , cf = } tables: the point
-- of preallocating is to never allocate again, and a table per sample would
-- defeat it.
export type SpatialTrack = {
    -- Shared by every tracked part. Index i holds the moment slot i was
    -- written, whichever part you are reading.
    times: { number },

    -- Counts samples EVER written, not slots used, and is NEVER reset while
    -- samples are live. The ring index is derived from it -- see `_index`.
    cursor: number,

    -- THE ANCHOR'S POSES, and it is a plain field rather than an entry in the
    -- map below for two reasons.
    --
    -- The anchor is genuinely privileged: it is the body's canonical position,
    -- and it is what the broadphase culls against, what an attack's origin is
    -- built from, and what `getCFrame` returns. Every other tracked part is a
    -- limb hanging off it.
    --
    -- And it has to exist BEFORE there is an anchor to key it by. An entity is
    -- constructed on join and its body arrives later, so a map keyed by
    -- BasePart has nowhere to put the first sample -- `baseParts[nil]` is not
    -- a thing. Tests rely on this too: they record into a bare component with
    -- no Instance anywhere.
    poses: { CFrame },

    -- One pose array per additional tracked part. Same length, same slots,
    -- same timeline as `times` above.
    baseParts: {
        [BasePart]: {
            poses: { CFrame },
        },
    },
}

-- THE DEFAULT IS A SECOND COPY OF SpatialService's HISTORY_LENGTH, which is
-- a duplicated constant on purpose rather than by accident: this component is
-- serverShared and the service is place-specific, so it cannot require the
-- number from the one place that chooses it. Two guards cover the drift --
-- SpatialService:attach asserts at runtime, and SpatialTests asserts at test
-- time -- so a mismatch fails loudly instead of silently shortening rewind.
-- If it ever needs to be one number, the fix is entity construction passing
-- SpatialService:constants().historyLength in, not this file reaching upward.
function SpatialComponent.new(historyLength: number?)
    local length = historyLength or 47
    assert(length > 1, "[SpatialComponent] history needs at least two slots to interpolate")

    local tracks: SpatialTrack = {
        times = table.create(length, 0),
        cursor = 0,
        poses = table.create(length),
        baseParts = {},
    }

    return setmetatable({
        anchor = nil,
        radius = 0,

        -- HALF THE LENGTH OF THE CAPSULE'S STRAIGHT SECTION, along the
        -- anchor's LOCAL Y. Zero means the capsule degenerates to a sphere.
        --
        -- THE OLD SINGLE-CAPSULE HURTBOX, AND IT IS ON ITS WAY OUT. Resolution
        -- still tests it while HurtboxComponent's zone list is drawn but not
        -- yet tested against; `NextSteps.md` item 3 deletes this, `radius`,
        -- and `endpoints` together. Two shapes describing one body is a
        -- labelled transitional state, not a design.
        halfHeight = 0,

        _tracks = tracks,
        _length = length,
    }, SpatialComponent)
end

-- Which physical slot holds logical sample k. The ring wraps; the logical
-- sequence does not, which is the whole reason `cursor` counts forever.
function SpatialComponent:_index(k: number): number
    return ((k - 1) % self._length) + 1
end

-- Allocates a pose array for `part` if it does not already have one.
-- Idempotent, so tracking the same part twice is harmless rather than a second
-- source of truth for the same fact.
--
-- The anchor is skipped: its poses live directly on the track record and
-- already exist. Registering it here would give the body two pose arrays that
-- must never disagree.
function SpatialComponent:_ensureTrack(part: BasePart)
    if part == self.anchor then
        return
    end
    if not self._tracks.baseParts[part] then
        self._tracks.baseParts[part] = {
            poses = table.create(self._length),
        }
    end
end

-- The pose array for `part`, or nil if nothing is tracking it.
--
-- Nil and the anchor both resolve to the body's own array, so a caller that
-- only cares where the BODY was never has to know the map exists. Both shapes
-- expose `.poses`, which is what lets everything downstream stay branch-free.
function SpatialComponent:_trackFor(part: BasePart?)
    if part == nil or part == self.anchor then
        return self._tracks
    end
    return self._tracks.baseParts[part]
end

-- Advances the shared cursor and returns the slot to write. Returns nil when
-- the timestamp does not advance.
--
-- ONE CURSOR FOR EVERY PART, because every part is sampled on the same tick at
-- the same instant. Per-part counters would be a set of numbers that must
-- never diverge, which is a class of bug that cannot exist when there is one.
--
-- Non-advancing timestamps are ignored rather than asserted: this runs inside
-- a pcall'd Scheduler tick, so an assert would warn once per frame forever
-- instead of failing usefully. The binary search in `poseAt` depends on
-- ordering, so the guard is not optional.
function SpatialComponent:_advance(t: number): number?
    local tracks = self._tracks

    if tracks.cursor > 0 then
        local newest = tracks.times[self:_index(tracks.cursor)]
        if t <= newest then
            return nil
        end
    end

    tracks.cursor += 1
    local i = self:_index(tracks.cursor)
    tracks.times[i] = t
    return i
end

-- Called by SpatialService when an entity enters the world. The anchor is
-- set here rather than in the constructor because an entity exists before
-- its body does -- a player's PlayerEntity is built on join, and their
-- character spawns some time afterwards.
--
-- THE ANCHOR IS TRACKED BY THIS CALL. A body that never calls `trackParts` --
-- every dummy, and anything without a hitzone list -- therefore behaves
-- exactly as it did before this component tracked more than one part: one
-- ring, one pose array, `poseAt(t)` with no second argument.
function SpatialComponent:setAnchor(anchor: BasePart, radius: number, halfHeight: number?)
    assert(typeof(anchor) == "Instance" and anchor:IsA("BasePart"),
        "[SpatialComponent] anchor must be a BasePart")
    assert(type(radius) == "number" and radius > 0,
        "[SpatialComponent] hurtbox radius must be positive")

    local half = halfHeight or 0
    assert(type(half) == "number" and half >= 0,
        "[SpatialComponent] halfHeight must be zero or positive")

    self.anchor = anchor
    self.radius = radius
    self.halfHeight = half

    -- Clear BEFORE assigning: clearHistory drops every extra track, and the
    -- anchor's own array is emptied with it.
    self:clearHistory()
end

-- Registers additional parts to sample -- the distinct limbs a hitzone list
-- hangs off. The anchor is already tracked by setAnchor and does not need
-- repeating.
--
-- DISTINCT PARTS, NOT ZONES. Ten zones might ride ten limbs, or two capsules
-- might share one tail segment. `_ensureTrack` deduplicates, so a caller can
-- pass a zone list's anchors straight through without pre-filtering.
--
-- CALL IT AFTER setAnchor, ON EVERY ATTACH INCLUDING RESPAWN. A respawned
-- character is an entirely new set of Instances; tracks keyed on the previous
-- body's parts would never update again and would keep destroyed Instances
-- alive. setAnchor's clearHistory is what drops them, which is why the order
-- matters.
function SpatialComponent:trackParts(parts: { BasePart })
    assert(type(parts) == "table", "[SpatialComponent] trackParts wants an array of BaseParts")

    for index, part in ipairs(parts) do
        assert(typeof(part) == "Instance" and part:IsA("BasePart"), string.format(
            "[SpatialComponent] trackParts[%d] is not a BasePart", index))
        self:_ensureTrack(part)
    end
end

-- How many parts are being sampled. Diagnostics, and the boot check that a
-- body with a zone list actually got its limbs registered -- a hurtbox whose
-- anchors were never tracked resolves to nothing and looks like bad geometry.
function SpatialComponent:trackedCount(): number
    local count = 0
    for _ in self._tracks.baseParts do
        count += 1
    end
    return count
end

-- The capsule's two segment endpoints in WORLD space, given a pose.
--
-- THE OLD SINGLE-CAPSULE PATH. Dies with `radius`/`halfHeight` when resolution
-- moves to the zone list -- HurtboxComponent:endpoints is its replacement and
-- takes a zone index.
--
-- Returns the same point twice when `halfHeight` is zero -- a zero-length
-- segment, which every Overlap function treats as a sphere. Callers never
-- branch on shape.
--
-- ALONG LOCAL Y, so the capsule leans when the body leans. `cf * offset`
-- transforms a local offset into world space, which is what carries the
-- anchor's rotation into the result -- using `cf.Position + offset` instead
-- would produce a capsule that stays stubbornly world-upright while the body
-- turns, and that error is invisible until something is knocked over.
function SpatialComponent:endpoints(cf: CFrame): (Vector3, Vector3)
    local half = self.halfHeight
    if half <= 0 then
        local p = cf.Position
        return p, p
    end
    local offset = Vector3.new(0, half, 0)
    return cf * offset, cf * -offset
end

-- NO CALLERS AS OF 2026-08-22, including in tests. Written ahead of the
-- hitzone list and never wired up. Flagged out loud because it was quoted in
-- conversation as though it described how hurtboxes are built today, and it
-- describes how ONE OF THREE routes would build them once something calls it.
--
-- IT IS THE DEFAULT, NOT THE POLICY. A hitzone may derive its capsule from a
-- part (this function), declare the numbers in the Content Layer, or name a
-- hurtbox part authored by hand inside the rig. All three reduce to an anchor
-- plus a radius plus a halfHeight, so nothing downstream can tell which was
-- used -- which is what makes the choice per-hitzone and reversible.
--
-- AND IT LIES ON SOME PARTS. `Size` is the AABB in the part's LOCAL axes, so a
-- diagonal limb, a curved horn, a flat plate or a part with one outlying spike
-- all derive badly. Use the overlay to check, or use one of the other routes.
--
-- Returns `radius, halfHeight, axis`. A roughly cubic part yields
-- `halfHeight == 0`, which is a sphere -- correct, and it falls out of the
-- arithmetic rather than needing a special case.
function SpatialComponent.capsuleFromSize(size: Vector3): (number, number, string)
    local axis, longest = "Y", size.Y
    if size.X > longest then
        axis, longest = "X", size.X
    end
    if size.Z > longest then
        axis, longest = "Z", size.Z
    end

    local a, b
    if axis == "X" then
        a, b = size.Y, size.Z
    elseif axis == "Y" then
        a, b = size.X, size.Z
    else
        a, b = size.X, size.Y
    end

    local radius = math.min(a, b) * 0.5
    local halfHeight = math.max(0, longest * 0.5 - radius)
    return radius, halfHeight, axis
end

function SpatialComponent:clearAnchor()
    self.anchor = nil
    self:clearHistory()
end

-- History from a previous body is not history for this one. A respawned
-- character that inherited the old buffer would be rewindable to a position it
-- never occupied, which is worse than having no history at all.
--
-- DROPS THE TRACK MAP ENTIRELY, not just the arrays inside it. Keyed by
-- Instance, a leftover entry keeps a destroyed part alive in memory and leaves
-- a track that will never be written again.
function SpatialComponent:clearHistory()
    self._tracks.cursor = 0
    table.clear(self._tracks.times)
    table.clear(self._tracks.poses)
    table.clear(self._tracks.baseParts)
end

function SpatialComponent:isAnchored(): boolean
    local anchor = self.anchor
    return anchor ~= nil and anchor:IsDescendantOf(workspace)
end

-- Live position, straight off the instance. Correct for anything happening
-- NOW; wrong for anything a client saw, which is what poseAt is for.
function SpatialComponent:getCFrame(): CFrame?
    if not self:isAnchored() then
        return nil
    end
    return self.anchor.CFrame
end

function SpatialComponent:sampleCount(): number
    return math.min(self._tracks.cursor, self._length)
end

-- How many samples this buffer can hold. SpatialService checks it at attach
-- against its own rewind ceiling -- the two constants are chosen in different
-- files and a mismatch is silent, so it is verified rather than assumed.
function SpatialComponent:historyLength(): number
    return self._length
end

-- Appends one sample for ONE part, from a pose the caller supplies. Defaults
-- to the anchor.
--
-- THE INJECTABLE PRIMITIVE, and it is what keeps this component testable. A
-- test can record a hand-written arc into a bare component with no Instance
-- anywhere in it -- which is how every ring-buffer case (wrap, interpolation,
-- clamping, out-of-order rejection) is covered without a running world.
-- `recordAll` is the production path and calls the same machinery.
function SpatialComponent:record(t: number, cf: CFrame, part: BasePart?)
    local track = self:_trackFor(part)
    if not track then
        return
    end

    local i = self:_advance(t)
    if not i then
        return
    end

    track.poses[i] = cf
end

-- Appends one sample for EVERY tracked part, at one timestamp, read live off
-- the Instances. The production path -- SpatialService's 30Hz row calls this
-- and nothing else.
--
-- The component reads the parts itself rather than being handed poses, because
-- with N parts the caller would otherwise need the track list too. Not a new
-- liberty: `getCFrame` and `isAnchored` already read the anchor.
--
-- A DESTROYED PART IS SKIPPED, NOT READ. A respawn can take the character
-- between two Heartbeats, and reading `.CFrame` off a destroyed Instance
-- throws inside the tick. Its slot keeps whatever it held, which `poseAt`
-- will happily return -- acceptable because the next `setAnchor` drops every
-- track, and the alternative is a tick that dies mid-loop and stops sampling
-- every entity queued behind this one.
function SpatialComponent:recordAll(t: number)
    local tracks = self._tracks

    local i = self:_advance(t)
    if not i then
        return
    end

    local anchor = self.anchor
    if anchor and anchor.Parent ~= nil then
        tracks.poses[i] = anchor.CFrame
    end

    for part, track in tracks.baseParts do
        if part.Parent ~= nil then
            track.poses[i] = part.CFrame
        end
    end
end

-- Where `part` was at server time `t`, interpolated between the two samples
-- bracketing it. Defaults to the anchor, so a caller that only cares where the
-- BODY was passes one argument and reads exactly as it did before this
-- component tracked limbs.
--
-- `part` IS SECOND AND OPTIONAL, deliberately: every pre-existing caller keeps
-- working unchanged, and there is one function rather than a root-specific one
-- plus a general one.
--
-- Clamps rather than returning nil at both ends, and the two ends mean
-- different things. Past the newest: the caller asked about the future, and the
-- newest sample is the best answer available. Past the oldest: the caller asked
-- further back than the buffer reaches, which SpatialService's MAX_REWIND is
-- supposed to prevent -- the clamp is a floor under a bug, not a normal path.
function SpatialComponent:poseAt(t: number, part: BasePart?): CFrame?
    local tracks = self._tracks
    local track = self:_trackFor(part)
    if not track then
        return nil
    end

    local count = self:sampleCount()
    if count == 0 then
        return nil
    end

    local poses = track.poses
    local times = tracks.times

    local oldestK = tracks.cursor - count + 1
    local newestK = tracks.cursor

    local newestIdx = self:_index(newestK)
    if t >= times[newestIdx] then
        return poses[newestIdx]
    end

    local oldestIdx = self:_index(oldestK)
    if t <= times[oldestIdx] then
        return poses[oldestIdx]
    end

    -- Largest k whose timestamp is at or before t. Searching the LOGICAL
    -- sequence, not the physical array -- the ring wraps, the sequence does
    -- not, which is the whole reason cursor counts forever.
    local lo, hi = oldestK, newestK
    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        if times[self:_index(mid)] <= t then
            lo = mid
        else
            hi = mid - 1
        end
    end

    local aIdx, bIdx = self:_index(lo), self:_index(lo + 1)
    local a, b = poses[aIdx], poses[bIdx]

    -- A part registered mid-session, or skipped while destroyed, can have a
    -- gap where the shared timeline has a stamp. Fall back rather than
    -- erroring on a nil CFrame.
    if not a then
        return b
    end
    if not b then
        return a
    end

    local ta, tb = times[aIdx], times[bIdx]
    local span = tb - ta
    if span <= 0 then
        return a
    end

    return a:Lerp(b, (t - ta) / span)
end

-- Diagnostics only. Returns the age in seconds of the oldest and newest
-- samples relative to `now`, so a caller can confirm the buffer actually spans
-- the rewind window it is being asked about.
--
-- One timeline for every part, so this needs no part argument.
function SpatialComponent:span(now: number): (number, number)
    local count = self:sampleCount()
    if count == 0 then
        return 0, 0
    end
    local times = self._tracks.times
    local oldest = times[self:_index(self._tracks.cursor - count + 1)]
    local newest = times[self:_index(self._tracks.cursor)]
    return now - oldest, now - newest
end

return SpatialComponent
