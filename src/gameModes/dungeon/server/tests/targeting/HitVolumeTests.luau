-- src/gameModes/dungeon/server/tests/targeting/HitVolumeTests.luau
--
-- The declarative half: vocabulary, defaults, validation, reach.
-- See HitDetection.md.
--
-- The reach cases carry the most weight. Reach sizes the broadphase cull, so
-- a reach that UNDERESTIMATES discards candidates before the exact overlap
-- test ever sees them -- producing misses caused by culling, which look
-- identical to misses caused by detection and are far harder to find.

local serverRoot = game.ServerScriptService:WaitForChild("Server")
local targeting = serverRoot:WaitForChild("resolution"):WaitForChild("targeting")

local HitVolume = require(targeting:WaitForChild("HitVolume"))
local TestRunner = require(script.Parent.Parent:WaitForChild("TestRunner"))

return function()
    local t = TestRunner.new("HitVolume")

    t:case("resolve fills defaults and freezes the result", function(a)
        local volume = HitVolume.resolve({ shape = "ARC", radius = 8, angle = 90 })

        a.equal(volume.anchor, HitVolume.Anchor.ATTACKER)
        a.equal(volume.aimSource, HitVolume.AimSource.FACING,
            "the default introduces no new client trust")
        a.equal(volume.samples, 1)
        a.equal(volume.activeWindow, 0)
        a.isFalse(volume.requiresLineOfSight)

        a.throws(function()
            local mutable: any = volume
            mutable.radius = 99
        end, nil, "content is read many times and written once")
    end)

    t:case("resolve does not mutate what it was given", function(a)
        local declared = { shape = "SPHERE", radius = 5 }
        HitVolume.resolve(declared)
        a.isNil(declared.anchor, "the caller's table is left alone")
    end)

    t:case("validate rejects malformed volumes with a reason", function(a)
        local function reason(volume)
            local _, message = HitVolume.validate(volume)
            return message or ""
        end

        a.isTrue(HitVolume.validate({ shape = "ARC", radius = 8, angle = 90 }))
        a.isTrue(string.find(reason({ shape = "WEDGE" }), "unknown shape") ~= nil)
        a.isTrue(string.find(reason({ shape = "ARC", angle = 90 }), "radius") ~= nil)
        a.isTrue(string.find(reason({ shape = "ARC", radius = 8, angle = 0 }), "angle") ~= nil)
        a.isTrue(string.find(reason({ shape = "ARC", radius = 8, angle = 400 }), "angle") ~= nil)
        a.isTrue(string.find(reason({ shape = "SPHERE", radius = -1 }), "positive") ~= nil)
        a.isTrue(string.find(reason({ shape = "BOX", size = 5 }), "Vector3") ~= nil)
    end)

    t:case("validate rejects an unknown anchor or aim source", function(a)
        local base = { shape = "SPHERE", radius = 5 }

        local withAnchor = table.clone(base)
        withAnchor.anchor = "SOMEWHERE"
        local ok, message = HitVolume.validate(withAnchor)
        a.isFalse(ok)
        a.isTrue(string.find(message, "anchor") ~= nil)

        local withAim = table.clone(base)
        withAim.aimSource = "VIBES"
        local aimOk, aimMessage = HitVolume.validate(withAim)
        a.isFalse(aimOk)
        a.isTrue(string.find(aimMessage, "aimSource") ~= nil)
    end)

    t:case("validate rejects multiple samples with no window to spread them over", function(a)
        -- Sampling an instant three times returns the same answer three
        -- times. Not wrong, but always a mistake worth naming.
        local ok, message = HitVolume.validate({
            shape = "ARC", radius = 8, angle = 90, samples = 3,
        })
        a.isFalse(ok)
        a.isTrue(string.find(message, "activeWindow") ~= nil)

        a.isTrue(HitVolume.validate({
            shape = "ARC", radius = 8, angle = 90, samples = 3, activeWindow = 0.12,
        }), "with a window, three samples are fine")
    end)

    t:case("reach never underestimates", function(a)
        a.near(HitVolume.reach({ shape = "SPHERE", radius = 5 }), 5)
        a.near(HitVolume.reach({ shape = "ARC", radius = 8, angle = 90 }), 8)
        a.near(HitVolume.reach({ shape = "CAPSULE", length = 10, radius = 1 }), 11,
            0.001, "a capsule reaches its far cap, not just its length")

        -- Half the DIAGONAL, not half the largest side: a rotated box reaches
        -- its corners, and the corner is what a cull has to clear.
        local diagonal = HitVolume.reach({ shape = "BOX", size = Vector3.new(4, 4, 4) })
        a.near(diagonal, math.sqrt(12), 0.001)
        a.isTrue(diagonal > 2, "a corner is further away than a face")
    end)

    t:case("reach accounts for an offset volume", function(a)
        local offset = CFrame.new(0, 0, -6)
        a.near(HitVolume.reach({ shape = "SPHERE", radius = 5, offset = offset }), 11)
    end)

    return t:run()
end
