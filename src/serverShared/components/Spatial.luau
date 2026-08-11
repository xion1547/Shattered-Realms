-- src/serverShared/components/Spatial.luau
--
-- Where an entity is, and where it recently was. See HitDetection.md.
--
-- THE FIRST COMPONENT THAT REFERENCES A ROBLOX INSTANCE, which is a
-- departure worth naming rather than slipping in. Part 3 requires a
-- Component's truth be "checkable by looking at itself alone", and this one
-- satisfies that: it can answer "am I anchored, and where" without
-- consulting any Service, any registry, or any other entity.
--
-- The component owns local truth: the anchor, the hurtbox radius, and its
-- own ring buffer of past poses. WHEN to sample and HOW FAR to rewind are
-- game rules and belong to SpatialService -- exactly the split StateFlags
-- and StateService already have.
--
-- THE BUFFER IS PREALLOCATED AND NEVER GROWS. Nothing in this layer
-- allocates per sample, per query or per hit. That is not premature
-- optimisation: this is written by a 30Hz tick for every entity in the
-- world, forever, and a buffer that reallocated would be the one piece of
-- the combat path that produced garbage on a fixed schedule.

local Spatial = {}
Spatial.__index = Spatial

-- Two parallel arrays rather than an array of { t = , cf = } tables: the
-- point of preallocating is to never allocate again, and a table per sample
-- would defeat it.
function Spatial.new(historyLength: number?)
    local length = historyLength or 17
    assert(length > 1, "[Spatial] history needs at least two slots to interpolate")

    return setmetatable({
        anchor = nil,
        radius = 0,

        _times = table.create(length, 0),
        _poses = table.create(length),
        _length = length,
        -- Counts samples EVER written, not slots used. The ring index is
        -- derived from it, so it must never be reset while samples are live.
        _cursor = 0,
    }, Spatial)
end

-- Which physical slot holds logical sample k.
function Spatial:_index(k: number): number
    return ((k - 1) % self._length) + 1
end

-- Called by SpatialService when an entity enters the world. The anchor is
-- set here rather than in the constructor because an entity exists before
-- its body does -- a player's PlayerEntity is built on join, and their
-- character spawns some time afterwards.
function Spatial:setAnchor(anchor: BasePart, radius: number)
    assert(typeof(anchor) == "Instance" and anchor:IsA("BasePart"),
        "[Spatial] anchor must be a BasePart")
    assert(type(radius) == "number" and radius > 0,
        "[Spatial] hurtbox radius must be positive")

    self.anchor = anchor
    self.radius = radius
    self:clearHistory()
end

function Spatial:clearAnchor()
    self.anchor = nil
    self:clearHistory()
end

-- History from a previous body is not history for this one. A respawned
-- character that inherited the old buffer would be rewindable to a position
-- it never occupied, which is worse than having no history at all.
function Spatial:clearHistory()
    self._cursor = 0
    table.clear(self._times)
    table.clear(self._poses)
end

function Spatial:isAnchored(): boolean
    local anchor = self.anchor
    return anchor ~= nil and anchor:IsDescendantOf(workspace)
end

-- Live position, straight off the instance. Correct for anything happening
-- NOW; wrong for anything a client saw, which is what poseAt is for.
function Spatial:getCFrame(): CFrame?
    if not self:isAnchored() then
        return nil
    end
    return self.anchor.CFrame
end

function Spatial:sampleCount(): number
    return math.min(self._cursor, self._length)
end

-- How many samples this buffer can hold. SpatialService checks it at attach
-- against its own rewind ceiling -- the two constants are chosen in
-- different files and a mismatch is silent, so it is verified rather than
-- assumed.
function Spatial:historyLength(): number
    return self._length
end

-- Appends one sample. Non-advancing timestamps are ignored rather than
-- asserted: this runs inside a pcall'd Scheduler tick, so an assert here
-- would warn once per frame forever instead of failing usefully. The
-- binary search in poseAt depends on ordering, so the guard is not optional.
function Spatial:record(t: number, cf: CFrame)
    if self._cursor > 0 then
        local newest = self._times[self:_index(self._cursor)]
        if t <= newest then
            return
        end
    end

    self._cursor += 1
    local i = self:_index(self._cursor)
    self._times[i] = t
    self._poses[i] = cf
end

-- Where this entity was at server time `t`, interpolated between the two
-- samples bracketing it.
--
-- Clamps rather than returning nil at both ends, and the two ends mean
-- different things. Past the newest: the caller asked about the future, and
-- the newest sample is the best answer available. Past the oldest: the
-- caller asked further back than the buffer reaches, which SpatialService's
-- MAX_REWIND is supposed to prevent -- the clamp is a floor under a bug,
-- not a normal path.
function Spatial:poseAt(t: number): CFrame?
    local count = self:sampleCount()
    if count == 0 then
        return nil
    end

    local oldestK = self._cursor - count + 1
    local newestK = self._cursor

    local newestIdx = self:_index(newestK)
    if t >= self._times[newestIdx] then
        return self._poses[newestIdx]
    end

    local oldestIdx = self:_index(oldestK)
    if t <= self._times[oldestIdx] then
        return self._poses[oldestIdx]
    end

    -- Largest k whose timestamp is at or before t. Searching the LOGICAL
    -- sequence, not the physical array -- the ring wraps, the sequence does
    -- not, which is the whole reason _cursor counts forever.
    local lo, hi = oldestK, newestK
    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        if self._times[self:_index(mid)] <= t then
            lo = mid
        else
            hi = mid - 1
        end
    end

    local aIdx, bIdx = self:_index(lo), self:_index(lo + 1)
    local ta, tb = self._times[aIdx], self._times[bIdx]
    local span = tb - ta
    if span <= 0 then
        return self._poses[aIdx]
    end

    return self._poses[aIdx]:Lerp(self._poses[bIdx], (t - ta) / span)
end

-- Diagnostics only. Returns the age in seconds of the oldest and newest
-- samples relative to `now`, so a caller can confirm the buffer actually
-- spans the rewind window it is being asked about.
function Spatial:span(now: number): (number, number)
    local count = self:sampleCount()
    if count == 0 then
        return 0, 0
    end
    local oldest = self._times[self:_index(self._cursor - count + 1)]
    local newest = self._times[self:_index(self._cursor)]
    return now - oldest, now - newest
end

return Spatial
