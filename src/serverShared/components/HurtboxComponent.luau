-- src/serverShared/components/HurtboxComponent.luau
--
-- WHAT SHAPE an entity can be hit in. See HitDetection.md Part 7.
--
-- THIS IS THE OTHER HALF OF SpatialComponent, and the split is worth stating
-- because the two are constantly confused:
--
--   SpatialComponent    WHERE the entity is, and where it recently was.
--                       An anchor and a ring buffer of past poses.
--   HurtboxComponent    WHAT SHAPE can be hit. A list of capsules.
--                       No position of its own. No history of its own.
--
-- A hurtbox has no idea where it is. It holds offsets, and a caller supplies
-- the pose to hang them off -- which is exactly what makes it rewindable: the
-- same zone list evaluated against a pose from 100ms ago produces the shape
-- the body had 100ms ago, for free, with nothing stored per moment.
--
-- ============================================================================
-- WHY A LIST INSTEAD OF ONE VOLUME
-- ============================================================================
--
-- One capsule around a whole body makes the space BETWEEN its limbs hittable.
-- Fire under a raised arm and it registers. That is the currently shipped
-- behaviour and it is a placeholder, not a design -- the player's single
-- capsule is already about 2.5x too wide horizontally.
--
-- Complexity is absorbed by COUNT, not by making one primitive cleverer. A
-- curved horn is three capsules. A tail is four. That is the entire idea.
--
-- ============================================================================
-- ZONES ARE OFFSETS FROM A POSE THE CALLER SUPPLIES
-- ============================================================================
--
-- `endpoints(i, pose)` takes the pose to hang zone `i` off. Today every caller
-- passes the body's ROOT pose, which is correct for players and for anything
-- that does not animate:
--
--   * a player's limbs are animated by THEIR CLIENT, so the server's copy of
--     them diverges by roughly the interpolation constant (HitDetection 9.6).
--     Anchoring to the root -- the slowest, best-replicated part of the body --
--     avoids inheriting that, and a humanoid's hittable mass barely changes as
--     its arms swing.
--   * a dummy does not move at all.
--
-- A SERVER-ANIMATED BOSS IS THE CASE THAT WILL WANT MORE, and this signature
-- already allows it. A flapping wing needs its zone hung off the WING's pose,
-- not the root's, or the hurtbox stays in the rest position while the wing
-- moves. That needs one history per anchor rather than one per body, which is
-- why it is not here yet -- see HitDetection 7.2a. Nothing in this file
-- changes when it arrives; the caller passes a different pose.
--
-- ============================================================================
-- HOW A ZONE LIST GETS AUTHORED
-- ============================================================================
--
-- You place real parts on the model in Studio and let something read them.
-- You do not compute offsets by hand. HitDetection Part 0: you author with
-- real parts, the game runs on numbers.
--
-- This file is the numbers half and deliberately knows nothing about parts,
-- models, or Studio. Something else reads a rig and calls `new` with the
-- result -- which is also what keeps the targeting tests able to construct a
-- hurtbox out of three literal capsules with no rig anywhere.

local HurtboxComponent = {}
HurtboxComponent.__index = HurtboxComponent

export type Zone = {
    -- WHERE the capsule sits, relative to whatever pose the caller supplies.
    --
    -- A CFrame, NOT a Vector3, and this is the field most likely to be got
    -- wrong. A capsule has a direction: an upper arm points sideways, a torso
    -- points up, a horn points forward. A position-only offset gives every
    -- zone the same vertical orientation and produces a body made of six
    -- upright pills.
    offset: CFrame,

    -- Thickness. Half the capsule's width.
    radius: number,

    -- HALF THE LENGTH OF THE STRAIGHT SECTION, along the zone's own local Y --
    -- the same convention SpatialComponent:endpoints uses, deliberately. Two
    -- conventions for the same idea is how this rots six months from now.
    --
    -- Zero degenerates to a sphere, which is correct for a head and falls out
    -- of the arithmetic rather than needing a special case.
    --
    -- Total length is `2 * halfHeight + 2 * radius`: the straight part plus a
    -- hemisphere at each end.
    halfHeight: number,

    -- Diagnostics only. Never read by resolution -- it exists so an overlay can
    -- label what you are looking at, and so a boot check can say WHICH zone is
    -- malformed instead of "zone 4".
    name: string?,
}

