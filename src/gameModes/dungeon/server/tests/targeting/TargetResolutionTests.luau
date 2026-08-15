-- src/gameModes/dungeon/server/tests/targeting/TargetResolutionTests.luau
--
-- The engine end to end, against real attached entities. See HitDetection.md.
--
-- Unlike OverlapTests these are not pure -- they attach real BaseParts to
-- SpatialService and tick it, because the thing worth testing is the whole
-- chain: origin resolution, the broadphase cull, the rewound narrow phase,
-- filtering, and the cap. Testing the stages in isolation would miss exactly
-- the bug this layer is most likely to have, which is one stage discarding
-- what another stage would have found.

local ServerStorage = game:GetService("ServerStorage")
local components = ServerStorage:WaitForChild("Shared"):WaitForChild("components")

local IdentityRegistry = require(ServerStorage:WaitForChild("Shared")
    :WaitForChild("registries"):WaitForChild("IdentityRegistry"))

local IdentityComponent = require(components:WaitForChild("IdentityComponent"))
local SpatialComponent = require(components:WaitForChild("SpatialComponent"))

local serverRoot = game.ServerScriptService:WaitForChild("Server")
local targeting = serverRoot:WaitForChild("resolution"):WaitForChild("targeting")

local HitVolume = require(targeting:WaitForChild("HitVolume"))
local TargetQuery = require(targeting:WaitForChild("TargetQuery"))
local TargetResolution = require(targeting:WaitForChild("TargetResolution"))
local SpatialService = require(serverRoot:WaitForChild("services"):WaitForChild("authority")
    :WaitForChild("SpatialService"))

local TestRunner = require(script.Parent.Parent:WaitForChild("TestRunner"))

local FORWARD = Vector3.new(0, 0, -1)

local nextId = 0
local spawned = {}

local function makeEntity(position: Vector3, radius: number, facing: Vector3?)
    nextId += 1

    local part = Instance.new("Part")
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.Transparency = 1
    part.Size = Vector3.one
    part.CFrame = CFrame.lookAt(position, position + (facing or FORWARD))
    part.Parent = workspace

    local entity = {
        identity = IdentityComponent.new(IdentityRegistry.ENEMY,"TEST_" .. nextId),
        spatial = SpatialComponent.new(),
    }
    SpatialService:attach(entity, part, radius)

    table.insert(spawned, { entity = entity, part = part })
    return entity
end

local function cleanup()
    for _, row in ipairs(spawned) do
        SpatialService:detach(row.entity)
        row.part:Destroy()
    end
    table.clear(spawned)
end

local function contains(list, entity): boolean
    for _, found in ipairs(list) do
        if found == entity then
            return true
        end
    end
    return false
end

