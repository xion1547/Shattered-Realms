-- src/gameModes/dungeon/server/resolution/targeting/HitVolume.luau
--
-- The DECLARATIVE half of hit detection. See HitDetection.md.
--
-- A hit volume is a plain table on a skill definition describing a shape and
-- nothing else. Adding a new attack shape to the game is a data edit; adding
-- a new KIND of shape is one entry here plus one function in Overlap.
--
-- SERVER ONLY, and deliberately not in src/shared/. ReplicatedStorage is a
-- broadcast (Part 13) -- publishing this table would hand every client the
-- exact reach and arc of every skill in the game. The client needs none of
-- it: it plays an animation and waits for a diff.
--
-- This module holds the vocabulary, the defaults, the validator and the
-- reach calculation. It holds NO overlap math -- that is Overlap.luau, which
-- has no requires at all.

local HitVolume = {}

HitVolume.Shape = table.freeze({
    SPHERE = "SPHERE",      -- point-blank AoE, ground markers, explosions
    BOX = "BOX",            -- cleaves, walls, rectangular zones
    ARC = "ARC",            -- the standard melee swing
    CAPSULE = "CAPSULE",    -- thrusts, beams, dash attacks
})

-- Where the volume sits. A ground-targeted AoE anchors to a location; a
-- swing anchors to whoever swung it.
HitVolume.Anchor = table.freeze({
    ATTACKER = "ATTACKER",
    POINT = "POINT",
})

-- Where the volume's facing comes from.
--
-- FACING is the default and introduces NO new trust: the server uses its own
-- record of which way the attacker was pointing. It is stale by roughly one
-- round trip, which at 100ms is ~18 degrees for a player turning at 180
-- deg/s -- irrelevant inside a 90-degree cleave.
--
-- CLIENT_AIM is for narrow volumes only, where 18 degrees is the difference
-- between hitting and missing. It is the ONLY field a client contributes to
-- a volume, it is a direction and never a position or a distance, and the
-- worst a liar achieves is swinging somewhere they were not facing -- which
-- they could have done by turning.
HitVolume.AimSource = table.freeze({
    FACING = "FACING",
    CLIENT_AIM = "CLIENT_AIM",
})

local DEFAULTS = {
    anchor = HitVolume.Anchor.ATTACKER,
    aimSource = HitVolume.AimSource.FACING,
    activeWindow = 0,
    samples = 1,
    maxTargets = nil,
    requiresLineOfSight = false,
    offset = nil,

    -- DEGREES THE VOLUME TRAVELS across its active window. Zero means it does
    -- not move, which is every volume written before this field existed.
    --
    -- A blade is not everywhere in its arc at once. A one-second slice sweeps
    -- through its arc, and a target at the far end has most of that second to
    -- leave -- so treating the whole fan as live for the whole window hits
    -- people who dodged, and no amount of `samples` fixes it because every
    -- sample tests the same fan.
    --
    -- With `sweep > 0` on an ARC, `angle` stops meaning "the whole fan" and
    -- starts meaning THE BLADE'S OWN WIDTH. On a CAPSULE it is the blade
    -- itself rotating, which is the closest thing here to a real sword.
    sweep = 0,
}

-- Which numeric fields each shape requires, and the rule each must satisfy.
local REQUIRED = {
    SPHERE = { radius = "positive" },
    BOX = { size = "vector3" },
    ARC = { radius = "positive", angle = "degrees" },
    CAPSULE = { length = "positive", radius = "positive" },
}

local CHECKS = {
    positive = function(value)
        return type(value) == "number" and value == value and value > 0,
            "must be a positive number"
    end,
    degrees = function(value)
        return type(value) == "number" and value == value and value > 0 and value <= 360,
            "must be a number of degrees in (0, 360]"
    end,
    vector3 = function(value)
        if typeof(value) ~= "Vector3" then
            return false, "must be a Vector3"
        end
        return value.X > 0 and value.Y > 0 and value.Z > 0, "must have positive extents"
    end,
}