-- Builds the component from a zone list.
--
-- THE LIST IS COPIED AND FROZEN. Content is written once and read on every
-- swing forever; a zone table something could edit at runtime is a hitbox bug
-- that only appears after the tenth hit and cannot be reproduced. The same
-- reasoning as HitVolume.resolve freezing its result.
--
-- ONE ZONE IS A COMPLETELY VALID LIST, and that is how the current
-- single-capsule behaviour survives the change: it becomes a one-zone list
-- rather than a branch. Same trick as a sphere being a zero-length capsule --
-- nothing downstream learns that the old case ever existed.
function HurtboxComponent.new(zones: { Zone })
    assert(type(zones) == "table", "[HurtboxComponent] zones must be a table")
    assert(#zones > 0, "[HurtboxComponent] a hurtbox needs at least one zone")

    local copied = table.create(#zones)

    -- Computed here rather than on demand, because it is read once per attack
    -- per candidate in the broadphase and the zone list never changes. See
    -- `boundingRadius` for what it is for.
    local bounding = 0

    for index, zone in ipairs(zones) do
        local label = zone.name or tostring(index)

        assert(typeof(zone.offset) == "CFrame", string.format(
            "[HurtboxComponent] zone '%s': offset must be a CFrame, not a Vector3 "
                .. "-- a capsule has a direction", label))
        assert(type(zone.radius) == "number" and zone.radius > 0, string.format(
            "[HurtboxComponent] zone '%s': radius must be positive", label))
        assert(type(zone.halfHeight) == "number" and zone.halfHeight >= 0, string.format(
            "[HurtboxComponent] zone '%s': halfHeight must be zero or positive", label))

        copied[index] = table.freeze({
            offset = zone.offset,
            radius = zone.radius,
            halfHeight = zone.halfHeight,
            name = zone.name,
        })

        -- How far this zone's furthest point sits from the pose it hangs off:
        -- out to the zone's centre, then along its axis, then its thickness.
        local extent = zone.offset.Position.Magnitude + zone.halfHeight + zone.radius
        bounding = math.max(bounding, extent)
    end

    return setmetatable({
        zones = table.freeze(copied),
        _bounding = bounding,
    }, HurtboxComponent)
end

function HurtboxComponent:zoneCount(): number
    return #self.zones
end

-- The two segment endpoints of zone `index`, in WORLD space, given the pose to
-- hang it off -- plus that zone's radius, so a caller has everything Overlap
-- needs from one call.
--
-- `pose * offset` rather than `pose.Position + offset.Position`, and the
-- difference is the whole reason `offset` is a CFrame. The multiply carries the
-- pose's ROTATION into the result, so the zone leans when the body leans.
-- Adding positions instead produces zones that stay stubbornly world-upright
-- while the body turns -- and that error is invisible until something is
-- knocked over or stands on a slope.
--
-- ALONG THE ZONE'S LOCAL Y, from the zone's own frame, so a sideways arm
-- capsule stays sideways.
--
-- RETURNS THE SAME POINT TWICE when halfHeight is zero -- a zero-length
-- segment, which every Overlap function already treats as a sphere. Callers
-- never branch on shape.
function HurtboxComponent:endpoints(index: number, pose: CFrame): (Vector3, Vector3, number)
    local zone = self.zones[index]
    assert(zone, string.format(
        "[HurtboxComponent] no zone %s (have %d)", tostring(index), #self.zones))

    local world = pose * zone.offset
    local half = zone.halfHeight

    if half <= 0 then
        local p = world.Position
        return p, p, zone.radius
    end

    local axis = Vector3.new(0, half, 0)
    return world * axis, world * -axis, zone.radius
end

-- The furthest any point of any zone can sit from the pose the zones hang off.
--
-- THIS EXISTS FOR THE BROADPHASE AND IT IS NOT OPTIONAL. The cull discards
-- candidates further away than `reach + margin`, and with a zone list an
-- entity's real extent is its FURTHEST ZONE, not its body. Cull with a number
-- that describes only the torso and you silently drop an entity whose
-- outstretched arm genuinely was inside the volume.
--
-- That failure looks identical to broken overlap math and is far harder to
-- find, because the exact test never runs to be debugged. Wrong-high costs a
-- few extra tests; wrong-low costs real hits.
function HurtboxComponent:boundingRadius(): number
    return self._bounding
end

-- Diagnostics. The overlay labels capsules with this, so "the left arm zone is
-- in the wrong place" is a sentence you can say instead of "zone 4".
function HurtboxComponent:zoneName(index: number): string
    local zone = self.zones[index]
    return (zone and zone.name) or tostring(index)
end

return HurtboxComponent
