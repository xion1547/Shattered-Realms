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

local SpatialComponent = {}
SpatialComponent.__index = SpatialComponent

-- Two parallel arrays rather than an array of { t = , cf = } tables: the
-- point of preallocating is to never allocate again, and a table per sample
-- would defeat it.
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

    return setmetatable({
        anchor = nil,
        radius = 0,

        -- HALF THE LENGTH OF THE CAPSULE'S STRAIGHT SECTION, along the
        -- anchor's LOCAL Y. Zero means the capsule degenerates to a sphere,
        -- which is what every caller got before capsules existed and is still
        -- the correct shape for anything round.
        --
        -- Total height is `2 * halfHeight + 2 * radius` -- the straight part
        -- plus a hemisphere at each end.
        --
        -- ONE CAPSULE, NOT A LIST, and that is deliberate scope. HitDetection
        -- §7.7 moves the list to a HurtboxComponent, because a list of shapes
        -- is anatomy and this component's job is remembering where a body
        -- was. One capsule is the shape a single anchor can honestly carry.
        halfHeight = 0,

        _times = table.create(length, 0),
        _poses = table.create(length),
        _length = length,
        -- Counts samples EVER written, not slots used. The ring index is
        -- derived from it, so it must never be reset while samples are live.
        _cursor = 0,
    }, SpatialComponent)
end

-- Which physical slot holds logical sample k.
function SpatialComponent:_index(k: number): number
    return ((k - 1) % self._length) + 1
end

-- Called by SpatialService when an entity enters the world. The anchor is
-- set here rather than in the constructor because an entity exists before
-- its body does -- a player's PlayerEntity is built on join, and their
-- character spawns some time afterwards.
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
    self:clearHistory()
end

-- The capsule's two segment endpoints in WORLD space, given a pose.
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

-- NO CALLERS AS OF 2026-08-20, including in tests. Written ahead of the
-- hitzone list and never wired up. Flagged out loud because it was quoted in
-- conversation as though it described how hurtboxes are built today, and it
-- describes how ONE OF THREE routes would build them once something calls it.
--
-- IT IS THE DEFAULT, NOT THE POLICY. HitDetection §7.2.3: a hitzone may derive
-- its capsule from a part (this function), declare the numbers in the Content
-- Layer, or name a hurtbox part authored by hand inside the rig. All three
-- reduce to an anchor plus a radius plus a halfHeight, so nothing downstream
-- can tell which was used -- which is what makes the choice per-hitzone and
-- reversible.
--
-- AND IT LIES ON SOME PARTS. `Size` is the AABB in the part's LOCAL axes, so a
-- diagonal limb, a curved horn, a flat plate or a part with one outlying spike
-- all derive badly. §7.2.1 has the table. Use the overlay to check, or use one
-- of the other two routes.
--
-- Derive a capsule from a part's size, per HitDetection §7.2.1: the segment
-- runs along the part's LONGEST axis, and the radius is half the smaller of
-- the other two.
--
-- Returns `radius, halfHeight, axis`. A roughly cubic part yields
-- `halfHeight == 0`, which is a sphere -- correct, and it falls out of the
-- arithmetic rather than needing a special case.
--
-- ONLY THE Y CASE IS USABLE BY setAnchor TODAY, because `endpoints` builds
-- its offset along local Y. A part whose longest axis is X or Z needs either
-- a rotated anchor or a per-hitzone axis, and that arrives with
-- HurtboxComponent. The axis is returned anyway so a caller can assert on it
-- instead of silently getting a capsule pointing the wrong way.
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
-- character that inherited the old buffer would be rewindable to a position
-- it never occupied, which is worse than having no history at all.
function SpatialComponent:clearHistory()
    self._cursor = 0
    table.clear(self._times)
    table.clear(self._poses)
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
    return math.min(self._cursor, self._length)
end

-- How many samples this buffer can hold. SpatialService checks it at attach
-- against its own rewind ceiling -- the two constants are chosen in
-- different files and a mismatch is silent, so it is verified rather than
-- assumed.
function SpatialComponent:historyLength(): number
    return self._length
end

-- Appends one sample. Non-advancing timestamps are ignored rather than
-- asserted: this runs inside a pcall'd Scheduler tick, so an assert here
-- would warn once per frame forever instead of failing usefully. The
-- binary search in poseAt depends on ordering, so the guard is not optional.
function SpatialComponent:record(t: number, cf: CFrame)
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
function SpatialComponent:poseAt(t: number): CFrame?
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
function SpatialComponent:span(now: number): (number, number)
    local count = self:sampleCount()
    if count == 0 then
        return 0, 0
    end
    local oldest = self._times[self:_index(self._cursor - count + 1)]
    local newest = self._times[self:_index(self._cursor)]
    return now - oldest, now - newest
end

return SpatialComponent
