-- src/gameModes/dungeon/server/tests/targeting/OverlapTests.luau
--
-- The four sphere-vs-shape tests. See HitDetection.md.
--
-- Overlap has no requires and touches no engine state, so every case here is
-- pure: CFrames and Vector3s in, a boolean out. EVERY EXPECTED VALUE IS
-- COMPUTED BY HAND rather than observed -- a test asserting whatever the
-- code currently returns is not a test.
--
-- The cases that matter are the ones a NAIVE implementation passes: a target
-- whose centre sits outside an arc while its body is inside it, and a box
-- that has been rotated.

local serverRoot = game.ServerScriptService:WaitForChild("Server")
local targeting = serverRoot:WaitForChild("resolution"):WaitForChild("targeting")

local Overlap = require(targeting:WaitForChild("Overlap"))
local TestRunner = require(script.Parent.Parent:WaitForChild("TestRunner"))

-- Looking down -Z, which is a Part's default facing.
local FORWARD = Vector3.new(0, 0, -1)
local ORIGIN = CFrame.lookAt(Vector3.zero, FORWARD)

-- A point `degrees` off FORWARD in the XZ plane, at `distance`.
local function offAxis(degrees: number, distance: number): Vector3
    local rad = math.rad(degrees)
    return Vector3.new(math.sin(rad), 0, -math.cos(rad)) * distance
end

