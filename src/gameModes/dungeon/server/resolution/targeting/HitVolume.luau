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

    return true
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
