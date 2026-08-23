-- src/serverShared/definitions/HurtboxDefinitions.luau
--
-- HURTBOX SHAPES AS CONTENT. Each entry is a list of capsules; the generic
-- engine that reads one is `components/HurtboxComponent.luau`. Adding a body
-- shape is an entry here and nothing else.
--
-- SERVER ONLY, deliberately not in src/shared/. ReplicatedStorage is a
-- broadcast -- publishing this would hand every client the exact hittable
-- geometry of every body in the game. The client needs none of it: it plays
-- an animation and waits for a diff.
--
-- ============================================================================
-- EACH ZONE NAMES THE LIMB IT RIDES
-- ============================================================================
--
-- `anchor` is a part name inside the rig. The zone hangs off THAT part's pose,
-- so it follows the animation: raise an arm and its capsule goes up with it.
--
-- > REVISED 2026-08-22. The first version anchored every zone to the body's
-- > ROOT, which produced a rigid arrangement of capsules that ignored the pose
-- > entirely -- a mannequin riding the player. The reasoning was that a
-- > client-animated limb reaches the server about 0.104s stale (HitDetection
-- > 9.6), and at full sword-swing speed that is ~4.7 studs of error.
-- >
-- > That number is real and it was the wrong one to design around:
-- >
-- >     error = limb speed x 0.104s
-- >
-- >     standing / walking    ~3 studs/sec   -> 0.30 studs   (arm radius: 0.28)
-- >     running               ~6 studs/sec   -> 0.62 studs
-- >     mid sword-swing      ~45 studs/sec   -> 4.68 studs
-- >
-- > At the speeds a body spends nearly all its time at, the error is smaller
-- > than the capsule's own thickness. Root-anchoring bought exactness on zones
-- > that were never meaningfully inaccurate and paid for it with a body shape
-- > that matched nothing you could see.
-- >
-- > The swing case is real and is accepted: during your own attack an ARM zone
-- > is briefly stale -- the smallest zone on the body, on the defensive side,
-- > where "defense is generous" (Part 6) already errs your way.
--
-- ONE CONSEQUENCE, NAMED. A client owns its own limbs, so it can influence
-- where its own zones sit. Accepted rather than defended against: what a liar
-- wins is a slightly displaced arm capsule on the DEFENSIVE side, and
-- "defense is generous" (HitDetection Part 6) already errs their way anyway.
--
-- NOTHING ENFORCES A BOUND TODAY. An earlier version of this comment claimed
-- the displacement was "bounded rather than banned by a clamp on how far a
-- zone may sit from the root" (HitDetection 7.4) -- there is no such clamp,
-- in this file or anywhere else, and grepping for one was how that was found.
-- The bound is the right design if this ever matters; it is not built, and a
-- comment asserting a safety property the code does not have is worse than no
-- comment, because it stops anyone from checking.
--
-- What WOULD trigger building it: a body whose zones reach far enough from the
-- root that displacing one meaningfully changes what can hit it. An arm
-- capsule of radius 0.28 is not that.
--
-- ============================================================================
-- HOW PLAYERS AND BOSSES DIFFER, AND WHY
-- ============================================================================
--
-- HitDetection 7.3 lists three authoring routes, and two of them show up here:
--
--   DECLARE   numbers typed in the Content Layer.  <- players, below
--   AUTHOR    parts placed by hand inside the rig. <- bosses, later
--
-- Players get the typed route for a boring reason: they wear Roblox's stock
-- R15 character, so there is no `.rbxm` of ours to drop parts into and nothing
-- to read. A boss is our own model, so its zones get placed by eye in Studio
-- and read off the rig at spawn -- the better workflow, and the one to reach
-- for whenever it is available.
--
-- Nothing downstream can tell which route produced a list.
--
-- ============================================================================
-- THE NUMBERS ARE EYEBALLED AND ARE MEANT TO BE
-- ============================================================================
--
-- Measured off R15's default part sizes, not derived. THE WAY TO CHECK THEM IS
-- TO LOOK: `DebugHurtboxes` draws them, `DebugHurtboxLog` prints them.
--
-- That is HitDetection 0.5, not laziness -- essentially nothing in this layer
-- can be verified by reading numbers, and all of it is obvious on screen. A
-- forearm capsule six inches long is invisible here and unmissable in the
-- viewport.
--
-- R15 part sizes this was measured against, roughly:
--
--     UpperTorso  1.6 tall     UpperArm  1.4 tall     UpperLeg  1.6 tall
--     LowerTorso  0.4          LowerArm  1.2          LowerLeg  1.4
--     Head        1.2          Hand      0.4          Foot      0.4
--
-- OFFSETS ARE RELATIVE TO THE ANCHOR PART, not to the root. `CFrame.identity`
-- means "centred on that limb", which is right for most of them.

local HurtboxDefinitions = {}

