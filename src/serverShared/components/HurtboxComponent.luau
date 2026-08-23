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
-- `endpoints(i, pose)` takes the pose to hang zone `i` off, and `bind` resolves
-- each zone's named part so a caller knows WHICH pose to pass. A zone rides its
-- own limb: raise an arm and its capsule goes up with it.
--
-- THE CALLER SUPPLIES THE POSE RATHER THAN THIS FILE READING IT, and that is
-- what keeps the whole thing rewindable. Resolution needs where a limb was at a
-- PAST moment, which comes from a history buffer, not from the live Instance. A
-- component that read `part.CFrame` itself could only ever answer about now.
--
-- > A ROOT-ANCHORED VERSION WAS BUILT FIRST AND REVERSED 2026-08-22. Every zone
-- > hung off the body's root, which produced a rigid arrangement of capsules
-- > ignoring the pose entirely -- a mannequin riding the player. The reasoning
-- > was that a client-animated limb reaches the server ~0.104s stale, worth
-- > 4.7 studs at full swing speed. Real number, wrong one to design around:
-- >
-- >     error = limb speed x 0.104s
-- >     walking  ~3/sec -> 0.30 studs   (an arm capsule's radius is 0.28)
-- >     swinging ~45/sec -> 4.68 studs
-- >
-- > At the speeds a body spends nearly all its time at, the error is under the
-- > capsule's own thickness. HurtboxDefinitions carries the full argument.
--
-- WHAT IS STILL OWED, and it is not in this file: resolution rewinds, so each
-- zone needs its own history rather than one buffer per body -- a wing and a
-- torso are in different places at different moments. Until that lands, the
-- overlay reads limbs LIVE and resolution still tests the old single capsule.
-- HitDetection 7.2a.
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

    -- The NAME of the rig part this zone rides. `offset` is relative to that
    -- part's pose, so the zone follows the animation.
    --
    -- A NAME, NEVER AN INSTANCE, and that is the whole reason this is a string.
    -- The same definition table is shared by every body of a given kind and
    -- survives every respawn; an Instance reference would bind one list to one
    -- corpse. Resolution to an actual part happens per body, in `bind`.
    --
    -- Absent means "ride the body's root", which is right for anything with
    -- one part -- a dummy -- and is the fallback when a named part is missing.
    anchor: string?,

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


    for index, zone in ipairs(zones) do
        local label = zone.name or tostring(index)

        assert(typeof(zone.offset) == "CFrame", string.format(
            "[HurtboxComponent] zone '%s': offset must be a CFrame, not a Vector3 "
                .. "-- a capsule has a direction", label))
        assert(type(zone.radius) == "number" and zone.radius > 0, string.format(
            "[HurtboxComponent] zone '%s': radius must be positive", label))
        assert(type(zone.halfHeight) == "number" and zone.halfHeight >= 0, string.format(
            "[HurtboxComponent] zone '%s': halfHeight must be zero or positive", label))

        assert(zone.anchor == nil or type(zone.anchor) == "string", string.format(
            "[HurtboxComponent] zone '%s': anchor must be a part NAME, not an "
                .. "Instance -- it is resolved per body in bind()", label))

        copied[index] = table.freeze({
            offset = zone.offset,
            radius = zone.radius,
            halfHeight = zone.halfHeight,
            anchor = zone.anchor,
            name = zone.name,
        })

    end

    return setmetatable({
        zones = table.freeze(copied),

        -- Measured in `bind`, because it cannot be known here: a zone's offset is
        -- relative to ITS LIMB, and how far that limb sits from the root is a
        -- property of the body, not of the zone list.
        _bounding = 0,

        -- Resolved per body by `bind`. Empty until then, and every zone falls
        -- back to whatever pose a caller supplies.
        _anchors = {},
    }, HurtboxComponent)
end

function HurtboxComponent:zoneCount(): number
    return #self.zones
end

-- Resolves each zone's anchor NAME to an actual part on this body.
--
-- CALLED ON EVERY ATTACH, INCLUDING EVERY RESPAWN, and that is not an
-- optimisation to skip. A respawned character is a brand new set of Instances;
-- anchors resolved against the previous body point at parts that have been
-- destroyed, and a zone hanging off a destroyed part silently stops moving.
-- That reads as "the hurtbox is stuck", which is a bug nobody would think to
-- look for here.
--
-- A MISSING PART FALLS BACK TO THE ROOT AND WARNS ONCE, rather than erroring.
-- The list is content and the rig is art, and the two drift: an R6 character,
-- a renamed limb, a boss exported without a part. Failing hard would make one
-- bad zone name cost the whole body's hittability, which is a much worse
-- outcome than one zone in the wrong place -- and the warning is what stops it
-- being silent.
function HurtboxComponent:bind(model: Instance?, root: BasePart?)
    table.clear(self._anchors)

    for index, zone in ipairs(self.zones) do
        local part = nil

        if zone.anchor and model then
            local found = model:FindFirstChild(zone.anchor)
            if found and found:IsA("BasePart") then
                part = found
            else
                warn(string.format(
                    "[HurtboxComponent] zone '%s' wants part '%s' and this body has "
                        .. "no such BasePart -- falling back to the root, so this "
                        .. "zone will not follow the animation",
                    zone.name or tostring(index), zone.anchor))
            end
        end

        self._anchors[index] = part or root
    end

    self:_measureBounding(root)
end

-- How far any zone can sit from the ROOT, which is what the broadphase culls
-- against.
--
-- IT CANNOT BE COMPUTED FROM THE ZONE LIST ALONE, and getting that wrong is
-- how a hurtbox silently shrinks. A zone's offset is relative to ITS LIMB, so
-- summing offset + halfHeight + radius answers "how far does this capsule
-- reach from its own limb" -- which for a player came out at 1.45 studs while
-- the real reach from the root was nearly twice that. The cull was tight and
-- the error was masked only because the volume's own reach dominated it.
--
-- So it is measured here, where the limbs actually exist, as
-- (limb from root) + (zone from limb).
--
-- PADDED, BECAUSE THIS IS A REST-POSE MEASUREMENT. Limbs move: an arm raised
-- overhead puts its capsule much further from the root than the same arm
-- hanging down. The pad is deliberately generous because the two errors are
-- not symmetric -- wrong-high costs a few extra exact tests, wrong-low
-- silently drops real hits before the exact test ever runs.
--
-- If it ever proves too tight, the upgrade is a running maximum updated as
-- limbs are sampled, which is self-correcting. Not built: a fixed pad is
-- deterministic and costs nothing per tick.
local REST_POSE_PAD = 2.0

function HurtboxComponent:_measureBounding(root: BasePart?)
    local bounding = 0

    for index, zone in ipairs(self.zones) do
        local part = self._anchors[index]

        local fromRoot = 0
        if part and root and part ~= root and part.Parent and root.Parent then
            fromRoot = (root.CFrame:Inverse() * part.CFrame).Position.Magnitude
        end

        local extent = fromRoot
            + zone.offset.Position.Magnitude
            + zone.halfHeight
            + zone.radius

        bounding = math.max(bounding, extent)
    end

    self._bounding = bounding * REST_POSE_PAD
end

-- The part zone `index` rides, or nil when nothing has been bound.
--
-- CALLERS READ THIS TO GET THE POSE, rather than the component reading it
-- itself, and that is what keeps the whole thing rewindable: resolution needs
-- the pose this part had at a PAST moment, which comes from a history buffer
-- and not from the live Instance. A component that read `part.CFrame` itself
-- would only ever be able to answer about now.
function HurtboxComponent:anchorFor(index: number): BasePart?
    return self._anchors[index]
end

-- Convenience for the LIVE case -- diagnostics, and anything that genuinely
-- wants "where is this zone right now". Never the path resolution takes.
function HurtboxComponent:livePose(index: number): CFrame?
    local part = self._anchors[index]
    if part and part.Parent then
        return part.CFrame
    end
    return nil
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