return function()
    local t = TestRunner.new("Overlap")

    -- SPHERE ---------------------------------------------------------------

    t:case("sphere overlap counts the target's own radius", function(a)
        local volume = { shape = "SPHERE", radius = 5 }

        a.isTrue(Overlap.sphere(ORIGIN, volume, Vector3.new(0, 0, -4), 1), "well inside")
        a.isFalse(Overlap.sphere(ORIGIN, volume, Vector3.new(0, 0, -10), 1), "well outside")

        -- A centre at 5.5 is outside a radius-5 sphere, but a body of radius
        -- 1 reaches back to 4.5. Testing centres alone misses this.
        a.isTrue(Overlap.sphere(ORIGIN, volume, Vector3.new(0, 0, -5.5), 1),
            "centre outside, body overlapping")
        a.isFalse(Overlap.sphere(ORIGIN, volume, Vector3.new(0, 0, -6.5), 1),
            "centre outside, body clear")
    end)

    t:case("sphere overlap is symmetric in all three axes", function(a)
        local volume = { shape = "SPHERE", radius = 5 }
        for _, axis in ipairs({ Vector3.xAxis, Vector3.yAxis, Vector3.zAxis }) do
            a.isTrue(Overlap.sphere(ORIGIN, volume, axis * 4, 0.5))
            a.isFalse(Overlap.sphere(ORIGIN, volume, axis * 9, 0.5))
        end
    end)

    -- BOX ------------------------------------------------------------------

    t:case("box overlap clamps to the nearest face", function(a)
        local volume = { shape = "BOX", size = Vector3.new(4, 4, 4) }

        a.isTrue(Overlap.box(ORIGIN, volume, Vector3.zero, 0.1), "dead centre")
        a.isTrue(Overlap.box(ORIGIN, volume, Vector3.new(2.4, 0, 0), 0.5),
            "0.4 outside the face, radius 0.5 reaches it")
        a.isFalse(Overlap.box(ORIGIN, volume, Vector3.new(3, 0, 0), 0.5),
            "1.0 outside the face, radius 0.5 does not")
    end)

    t:case("box overlap respects rotation", function(a)
        -- A 2x2x10 box points down its own Z. Rotated 90 degrees about Y it
        -- extends along world X instead. An axis-aligned implementation
        -- passes the first assertion and fails the second.
        local volume = { shape = "BOX", size = Vector3.new(2, 2, 10) }
        local rotated = CFrame.Angles(0, math.rad(90), 0)

        a.isTrue(Overlap.box(rotated, volume, Vector3.new(4, 0, 0), 0.5),
            "along the box's long axis after rotation")
        a.isFalse(Overlap.box(rotated, volume, Vector3.new(0, 0, 4), 0.5),
            "along where the long axis USED to be")
    end)

    -- ARC ------------------------------------------------------------------

    t:case("arc overlap rejects what is behind it", function(a)
        local volume = { shape = "ARC", radius = 10, angle = 90 }

        a.isTrue(Overlap.arc(ORIGIN, volume, Vector3.new(0, 0, -5), 1), "straight ahead")
        a.isFalse(Overlap.arc(ORIGIN, volume, Vector3.new(0, 0, 5), 1), "straight behind")
    end)

    t:case("arc overlap widens by the target's angular size", function(a)
        -- THE CASE A NAIVE IMPLEMENTATION GETS WRONG. A 90-degree arc reaches
        -- 45 degrees either side. A body of radius 1 at distance 5 subtends
        -- asin(1/5) = 11.54 degrees, so its edge reaches that much past its
        -- centre.
        local volume = { shape = "ARC", radius = 10, angle = 90 }

        -- 50 - 11.54 = 38.46, inside 45. The centre is out; the body is not.
        a.isTrue(Overlap.arc(ORIGIN, volume, offAxis(50, 5), 1),
            "centre beyond the arc edge, body inside it")

        -- 60 - 11.54 = 48.46, outside 45.
        a.isFalse(Overlap.arc(ORIGIN, volume, offAxis(60, 5), 1),
            "far enough out that even the body misses")

        -- A point-sized target gets no widening at all.
        a.isFalse(Overlap.arc(ORIGIN, volume, offAxis(50, 5), 0),
            "with no radius, 50 degrees is simply outside 45")
    end)

    t:case("arc overlap always hits when the attacker is inside the target", function(a)
        -- Standing inside a boss, every direction to its centre is
        -- arbitrary. Facing must not get to decide this.
        local volume = { shape = "ARC", radius = 10, angle = 45 }
        a.isTrue(Overlap.arc(ORIGIN, volume, Vector3.new(0, 0, 2), 8),
            "target centre is behind, but the attacker is inside its body")
    end)

    t:case("a 360 degree arc hits in every direction", function(a)
        local volume = { shape = "ARC", radius = 10, angle = 360 }
        a.isTrue(Overlap.arc(ORIGIN, volume, Vector3.new(0, 0, 5), 1), "behind")
        a.isTrue(Overlap.arc(ORIGIN, volume, Vector3.new(5, 0, 0), 1), "beside")
        a.isFalse(Overlap.arc(ORIGIN, volume, Vector3.new(0, 0, 20), 1), "still bounded by radius")
    end)

    -- CAPSULE --------------------------------------------------------------

    t:case("capsule overlap measures to the nearest point on the segment", function(a)
        local volume = { shape = "CAPSULE", length = 10, radius = 1 }

        a.isTrue(Overlap.capsule(ORIGIN, volume, Vector3.new(0, 0, -5), 1), "on the line")
        a.isTrue(Overlap.capsule(ORIGIN, volume, Vector3.new(0, 1.5, -5), 1),
            "1.5 off the line, radii sum to 2")
        a.isFalse(Overlap.capsule(ORIGIN, volume, Vector3.new(0, 3, -5), 1), "3 off the line")
        a.isFalse(Overlap.capsule(ORIGIN, volume, Vector3.new(0, 0, -15), 1), "past the far end")
    end)

    t:case("capsule overlap detects what it starts inside", function(a)
        -- Unlike a raycast, which would not. A thrust that begins inside an
        -- enemy already standing on top of you has to register.
        local volume = { shape = "CAPSULE", length = 10, radius = 1 }
        a.isTrue(Overlap.capsule(ORIGIN, volume, Vector3.zero, 1), "at the origin")
    end)

    -- DISPATCH -------------------------------------------------------------

    t:case("an unknown shape errors rather than quietly missing", function(a)
        -- A volume that never hits anything looks exactly like a balance
        -- problem, which is the worst possible disguise for a typo.
        a.throws(function()
            Overlap.test(ORIGIN, { shape = "TRAPEZOID" }, Vector3.zero, 1)
        end, "unknown shape")

        a.isTrue(Overlap.supports("ARC"))
        a.isFalse(Overlap.supports("TRAPEZOID"))
    end)

    return t:run()
end