return function()
    local t = TestRunner.new("TargetResolution")

    t:case("resolves entities inside the volume and no others", function(a)
        local attacker = makeEntity(Vector3.zero, 2)
        local infront = makeEntity(Vector3.new(0, 0, -6), 2)
        local behind = makeEntity(Vector3.new(0, 0, 6), 2)
        local distant = makeEntity(Vector3.new(0, 0, -60), 2)
        SpatialService:tick(1 / 30)

        local hits = TargetResolution.resolve(TargetQuery.new({
            attacker = attacker,
            volume = HitVolume.resolve({ shape = "ARC", radius = 10, angle = 90 }),
            at = workspace:GetServerTimeNow(),
        }))

        a.isTrue(contains(hits, infront), "in the arc")
        a.isFalse(contains(hits, behind), "behind the arc")
        a.isFalse(contains(hits, distant), "beyond the reach")
        a.isFalse(contains(hits, attacker), "an attacker never hits itself")
        cleanup()
    end)

    t:case("the filter predicate decides eligibility, not this module", function(a)
        -- Whether a pet may hit its owner is a combat rule, and rules belong
        -- to Services (Part 3). This module finds bodies and has no opinion
        -- about which ones deserve it.
        local attacker = makeEntity(Vector3.zero, 2)
        local allowed = makeEntity(Vector3.new(0, 0, -5), 2)
        local refused = makeEntity(Vector3.new(0, 0, -7), 2)
        SpatialService:tick(1 / 30)

        local hits = TargetResolution.resolve(TargetQuery.new({
            attacker = attacker,
            volume = HitVolume.resolve({ shape = "SPHERE", radius = 20 }),
            at = workspace:GetServerTimeNow(),
            filter = function(entity)
                return entity ~= refused
            end,
        }))

        a.isTrue(contains(hits, allowed))
        a.isFalse(contains(hits, refused))
        cleanup()
    end)

    t:case("a target caught by every sample is still one target", function(a)
        -- Part 8's rule -- one calculation, cosmetic fragmentation --
        -- enforced here rather than trusted to the caller.
        local attacker = makeEntity(Vector3.zero, 2)
        local victim = makeEntity(Vector3.new(0, 0, -5), 2)
        SpatialService:tick(1 / 30)

        -- Only one sample exists, so all three lookups clamp to it. That is
        -- fine and is not what this case measures: the assertion is that
        -- three passes over the same entity produce one entry, not three.
        local hits = TargetResolution.resolve(TargetQuery.new({
            attacker = attacker,
            volume = HitVolume.resolve({
                shape = "SPHERE", radius = 20, samples = 3, activeWindow = 0.1,
            }),
            at = workspace:GetServerTimeNow() - 0.1,
        }))

        a.equal(#hits, 1, "three samples, one entity, one entry")
        a.isTrue(contains(hits, victim))
        cleanup()
    end)

    t:case("maxTargets caps the result", function(a)
        local attacker = makeEntity(Vector3.zero, 2)
        for index = 1, 5 do
            makeEntity(Vector3.new(index, 0, -5), 2)
        end
        SpatialService:tick(1 / 30)

        local hits = TargetResolution.resolve(TargetQuery.new({
            attacker = attacker,
            volume = HitVolume.resolve({ shape = "SPHERE", radius = 30, maxTargets = 2 }),
            at = workspace:GetServerTimeNow(),
        }))

        a.equal(#hits, 2, "a skill is made single- or few-target by data, not by code")
        cleanup()
    end)

    t:case("preferredId sorts first without adding a target", function(a)
        local attacker = makeEntity(Vector3.zero, 2)
        makeEntity(Vector3.new(1, 0, -4), 2)
        local wanted = makeEntity(Vector3.new(2, 0, -6), 2)
        makeEntity(Vector3.new(3, 0, -5), 2)
        SpatialService:tick(1 / 30)

        local hits = TargetResolution.resolve(TargetQuery.new({
            attacker = attacker,
            volume = HitVolume.resolve({ shape = "SPHERE", radius = 30, maxTargets = 1 }),
            at = workspace:GetServerTimeNow(),
            preferredId = wanted.identity:getId(),
        }))

        a.equal(#hits, 1)
        a.equal(hits[1], wanted, "the capped hit goes to what the player pointed at")
        cleanup()
    end)

    t:case("a preferredId outside the volume is ignored, never honoured", function(a)
        -- The whole reason there is one code path: a client-supplied id can
        -- reorder a set the server computed, and can never join it.
        local attacker = makeEntity(Vector3.zero, 2)
        local reachable = makeEntity(Vector3.new(0, 0, -5), 2)
        local unreachable = makeEntity(Vector3.new(0, 0, -500), 2)
        SpatialService:tick(1 / 30)

        local hits = TargetResolution.resolve(TargetQuery.new({
            attacker = attacker,
            volume = HitVolume.resolve({ shape = "SPHERE", radius = 20 }),
            at = workspace:GetServerTimeNow(),
            preferredId = unreachable.identity:getId(),
        }))

        a.isFalse(contains(hits, unreachable), "naming it does not summon it")
        a.isTrue(contains(hits, reachable))
        cleanup()
    end)

    t:case("a POINT-anchored volume ignores where the attacker stands", function(a)
        local attacker = makeEntity(Vector3.zero, 2)
        local far = makeEntity(Vector3.new(0, 0, -80), 2)
        local near = makeEntity(Vector3.new(0, 0, -5), 2)
        SpatialService:tick(1 / 30)

        local hits = TargetResolution.resolve(TargetQuery.new({
            attacker = attacker,
            volume = HitVolume.resolve({
                shape = "SPHERE", radius = 10, anchor = HitVolume.Anchor.POINT,
            }),
            at = workspace:GetServerTimeNow(),
            origin = CFrame.new(0, 0, -80),
        }))

        a.isTrue(contains(hits, far), "a ground-targeted AoE lands where it was aimed")
        a.isFalse(contains(hits, near), "not where the caster is standing")
        cleanup()
    end)

    t:case("an unanchored attacker resolves to nothing rather than erroring", function(a)
        -- An entity dying mid-swing is ordinary, not exceptional.
        local orphan = { identity = IdentityComponent.new(IdentityRegistry.ENEMY,"ORPHAN"), spatial = SpatialComponent.new() }
        local hits = TargetResolution.resolve(TargetQuery.new({
            attacker = orphan,
            volume = HitVolume.resolve({ shape = "SPHERE", radius = 10 }),
            at = workspace:GetServerTimeNow(),
        }))
        a.equal(#hits, 0)
    end)

    t:case("client aim rotates the volume; a degenerate aim falls back to facing", function(a)
        local attacker = makeEntity(Vector3.zero, 2)
        local behind = makeEntity(Vector3.new(0, 0, 6), 2)
        SpatialService:tick(1 / 30)

        local volume = HitVolume.resolve({
            shape = "ARC", radius = 12, angle = 60,
            aimSource = HitVolume.AimSource.CLIENT_AIM,
        })
        local now = workspace:GetServerTimeNow()

        local aimed = TargetResolution.resolve(TargetQuery.new({
            attacker = attacker, volume = volume, at = now,
            aim = Vector3.new(0, 0, 1),
        }))
        a.isTrue(contains(aimed, behind), "aiming backwards reaches what is behind")

        local degenerate = TargetResolution.resolve(TargetQuery.new({
            attacker = attacker, volume = volume, at = now,
            aim = Vector3.zero,
        }))
        a.isFalse(contains(degenerate, behind),
            "a zero aim falls back to facing rather than producing a NaN volume")
        cleanup()
    end)

    return t:run()
end
