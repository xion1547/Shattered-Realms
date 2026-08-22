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
-- WHY PLAYERS ARE TYPED HERE AND BOSSES WILL NOT BE
-- ============================================================================
--
-- HitDetection 7.3 lists three routes a hurtbox can be authored through, and
-- both of the ones that matter show up in this file's existence:
--
--   DECLARE   numbers typed in the Content Layer.  <- players, below
--   AUTHOR    parts placed by hand inside the rig. <- bosses, later
--
-- Players get the typed route for a boring reason: they wear Roblox's stock
-- R15 character. There is no `.rbxm` of ours to drop parts into, so there is
-- nothing to read. A boss is our own model, so its zones get placed by eye in
-- Studio and read off the rig at spawn -- which is the better workflow and the
-- one to reach for whenever it is available.
--
-- Nothing downstream can tell which route produced a list. That is what makes
-- the choice per-body and reversible.
--
-- ============================================================================
-- THESE NUMBERS ARE EYEBALLED AND ARE MEANT TO BE
-- ============================================================================
--
-- They are a starting point measured off R15's default proportions, not
-- derived truth. THE WAY TO CHECK THEM IS TO LOOK AT THEM: turn on
-- `DebugHurtboxes` and see whether the capsules sit on the body.
--
-- That is not laziness, it is HitDetection 0.5 -- essentially nothing in this
-- layer can be verified by reading numbers, and all of it is obvious on screen.
-- A leg capsule six inches off is invisible in this file and unmissable in the
-- viewport.
--
-- ============================================================================
-- R15 PROPORTIONS, SO THE NUMBERS BELOW ARE READABLE
-- ============================================================================
--
-- Everything is relative to `HumanoidRootPart`, which sits at the waist. Y is
-- up, X is sideways, and a default R15 character is roughly 5.5 studs tall:
--
--        +2.7   top of head
--        +2.2   head centre
--        +1.0   upper torso centre
--         0.0   ROOT -- the waist
--        -1.0   upper leg centre
--        -2.2   lower leg centre
--        -3.0   feet
--
-- ROTATION IS IDENTITY ON EVERY ZONE HERE, and that is a property of humanoids
-- standing up rather than a shortcut: arms hang down, legs point down, the
-- torso stands up, so every capsule runs along Y and needs no rotation. The
-- CFrame field earns its keep on creatures -- a horn angled forward, a wing
-- swept back, a tail curving away -- where a position-only offset would give
-- every zone the same upright orientation and look absurd.

local HurtboxDefinitions = {}

-- SIX ZONES, NOT TEN, and the count is a deliberate first cut.
--
-- R15 ships fifteen parts. Mirroring all of them would be more faithful and
-- would cost fifteen overlap tests per candidate per attack for a body whose
-- forearm and upper arm are never meaningfully in different places relative to
-- each other. Six covers the shape a swing actually cares about; split further
-- only when something needs to distinguish a hand from an elbow.
--
-- WHAT THIS FIXES. The shipped placeholder is ONE capsule, radius 1.5,
-- halfHeight 1.5 -- a 3-stud-wide, 6-stud-tall pill. A player is about 1.4
-- studs across the root and roughly 2 across the shoulders, so the placeholder
-- is over twice as wide as the body at every height, including at the ankles
-- and above the head. Six zones follow the silhouette instead.
HurtboxDefinitions.PLAYER_R15 = {
    -- A sphere, and correctly so: halfHeight 0 collapses the capsule to a
    -- point plus a radius, which is the right shape for a head and falls out
    -- of the arithmetic rather than needing a special case.
    { name = "Head",     offset = CFrame.new(0, 2.2, 0),     radius = 0.60, halfHeight = 0.00 },

    -- Upper and lower torso as one capsule. They are rigidly stacked and never
    -- separate enough to be worth two tests.
    { name = "Torso",    offset = CFrame.new(0, 0.5, 0),     radius = 0.75, halfHeight = 0.80 },

    -- Arms hang at roughly x = +/-1.0. Thin: 0.3 radius is 0.6 studs across,
    -- which is about what an R15 arm actually is. The placeholder called this
    -- region 1.5.
    { name = "ArmLeft",  offset = CFrame.new(-1.0, 0.3, 0),  radius = 0.30, halfHeight = 0.90 },
    { name = "ArmRight", offset = CFrame.new( 1.0, 0.3, 0),  radius = 0.30, halfHeight = 0.90 },

    { name = "LegLeft",  offset = CFrame.new(-0.5, -1.6, 0), radius = 0.40, halfHeight = 1.00 },
    { name = "LegRight", offset = CFrame.new( 0.5, -1.6, 0), radius = 0.40, halfHeight = 1.00 },
}

-- ONE ZONE, AND THAT IS THE POINT.
--
-- A dummy is a single anchored Part and its body is BUILT from these numbers,
-- so the model and the hurtbox match exactly by construction -- which is why
-- dummies are the only thing in the world where the overlay currently agrees
-- with what you see.
--
-- Kept as a one-entry list rather than a special case, because a single
-- capsule IS a zone list of length one. Nothing downstream learns that the old
-- single-capsule behaviour ever existed, and there is no branch to delete
-- later. Same trick as a sphere being a zero-length capsule.
HurtboxDefinitions.DUMMY = {
    { name = "Body", offset = CFrame.identity, radius = 1.50, halfHeight = 1.50 },
}

-- Fails loudly at boot rather than on the first swing against a malformed
-- body. Cheap, runs once, and catches the failure this layer specialises in:
-- a body that is quietly the wrong shape still returns hits, so nothing errors
-- and nothing looks broken until someone notices the numbers feel off months
-- later.
function HurtboxDefinitions.validate(): (boolean, string?)
    for name, zones in pairs(HurtboxDefinitions) do
        if type(zones) == "table" then
            if #zones == 0 then
                return false, string.format("'%s' has no zones", name)
            end
            for index, zone in ipairs(zones) do
                local label = zone.name or tostring(index)
                if typeof(zone.offset) ~= "CFrame" then
                    return false, string.format(
                        "'%s' zone '%s': offset must be a CFrame", name, label)
                end
                if type(zone.radius) ~= "number" or zone.radius <= 0 then
                    return false, string.format(
                        "'%s' zone '%s': radius must be positive", name, label)
                end
                if type(zone.halfHeight) ~= "number" or zone.halfHeight < 0 then
                    return false, string.format(
                        "'%s' zone '%s': halfHeight must be zero or positive", name, label)
                end
            end
        end
    end
    return true
end

return HurtboxDefinitions
