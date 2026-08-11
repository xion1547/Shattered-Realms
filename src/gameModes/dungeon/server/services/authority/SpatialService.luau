-- src/gameModes/dungeon/server/services/authority/SpatialService.luau
--
-- AUTHORITY SERVICE. Where everything is, where it was, and how far back to
-- look. See HitDetection.md.
--
-- It stores no positions: those live on each entity's Spatial component.
-- What it owns is the three rules -- when to sample, how far to rewind, and
-- who is attached -- and being the ONE DOOR to all three.
--
-- The single-door argument is StateService's, applied to a different
-- failure: if every damage source read entity.spatial directly, the first
-- source that forgot to rewind would make lag compensation mean "compensated
-- for whatever remembered to compensate". A player would land hits with one
-- skill and miss identically-aimed hits with another, and nothing would look
-- broken from the inside of either.
--
-- ATTACHMENT IS EXPLICIT, AND THAT BUYS SOMETHING. There is no entity
-- registry anywhere in this codebase -- ServerManager holds players and
-- nothing holds enemies. Because attaching is a deliberate call, the set of
-- attached entities IS the candidate set for hit detection: anything that
-- can be hit is by definition something that registered a hurtbox, and
-- nothing else can ever be returned by a query.

local SpatialService = {}

-- Sampling rate. Roblox replicates character position at roughly 20Hz, so a
-- 60Hz sampler writes each replicated position into three consecutive slots
-- and learns nothing from two of them. 30Hz already oversamples the source.
local SAMPLE_HZ = 30

-- Past this, a player is being hit by something that left their screen half
-- a second ago. It is also the exploit ceiling: it bounds what a
-- manipulated latency figure could ever buy.
local MAX_REWIND = 0.5

-- Roblox characters replicate at ~20Hz and clients interpolate on top of
-- that, so what a client renders is behind what it has received. Both
-- open-source Roblox rewind implementations converged on this figure
-- independently.
local INTERPOLATION_CONSTANT = 0.1

-- Two slots of margin past the rewind ceiling, so the oldest sample is
-- always strictly older than MAX_REWIND and poseAt never has to clamp on a
-- legitimate query.
local HISTORY_LENGTH = math.ceil(MAX_REWIND * SAMPLE_HZ) + 2

-- MEASURED. Player:GetNetworkPing() returns SECONDS, not milliseconds.
--
-- Widely described as milliseconds, including in the API's own release
-- notes, and it is not. A Team Test session read 0.0122-0.0150 against an
-- independently measured round trip floor of ~38ms. As milliseconds that
-- would be twelve MICROSECONDS, which is below the processing cost of the
-- call itself; as seconds it is 12-15ms, which is an ordinary ping.
--
-- THE 1000x ERROR THIS REPLACES WAS COMPLETELY SILENT. Reading the value as
-- milliseconds made the latency term 24 microseconds, so rewindWindowFor
-- returned exactly INTERPOLATION_CONSTANT and lag compensation quietly did
-- nothing at all. Nothing errored, no test failed -- the only reason it was
-- caught is that PingProbe printed the window and 0.100s was suspiciously
-- round.
--
-- STILL OPEN, and now known to be low-stakes: whether the figure is a full
-- round trip or one way. The probe cannot separate them, because its own
-- client-turnaround overhead (~14-26ms, and variable) is larger than the
-- 12-15ms signal being measured. This stays at 2 -- the over-rewinding
-- reading -- and the cost of being wrong is ~12ms of extra rewind at these
-- latencies, which is inside the noise. It only starts to matter above
-- ~200ms ping, where MAX_REWIND is the binding constraint anyway.
local PING_TO_ROUND_TRIP = 2

SpatialService._attached = {}      -- entity -> true
SpatialService._attachedCount = 0

function SpatialService:boot()
    -- Nothing to declare. Position is not a Fact anything subscribes to;
    -- it is queried, never announced.
end

-- REGISTRATION ----------------------------------------------------------

-- Keyed by the entity table itself rather than by an id. Every caller
-- already holds the entity -- that is how it got here -- and keying by id
-- would mean this service had to care whether ids are strings ("ENEMY_1")
-- or numbers (UserId), which is a distinction it has no reason to know.
function SpatialService:attach(entity, anchor: BasePart, radius: number)
    assert(type(entity) == "table" and entity.spatial,
        "[SpatialService] entity has no Spatial component")

    -- The buffer length is chosen by whoever built the component, but the
    -- rewind ceiling is chosen here. Checked at attach rather than trusted,
    -- because the failure is silent: a buffer too short to span MAX_REWIND
    -- makes poseAt clamp to its oldest sample, which returns a real
    -- position from the wrong moment. Nothing errors and hits land slightly
    -- wrong forever.
    local available = entity.spatial:historyLength()
    assert(available >= HISTORY_LENGTH, string.format(
        "[SpatialService] Spatial buffer holds %d samples; %d needed to span %.2fs at %dHz",
        available, HISTORY_LENGTH, MAX_REWIND, SAMPLE_HZ))

    entity.spatial:setAnchor(anchor, radius)

    if not self._attached[entity] then
        self._attached[entity] = true
        self._attachedCount += 1
    end