-- Fills in every default without mutating the caller's table, and freezes
-- the result. Content is read many times and written once; a volume that
-- something could edit at runtime would be a balance bug that only appears
-- after the tenth swing.
function HitVolume.resolve(volume)
    assert(type(volume) == "table", "[HitVolume] a volume must be a table")

    local out = table.clone(volume)
    for key, value in pairs(DEFAULTS) do
        if out[key] == nil then
            out[key] = value
        end
    end
    return table.freeze(out)
end

-- Returns ok, reason. Called at boot over every declared volume so a
-- malformed one fails at startup rather than the first time a player
-- presses that button.
function HitVolume.validate(volume): (boolean, string?)
    if type(volume) ~= "table" then
        return false, "must be a table"
    end
    if not HitVolume.Shape[volume.shape] then
        return false, string.format("unknown shape: %s", tostring(volume.shape))
    end
    if volume.anchor and not HitVolume.Anchor[volume.anchor] then
        return false, string.format("unknown anchor: %s", tostring(volume.anchor))
    end
    if volume.aimSource and not HitVolume.AimSource[volume.aimSource] then
        return false, string.format("unknown aimSource: %s", tostring(volume.aimSource))
    end

    for field, rule in pairs(REQUIRED[volume.shape]) do
        local ok, reason = CHECKS[rule](volume[field])
        if not ok then
            return false, string.format("'%s' %s", field, reason)
        end
    end

    if volume.samples ~= nil then
        if type(volume.samples) ~= "number" or volume.samples < 1 or volume.samples % 1 ~= 0 then
            return false, "'samples' must be a whole number of at least 1"
        end
        -- More than one sample is only meaningful across a window. Sampling
        -- an instant three times returns the same answer three times, which
        -- is not wrong, but it is always a mistake worth naming.
        if volume.samples > 1 and (volume.activeWindow or 0) <= 0 then
            return false, "'samples' above 1 needs an 'activeWindow' to spread them across"
        end
    end

    if volume.activeWindow ~= nil
        and (type(volume.activeWindow) ~= "number" or volume.activeWindow < 0) then
        return false, "'activeWindow' must be zero or a positive number of seconds"
    end

    if volume.maxTargets ~= nil
        and (type(volume.maxTargets) ~= "number" or volume.maxTargets < 1) then
        return false, "'maxTargets' must be at least 1, or nil for unlimited"
    end

    if volume.offset ~= nil and typeof(volume.offset) ~= "CFrame" then
        return false, "'offset' must be a CFrame"
    end

    if volume.sweep ~= nil then
        if type(volume.sweep) ~= "number" or volume.sweep < 0 or volume.sweep > 360 then
            return false, "'sweep' must be between 0 and 360 degrees"
        end
        -- A volume that travels needs both a duration to travel over and more
        -- than one moment to be tested at. One sample of a moving blade is a
        -- stationary blade at an arbitrary point in its swing, which is worse
        -- than not sweeping at all -- it looks like a bug rather than a
        -- design.
        if volume.sweep > 0 then
            if (volume.activeWindow or 0) <= 0 then
                return false, "'sweep' needs an 'activeWindow' to travel across"
            end

            -- `samples` IS NOT REQUIRED FOR A SWEEP and is not read for one.
            -- The wedge count is derived from the sweep's angle and duration
            -- (see HitVolume.wedgeCount), because it is a safety property
            -- rather than a design knob. Rejected rather than ignored: a
            -- number that silently does nothing is worse than one that fails
            -- at boot with a reason.
            if volume.samples ~= nil and volume.samples > 1 then
                return false,
                    "a sweeping volume derives its own resolution -- remove "
                        .. "'samples', it is not read and would mislead"
            end

            -- A sweeping volume is resolved as a series of WEDGES covering the
            -- space between sample angles, and a wedge is an arc sector. That
            -- only makes sense for a shape that pivots at its origin: a blade
            -- (CAPSULE) or a fan (ARC). A sweeping BOX has no meaningful swept
            -- sector -- it would be a curved slab, which nothing here can
            -- express and no attack has asked for.
            if volume.shape ~= HitVolume.Shape.ARC
                and volume.shape ~= HitVolume.Shape.CAPSULE then
                return false, string.format(
                    "'sweep' is only supported on ARC and CAPSULE, not %s",
                    tostring(volume.shape))
            end
        end
    end

    return true
