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
-- ATTACHMENT IS EXPLICIT, AND THAT BUYS SOMETHING. EntityService holds every
-- live entity, but being registered is not the same as being hittable: a
-- player exists from the moment they join and their character does not, and
-- it detaches and re-attaches on every respawn. Because attaching is a
-- deliberate call, the set of attached entities IS the candidate set for hit
-- detection -- anything that can be hit is by definition something that
-- registered a hurtbox, and nothing else can ever be returned by a query.

local ServerStorage = game:GetService("ServerStorage")
local HurtboxComponent = require(ServerStorage:WaitForChild("Shared")
    :WaitForChild("components"):WaitForChild("HurtboxComponent"))

local SpatialService = {}

-- Sampling rate. Roblox replicates character position at roughly 20Hz, so a
-- 60Hz sampler writes each replicated position into three consecutive slots
-- and learns nothing from two of them. 30Hz already oversamples the source.
--
-- The 20Hz figure is community-measured, not documented -- Roblox publishes
-- the physics STEP rate (60/120/240Hz, adaptive) but not the replication
-- rate, and replication is throttled. Treat it as an estimate. It is only
-- load-bearing as a floor: any real rate at or under 30Hz makes this correct.
local SAMPLE_HZ = 30

-- How far back a query is ALLOWED to reach. Past this, a player is being hit
-- by something that left their screen half a second ago. It is also the
-- exploit ceiling: it bounds what a manipulated latency figure could ever
-- buy, which matters because latency can be induced even though the figure
-- itself is server-measured.
--
-- 0.5 IS ALREADY PERMISSIVE, which is easy to misread as conservative.
-- Competitive shooters land near 0.2 (Source's sv_maxunlag is 0.2, and the
-- modern hero shooters are in the same neighbourhood). This game gets to be
-- more generous than that because the rewound thing is usually an NPC: the
-- cost of over-rewinding here is other players watching damage land on empty
-- air, not a human being robbed of a dodge. That buys room, not licence.
--
-- WHAT HAPPENS PAST THIS IS DEGRADATION, NOT FAILURE, and that is the whole
-- design. A 600ms player is compensated 0.5s of their ~0.7s deficit, so
-- their swings under-lead a moving target by whatever ground it covered in
-- the uncompensated remainder. Bounded, self-limiting, and survivable --
-- which is the point, because nobody is playing well at 600ms regardless.
-- Rewind corrects aim. Nothing here can correct the fact that a telegraph
-- reaches that player 600ms late, so there is a ceiling on how much buying
-- more of it helps.
local MAX_REWIND = 0.5

-- Roblox characters replicate at ~20Hz and clients interpolate on top of
-- that, so what a client renders is behind what it has received. Both
-- open-source Roblox rewind implementations converged on this figure
-- independently.
local INTERPOLATION_CONSTANT = 0.1

-- How far back the buffer STORES, which is deliberately further than
-- MAX_REWIND reaches. These used to be one number and they answer two
-- different questions:
--
--   MAX_REWIND       how far we reach  -> costs fairness; is the exploit ceiling
--   HISTORY_SECONDS  how much we keep  -> costs memory, and memory is free here
--
-- Free is meant literally. A sample is a float plus a CFrame, call it ~90
-- bytes; 47 samples is about 4KB per entity, so a full dungeon is a quarter
-- of a megabyte and a pathological 500-entity server is single-digit MB.
-- poseAt binary-searches, so a longer buffer costs one extra comparison.
--
-- 1.5s covers the worst reading of a 600ms player (see PING_TO_ROUND_TRIP:
-- if that constant is wrong, their window is 1.3s, not 0.7s), so MAX_REWIND
-- can be retuned to anything defensible without this number having to move.
--
-- BE HONEST ABOUT WHAT THE SPLIT BUYS, because the obvious argument for it
-- does not hold. It does NOT protect against someone raising MAX_REWIND --
-- the old coupled form derived the length from it automatically, and the
-- attach assert caught the stale component default loudly. What it actually
-- buys is headroom against the rate divergence described on
-- verifySampleRate: tolerance for the REAL tick rate went from <=34Hz to
-- <=94Hz. The boot assert below then closes a hazard the split itself
-- introduced. Net positive, but for a different reason than it looks.
local HISTORY_SECONDS = 1.5

-- Two slots of margin past the stored span, so the oldest sample is always
-- strictly older than any legitimate query and poseAt never has to clamp.
local HISTORY_LENGTH = math.ceil(HISTORY_SECONDS * SAMPLE_HZ) + 2

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
-- caught is that PingProbe (retired 2026-08-21) printed the window and 0.100s
-- was suspiciously round.
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