end

function SpatialService:detach(entity)
    if not self._attached[entity] then
        return
    end

    self._attached[entity] = nil
    self._attachedCount -= 1

    if entity.spatial then
        entity.spatial:clearAnchor()
    end
end

function SpatialService:isAttached(entity): boolean
    return self._attached[entity] == true
end

function SpatialService:attachedCount(): number
    return self._attachedCount
end

-- SAMPLING --------------------------------------------------------------

-- Scheduled at SAMPLE_HZ. See HitDetection.md for why the Scheduler's
-- existing drain-first ordering does not need to change: the rewind target
-- is always at least INTERPOLATION_CONSTANT into the past, so the newest
-- samples are never the ones a compensated query reads.
function SpatialService:tick(_dt: number)
    if self._attachedCount == 0 then
        return
    end

    local now = workspace:GetServerTimeNow()
    local lost = nil

    for entity in pairs(self._attached) do
        local spatial = entity.spatial
        if spatial and spatial:isAnchored() then
            spatial:record(now, spatial.anchor.CFrame)
        else
            -- The body left the world -- a character respawning, an enemy
            -- despawning, a player disconnecting. Self-healing on purpose:
            -- without it, every departure that forgot to call detach would
            -- leak an entry, and a long-running server would iterate a
            -- growing list of corpses on every tick.
            lost = lost or {}
            table.insert(lost, entity)
        end
    end

    if lost then
        for _, entity in ipairs(lost) do
            self:detach(entity)
        end
    end
end

-- QUERIES ---------------------------------------------------------------

-- Round-trip latency in SECONDS, server-measured. Never a client-supplied
-- figure -- a client that could report its own latency would have an
-- obvious incentive to widen its own rewind window (Part 13).
function SpatialService:roundTripOf(player: Player): number
    local ok, raw = pcall(player.GetNetworkPing, player)
    if not ok or type(raw) ~= "number" or raw ~= raw or raw < 0 then
        return 0
    end
    return raw * PING_TO_ROUND_TRIP
end

-- How far back this player's view of the world is, in seconds.
--
--   server sends snapshot at            T
--   client receives it at               T + L
--   client is rendering state from      T - I     (it interpolates)
--   client presses attack at            T + L
--   the command reaches the server at   T + 2L
--
--   rewind = (T + 2L) - (T - I) = 2L + I  -- a FULL round trip, plus
--   interpolation. Not half a ping.
function SpatialService:rewindWindowFor(player: Player): number
    local window = self:roundTripOf(player) + INTERPOLATION_CONSTANT
    return math.clamp(window, 0, MAX_REWIND)
end

-- The server timestamp a player's attack should be resolved against.
function SpatialService:viewTimeFor(player: Player): number
    return workspace:GetServerTimeNow() - self:rewindWindowFor(player)
end

-- Where this entity was at server time `t`. nil means never sampled --
-- attached this frame, or not attached at all.
function SpatialService:poseAt(entity, t: number): CFrame?
    local spatial = entity.spatial
    if not spatial then
        return nil
    end
    return spatial:poseAt(t)
end

-- BROADPHASE ------------------------------------------------------------
--
-- A linear scan over attached entities, culling by squared distance so
-- nothing takes a square root it does not need.
--
-- NO SPATIAL PARTITIONING, deliberately. At the scale the design implies --
-- on the order of a hundred mobs in a farm zone -- a hundred squared-distance
-- comparisons is microseconds, and a spatial hash would be machinery bought
-- before it is needed. The trigger for revisiting is recorded in
-- HitDetection.md with a number attached: broadphase appearing in a profile
-- at all, or attached-entity count passing ~500.
--
-- `margin` is the caller's job and must account for how far anything could
-- have travelled during the rewind window -- otherwise this discards an
-- entity that has since run out of range but WAS inside the volume at the
-- moment being resolved.
function SpatialService:candidatesNear(position: Vector3, radius: number, margin: number?)
    local reach = radius + (margin or 0)
    local out = {}

    for entity in pairs(self._attached) do
        local spatial = entity.spatial
        local cf = spatial and spatial:getCFrame()
        if cf then
            local limit = reach + spatial.radius
            local offset = cf.Position - position
            -- Squared throughout: comparing against limit^2 is the same
            -- test without the square root, and this runs once per attached
            -- entity per query.
            if offset:Dot(offset) <= limit * limit then
                table.insert(out, entity)
            end
        end
    end

    return out
end

-- Exposed for the Scheduler row and for tests that need to reason about the
-- buffer without duplicating the arithmetic.
function SpatialService:constants()
    return {
        sampleHz = SAMPLE_HZ,
        maxRewind = MAX_REWIND,
        interpolationConstant = INTERPOLATION_CONSTANT,
        historyLength = HISTORY_LENGTH,
        pingToRoundTrip = PING_TO_ROUND_TRIP,
    }
end

return SpatialService