end

-- WEDGE RESOLUTION -------------------------------------------------------
--
-- How many wedges a sweeping volume resolves as. DERIVED, not authored --
-- see HitDetection.md §8.3 for what a wedge is.
--
-- WHY THIS IS NOT A NUMBER CONTENT WRITES. Since a sweep resolves as wedges
-- that TILE the arc, coverage is complete at any count -- one wedge spanning
-- the whole sweep leaves no gap in space. What the count actually buys is
-- TIME resolution: with one wedge you test the entire arc at a single
-- instant, so someone who walked in after the blade passed their spot is hit
-- anyway. More wedges means a finer answer to *when*.
--
-- That makes it a safety property rather than a design knob, and safety
-- properties should not be re-decided per skill. A designer who has to pick
-- `samples` for every attack will eventually pick a bad one, and the failure
-- is silent -- the attack still hits things, just at the wrong moments.

-- A wedge wider than this stops being a blade and starts being a fan.
local MAX_DEGREES_PER_WEDGE = 20

-- A wedge longer than this gives a running target time to cross it, which
-- breaks the link between "in the wedge at the sample" and "in the wedge when
-- the blade passed". Roughly three frames.
local MAX_SECONDS_PER_WEDGE = 0.05

-- Sanity ceiling. Nothing sane reaches it; it exists so a typo in content
-- (`activeWindow = 60`) costs a warning rather than twelve hundred resolves.
local MAX_WEDGES = 64

function HitVolume.wedgeCount(volume): number
    if (volume.sweep or 0) <= 0 then
        return 1
    end

    -- Whichever constraint is stricter wins. Angle alone is not enough: a
    -- 360-degree spin over two seconds is SLOWER than a 90-degree flick over
    -- a tenth of a second, and the flick is the one needing fine timing.
    local byAngle = math.ceil(volume.sweep / MAX_DEGREES_PER_WEDGE)
    local byTime = math.ceil((volume.activeWindow or 0) / MAX_SECONDS_PER_WEDGE)

    return math.clamp(math.max(byAngle, byTime, 1), 1, MAX_WEDGES)
end

-- Exposed so diagnostics can report the caps alongside the count, rather than
-- printing a number nobody can check.
function HitVolume.wedgeLimits()
    return {
        maxDegrees = MAX_DEGREES_PER_WEDGE,
        maxSeconds = MAX_SECONDS_PER_WEDGE,
        maxWedges = MAX_WEDGES,
    }
end

-- The furthest this volume extends from its origin, used to size the
-- broadphase cull. MUST NOT UNDERESTIMATE: a reach that is too small
-- discards candidates before the exact test ever sees them, producing
-- misses that look like bad hit detection and are actually bad culling.
function HitVolume.reach(volume): number
    local base
    if volume.shape == HitVolume.Shape.SPHERE then
        base = volume.radius
    elseif volume.shape == HitVolume.Shape.ARC then
        base = volume.radius
    elseif volume.shape == HitVolume.Shape.CAPSULE then
        base = volume.length + volume.radius
    elseif volume.shape == HitVolume.Shape.BOX then
        -- Half the diagonal, not half the largest side: a rotated box
        -- reaches its corners, and the corner is what a cull has to clear.
        base = (volume.size * 0.5).Magnitude
    else
        error(string.format("[HitVolume] unknown shape: %s", tostring(volume.shape)), 0)
    end

    if volume.offset then
        base += volume.offset.Position.Magnitude
    end
    return base
end

return HitVolume