-- TEN ZONES, and the count went UP from six when zones started riding limbs.
--
-- Six meant one capsule per arm, anchored to the upper arm and stretched to
-- cover the forearm. That is fine while the arm is straight and wrong the
-- moment an elbow bends -- which is most of what an arm does. Splitting at the
-- joints is the entire point of anchoring to limbs; not splitting them would
-- have kept the mannequin problem in a smaller costume.
--
-- Still merged deliberately: UpperTorso and LowerTorso are one zone (the waist
-- barely articulates), and hands and feet ride the forearm and shin capsules
-- rather than getting their own. Split those when something needs to tell a
-- hand from an elbow.
--
-- WHAT THIS REPLACES: one capsule, radius 1.5, halfHeight 1.5 -- a
-- 3-stud-wide, 6-stud-tall pill on a body 1.4 studs across the root. Over
-- twice the player's width at every height, including at the ankles and above
-- the head.
HurtboxDefinitions.PLAYER_R15 = {
    -- A sphere, correctly: halfHeight 0 collapses the capsule to a point plus
    -- a radius, which is the right shape for a head and falls out of the
    -- arithmetic rather than needing a special case.
    { name = "Head", anchor = "Head",
      offset = CFrame.identity, radius = 0.60, halfHeight = 0.00 },

    -- Anchored to UpperTorso and pushed down slightly so it spans the waist
    -- too. Those two parts hinge barely at all, so one capsule is honest.
    { name = "Torso", anchor = "UpperTorso",
      offset = CFrame.new(0, -0.20, 0), radius = 0.70, halfHeight = 0.55 },

    { name = "ArmUpperL", anchor = "LeftUpperArm",
      offset = CFrame.identity, radius = 0.28, halfHeight = 0.45 },
    -- Extends past the forearm to swallow the hand, which does not earn a zone
    -- of its own yet.
    { name = "ArmLowerL", anchor = "LeftLowerArm",
      offset = CFrame.new(0, -0.20, 0), radius = 0.26, halfHeight = 0.50 },

    { name = "ArmUpperR", anchor = "RightUpperArm",
      offset = CFrame.identity, radius = 0.28, halfHeight = 0.45 },
    { name = "ArmLowerR", anchor = "RightLowerArm",
      offset = CFrame.new(0, -0.20, 0), radius = 0.26, halfHeight = 0.50 },

    { name = "LegUpperL", anchor = "LeftUpperLeg",
      offset = CFrame.identity, radius = 0.35, halfHeight = 0.50 },
    -- Extends past the shin to swallow the foot.
    { name = "LegLowerL", anchor = "LeftLowerLeg",
      offset = CFrame.new(0, -0.20, 0), radius = 0.33, halfHeight = 0.55 },

    { name = "LegUpperR", anchor = "RightUpperLeg",
      offset = CFrame.identity, radius = 0.35, halfHeight = 0.50 },
    { name = "LegLowerR", anchor = "RightLowerLeg",
      offset = CFrame.new(0, -0.20, 0), radius = 0.33, halfHeight = 0.55 },
}

-- ONE ZONE, AND THAT IS THE POINT.
--
-- A dummy is a single anchored Part and its body is BUILT from these numbers,
-- so the model and the hurtbox match exactly by construction -- which is why
-- dummies are the only bodies in the world where the overlay already agrees
-- with what you see.
--
-- No `anchor`: with none named, a zone falls back to the body's root, which is
-- the only part a dummy has. Kept as a one-entry list rather than a special
-- case, because a single capsule IS a zone list of length one. Nothing
-- downstream learns the old single-capsule behaviour ever existed, and there
-- is no branch to delete later.
HurtboxDefinitions.DUMMY = {
    { name = "Body", offset = CFrame.identity, radius = 1.50, halfHeight = 1.50 },
}

-- Fails loudly at boot rather than on the first swing against a malformed
-- body. Cheap, runs once, and catches the failure this layer specialises in:
-- a body that is quietly the wrong shape still returns hits, so nothing errors
-- and nothing looks broken until someone notices the numbers feel off months
-- later.
function HurtboxDefinitions.validate(): (boolean, string?)
    for setName, zones in pairs(HurtboxDefinitions) do
        if type(zones) == "table" then
            if #zones == 0 then
                return false, string.format("'%s' has no zones", setName)
            end
            for index, zone in ipairs(zones) do
                local label = zone.name or tostring(index)
                if typeof(zone.offset) ~= "CFrame" then
                    return false, string.format(
                        "'%s' zone '%s': offset must be a CFrame", setName, label)
                end
                if type(zone.radius) ~= "number" or zone.radius <= 0 then
                    return false, string.format(
                        "'%s' zone '%s': radius must be positive", setName, label)
                end
                if type(zone.halfHeight) ~= "number" or zone.halfHeight < 0 then
                    return false, string.format(
                        "'%s' zone '%s': halfHeight must be zero or positive", setName, label)
                end
                if zone.anchor ~= nil and type(zone.anchor) ~= "string" then
                    return false, string.format(
                        "'%s' zone '%s': anchor must be a part NAME, not an Instance "
                            .. "-- it is resolved per body at attach", setName, label)
                end
            end
        end
    end
    return true
end

return HurtboxDefinitions