-- One-shot latch for the observed-rate check in tick. See verifySampleRate.
SpatialService._rateVerified = false

function SpatialService:boot()
    -- THE ONE INVARIANT THE SPLIT CREATES, and it is worth a boot gate
    -- because violating it errors nowhere. Reach past what the buffer stores
    -- and poseAt clamps to its oldest sample, returning a real position from
    -- the wrong moment -- every hit slightly wrong, forever, with nothing in
    -- a log to suggest it. Same family as the PING_TO_ROUND_TRIP unit bug
    -- above: a wrong number feeding a clamp is invisible to tests that only
    -- check the clamp held.
    assert(HISTORY_SECONDS >= MAX_REWIND, string.format(
        "[SpatialService] history stores %.2fs but rewind reaches %.2fs -- "
            .. "queries past the buffer resolve against the oldest sample instead",
        HISTORY_SECONDS, MAX_REWIND))

    -- Nothing to declare. Position is not a Fact anything subscribes to;
    -- it is queried, never announced.
end

-- REGISTRATION ----------------------------------------------------------

-- Keyed by the entity table itself rather than by an id. Every caller
-- already holds the entity -- that is how it got here -- and keying by id
-- would mean this service had to care whether ids are strings ("ENEMY_1")
-- or numbers (UserId), which is a distinction it has no reason to know.
-- `halfHeight` is optional and defaults to a sphere, so every pre-capsule
-- caller keeps working unchanged. See SpatialComponent:endpoints.
--
-- `zones` IS OPTIONAL AND IS THE HITZONE LIST (HitDetection Part 7). When
-- present it builds a HurtboxComponent onto the entity.
--
-- > TRANSITIONAL, AND DELIBERATELY SO. Right now TWO shapes describe the same
-- > body: `radius`/`halfHeight` on the Spatial component, which is what
-- > resolution still tests against, and `zones`, which only the overlay draws.
-- > That is two sources of truth and it is not a state to leave standing.
-- >
-- > It exists for one step, on purpose: the zone numbers are eyeballed
-- > (HurtboxDefinitions), and they get checked by LOOKING at them before
-- > anything hits with them. When TargetResolution loops zones, the single
-- > capsule and these two parameters go away together.
function SpatialService:attach(entity, anchor: BasePart, radius: number, halfHeight: number?,
    zones: { any }?)

    assert(type(entity) == "table" and entity.spatial,
        "[SpatialService] entity has no Spatial component")

    -- THE ATTACHED SET IS THE TARGET SET, so everything in it has to be a
    -- real entity. TargetResolution's callers read entity.identity on every
    -- candidate returned, so a table carrying a spatial component and nothing
    -- else is a target that damage cannot be attributed to -- it surfaces as
    -- a crash deep inside resolution, at the far end of the pipeline from the
    -- attach call that caused it.
    --
    -- This does NOT make the service care about ids: it still keys by the
    -- entity table and never reads the value. It requires only that the thing
    -- it is about to make hittable is something the rest of the game can name.
    -- Added for a diagnostic's stub entity; it holds for every real one too.
    assert(entity.identity, "[SpatialService] entity has no Identity component")

    -- The buffer length is chosen by whoever built the component, but how
    -- much history this service expects is chosen here. Checked at attach
    -- rather than trusted, because the failure is silent: a buffer too short
    -- makes poseAt clamp to its oldest sample, which returns a real position
    -- from the wrong moment. Nothing errors and hits land slightly wrong
    -- forever.
    local available = entity.spatial:historyLength()
    assert(available >= HISTORY_LENGTH, string.format(
        "[SpatialService] Spatial buffer holds %d samples; %d needed to span %.2fs at %dHz",
        available, HISTORY_LENGTH, HISTORY_SECONDS, SAMPLE_HZ))

    entity.spatial:setAnchor(anchor, radius, halfHeight)

    -- Rebuilt on every attach rather than only when absent, because attach is
    -- also what runs on respawn -- and a body that came back a different shape
    -- with a stale zone list is exactly the silent wrongness this layer
    -- specialises in.
    if zones then
        local hurtbox = HurtboxComponent.new(zones)

        -- Bound against the anchor's PARENT -- the character Model or the rig
        -- -- because that is where limbs are siblings of the root. Binding
        -- against the root itself would find nothing: `HumanoidRootPart` has no
        -- `LeftUpperArm` inside it.
        hurtbox:bind(anchor.Parent, anchor)
        entity.hurtbox = hurtbox

        -- Every limb the zones ride has to be SAMPLED, or resolution has no
        -- history to rewind them through. `_ensureTrack` deduplicates, so
        -- zones sharing a limb cost one track rather than several, and the
        -- anchor is skipped because it already has its own.
        --
        -- AFTER setAnchor, NOT BEFORE: setAnchor calls clearHistory, which
        -- drops every track. Registering first would throw these away
        -- immediately and leave the limbs silently unsampled.
        local limbs = {}
        for index = 1, hurtbox:zoneCount() do
            local part = hurtbox:anchorFor(index)
            if part then
                table.insert(limbs, part)
            end
        end
        entity.spatial:trackParts(limbs)
    end

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

-- Read-only iteration over the attached set.
--
-- A CALLBACK RATHER THAN A RETURNED TABLE, on purpose. Returning the set
-- would either hand out the live table -- which a caller could mutate,
-- breaking the count -- or allocate a copy on every call. This does neither,
-- and it cannot outlive the loop.
--
-- Added for HurtboxDebug, which needs to draw every attached body. That is a
-- legitimate read: `attachedCount` already exposes a weaker form of the same
-- question, and nothing here lets a caller change who is attached.
function SpatialService:forEachAttached(fn: (any) -> ())
    for entity in pairs(self._attached) do
        fn(entity)
    end
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
            spatial:recordAll(now)
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

    if not self._rateVerified then
        self:_verifyRateOnce(now)
    end
end

-- SAMPLE_HZ CONTROLS NOTHING, and that is the trap this guards.
--
-- tick() records whenever it is called, so SAMPLE_HZ does not set the rate --
-- it only sizes the buffer. The rate is the Scheduler's row, which is a
-- SECOND COPY of the number, living in a different file. Nothing makes them
-- agree.
--
-- If they diverge, neither assert in this file fires: both compare sample
-- COUNTS, and this failure is about DURATION. A buffer sampled faster than
-- assumed holds its full complement of samples while spanning less
-- wall-clock time than MAX_REWIND reaches, so poseAt clamps to its oldest
-- sample and every rewound query resolves against the wrong moment --
-- silently, forever. Same shape as the PING_TO_ROUND_TRIP unit bug above.
--
-- ONLY THE FAST DIRECTION IS DANGEROUS. Sampling slower than assumed makes
-- each sample cover more time, so the buffer spans MORE, never less; the
-- cost is coarser interpolation between samples, not a clamp. A server
-- dropping frames is therefore not the risk here. A changed Scheduler row is.
--
-- Measured against the buffer that actually exists rather than the rate it is
-- assumed to have been filled at. Returns nil for the span when there is
-- nothing to measure -- a partly filled buffer is not evidence either way.
function SpatialService:verifySampleRate(spatial, now: number): (boolean, number?)
    if spatial:sampleCount() < spatial:historyLength() then
        return true, nil
    end

    local oldest = spatial:span(now)
    return oldest >= MAX_REWIND, oldest
end

-- Latches on the first buffer with anything to say. A mismatched rate is a
-- static property of the config, so one measurement settles it and the check
-- costs nothing for the rest of the server's life.
--
-- Warns rather than asserts because this runs inside a pcall'd Scheduler
-- tick, where an assert is swallowed and retried every frame -- the same
-- reasoning SpatialComponent:record uses for ignoring stale timestamps.
function SpatialService:_verifyRateOnce(now: number)
    for entity in pairs(self._attached) do
        local spatial = entity.spatial
        if spatial then
            local ok, observed = self:verifySampleRate(spatial, now)
            if observed then
                self._rateVerified = true
                if not ok then
                    warn(string.format(
                        "[SpatialService] sampling faster than assumed: a full %d-sample "
                            .. "buffer spans %.3fs, but MAX_REWIND reaches %.2fs. SAMPLE_HZ "
                            .. "says %dHz -- check the SpatialService row in Scheduler.luau. "
                            .. "Rewound queries are clamping to the oldest sample and "
                            .. "resolving against the wrong moment.",
                        HISTORY_LENGTH, observed, MAX_REWIND, SAMPLE_HZ))
                end
                return
            end
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
            -- THE BOUNDING RADIUS OF THE CAPSULE, not just its thickness. A
            -- capsule reaches `halfHeight` further from its centre than a
            -- sphere of the same radius does, and culling on the radius alone
            -- would discard a tall target whose head or feet were inside the
            -- volume. Broadphase must never be tighter than the narrow phase.
            local limit = reach + spatial.radius + spatial.halfHeight
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
        historySeconds = HISTORY_SECONDS,
        historyLength = HISTORY_LENGTH,
        pingToRoundTrip = PING_TO_ROUND_TRIP,
    }
end

return SpatialService
