-- src/gameModes/dungeon/server/tests/targeting/OverlapTests.luau
--
-- The volume-vs-capsule tests. See HitDetection.md §7.
--
-- Overlap has no requires and touches no engine state, so every case here is
-- pure: CFrames and Vector3s in, a boolean out. EVERY EXPECTED VALUE IS
-- COMPUTED BY HAND rather than observed -- a test asserting whatever the
-- code currently returns is not a test.
--
-- THE TARGET IS NOW A CAPSULE: two segment endpoints plus a radius. Every
-- case that predates that change is preserved verbatim except for passing
-- the point TWICE, because a zero-length capsule IS a sphere. That is the
-- proof the refactor was behaviour-preserving -- if these still pass, the new
-- maths reduces to the old maths, and anything that breaks afterwards is new
-- behaviour rather than regression.
--
-- The cases that matter are the ones a NAIVE implementation passes: a target
-- whose centre sits outside an arc while its body is inside it, and a long
-- capsule lying across the swing with neither endpoint inside the cone.

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

    -- SPHERE (degenerate capsule) -------------------------------------------

    t:case("sphere overlap counts the target's own radius", function(a)
        local volume = { shape = "SPHERE", radius = 5 }
        local p

        p = Vector3.new(0, 0, -4)
        a.isTrue(Overlap.sphere(ORIGIN, volume, p, p, 1), "well inside")

        p = Vector3.new(0, 0, -10)
        a.isFalse(Overlap.sphere(ORIGIN, volume, p, p, 1), "well outside")

        -- A centre at 5.5 is outside a radius-5 sphere, but a body of radius
        -- 1 reaches back to 4.5. Testing centres alone misses this.
        p = Vector3.new(0, 0, -5.5)
        a.isTrue(Overlap.sphere(ORIGIN, volume, p, p, 1), "centre outside, body overlapping")

        p = Vector3.new(0, 0, -6.5)
        a.isFalse(Overlap.sphere(ORIGIN, volume, p, p, 1), "centre outside, body clear")
    end)

    t:case("sphere overlap is symmetric in all three axes", function(a)
        local volume = { shape = "SPHERE", radius = 5 }
        for _, axis in ipairs({ Vector3.xAxis, Vector3.yAxis, Vector3.zAxis }) do
            a.isTrue(Overlap.sphere(ORIGIN, volume, axis * 4, axis * 4, 0.5))
            a.isFalse(Overlap.sphere(ORIGIN, volume, axis * 9, axis * 9, 0.5))
        end
    end)

    -- SPHERE, genuinely capsule-shaped targets ------------------------------

    t:case("sphere overlap measures to the nearest point on the target segment", function(a)
        local volume = { shape = "SPHERE", radius = 3 }

        -- A 20-stud capsule running along X, well past the volume in both
        -- directions, but crossing right through it.
        local far = Vector3.new(-10, 0, 0)
        local near = Vector3.new(10, 0, 0)
        a.isTrue(Overlap.sphere(ORIGIN, volume, far, near, 0.5),
            "both endpoints far outside, the segment passes through the centre")

        -- Same segment, lifted clear.
        a.isFalse(Overlap.sphere(ORIGIN, volume, far + Vector3.new(0, 4, 0),
            near + Vector3.new(0, 4, 0), 0.5), "4 above, radii sum to 3.5")
    end)

    -- ARC --------------------------------------------------------------------

    t:case("arc overlap rejects what is behind it", function(a)
        local volume = { shape = "ARC", radius = 10, angle = 90 }
        local p

        p = Vector3.new(0, 0, -5)
        a.isTrue(Overlap.arc(ORIGIN, volume, p, p, 1), "straight ahead")

        p = Vector3.new(0, 0, 5)
        a.isFalse(Overlap.arc(ORIGIN, volume, p, p, 1), "straight behind")
    end)

    t:case("arc overlap widens by the target's angular size", function(a)
        -- THE CASE A NAIVE IMPLEMENTATION GETS WRONG. A 90-degree arc reaches
        -- 45 degrees either side. A body of radius 1 at distance 5 subtends
        -- asin(1/5) = 11.54 degrees, so its edge reaches that much past its
        -- centre.
        local volume = { shape = "ARC", radius = 10, angle = 90 }

        -- 50 - 11.54 = 38.46, inside 45. The centre is out; the body is not.
        local p = offAxis(50, 5)
        a.isTrue(Overlap.arc(ORIGIN, volume, p, p, 1),
            "centre beyond the arc edge, body inside it")

        -- 60 - 11.54 = 48.46, outside 45.
        local q = offAxis(60, 5)
        a.isFalse(Overlap.arc(ORIGIN, volume, q, q, 1),
            "far enough out that even the body misses")

        -- A point-sized target gets no widening at all.
        a.isFalse(Overlap.arc(ORIGIN, volume, p, p, 0),
            "with no radius, 50 degrees is simply outside 45")
    end)

    t:case("arc overlap always hits when the attacker is inside the target", function(a)
        -- Standing inside a boss, every direction to its centre is
        -- arbitrary. Facing must not get to decide this.
        local volume = { shape = "ARC", radius = 10, angle = 45 }
        local p = Vector3.new(0, 0, 2)
        a.isTrue(Overlap.arc(ORIGIN, volume, p, p, 8),
            "target centre is behind, but the attacker is inside its body")
    end)

    t:case("a 360 degree arc hits in every direction", function(a)
        local volume = { shape = "ARC", radius = 10, angle = 360 }
        local p

        p = Vector3.new(0, 0, 5)
        a.isTrue(Overlap.arc(ORIGIN, volume, p, p, 1), "behind")

        p = Vector3.new(5, 0, 0)
        a.isTrue(Overlap.arc(ORIGIN, volume, p, p, 1), "beside")

        p = Vector3.new(0, 0, 20)
        a.isFalse(Overlap.arc(ORIGIN, volume, p, p, 1), "still bounded by radius")
    end)

    -- ARC against genuinely capsule-shaped targets ---------------------------

    t:case("arc overlap catches a capsule whose ENDS are outside the cone", function(a)
        -- THE CASE THAT FAILS IF ONLY ENDPOINTS ARE TESTED. A 40-degree arc
        -- reaches 20 degrees either side. This capsule runs across the front
        -- of the swing at z = -6; its endpoints sit at +/-45 degrees off the
        -- axis, far outside the cone -- but its middle is dead ahead.
        local volume = { shape = "ARC", radius = 10, angle = 40 }

        local left = Vector3.new(-6, 0, -6)
        local right = Vector3.new(6, 0, -6)

        a.isTrue(Overlap.arc(ORIGIN, volume, left, right, 0.5),
            "both ends outside the cone, the belly of the capsule is inside it")

        -- Both endpoints alone must genuinely miss, or the assertion above
        -- proves nothing about the nearest-point candidate.
        a.isFalse(Overlap.arc(ORIGIN, volume, left, left, 0.5), "left end alone")
        a.isFalse(Overlap.arc(ORIGIN, volume, right, right, 0.5), "right end alone")
    end)

    t:case("arc overlap catches a capsule reaching in from outside the range", function(a)
        -- One end 30 studs away and well out of a 10-stud arc; the other end
        -- inside it. Testing a midpoint or a centre would miss this.
        local volume = { shape = "ARC", radius = 10, angle = 90 }

        local outside = Vector3.new(0, 0, -30)
        local inside = Vector3.new(0, 0, -4)

        a.isTrue(Overlap.arc(ORIGIN, volume, outside, inside, 0.5), "near end inside")
        a.isFalse(Overlap.arc(ORIGIN, volume, outside, outside, 0.5), "far end alone")
    end)

    t:case("arc overlap rejects a capsule that is entirely behind", function(a)
        local volume = { shape = "ARC", radius = 10, angle = 90 }
        a.isFalse(Overlap.arc(ORIGIN, volume,
            Vector3.new(-5, 0, 5), Vector3.new(5, 0, 5), 0.5),
            "a capsule lying across the attacker's back")
    end)

    t:case("arc overlap hits when the attacker stands on the capsule's segment", function(a)
        -- The apex-inside branch, with a real segment rather than a sphere.
        -- The capsule runs straight through the attacker from behind to in
        -- front, so facing is meaningless.
        local volume = { shape = "ARC", radius = 10, angle = 30 }
        a.isTrue(Overlap.arc(ORIGIN, volume,
            Vector3.new(-8, 0, 0), Vector3.new(8, 0, 0), 2),
            "attacker is inside the capsule's tube")
    end)

    -- BOX --------------------------------------------------------------------

    t:case("box overlap clamps to the nearest face", function(a)
        local volume = { shape = "BOX", size = Vector3.new(4, 4, 4) }
        local p

        p = Vector3.zero
        a.isTrue(Overlap.box(ORIGIN, volume, p, p, 0.1), "dead centre")

        p = Vector3.new(2.4, 0, 0)
        a.isTrue(Overlap.box(ORIGIN, volume, p, p, 0.5),
            "0.4 outside the face, radius 0.5 reaches it")

        p = Vector3.new(3, 0, 0)
        a.isFalse(Overlap.box(ORIGIN, volume, p, p, 0.5),
            "1.0 outside the face, radius 0.5 does not")
    end)

    t:case("box overlap respects rotation", function(a)
        -- A 2x2x10 box points down its own Z. Rotated 90 degrees about Y it
        -- extends along world X instead. An axis-aligned implementation
        -- passes the first assertion and fails the second.
        local volume = { shape = "BOX", size = Vector3.new(2, 2, 10) }
        local rotated = CFrame.Angles(0, math.rad(90), 0)
        local p

        p = Vector3.new(4, 0, 0)
        a.isTrue(Overlap.box(rotated, volume, p, p, 0.5),
            "along the box's long axis after rotation")

        p = Vector3.new(0, 0, 4)
        a.isFalse(Overlap.box(rotated, volume, p, p, 0.5),
            "along where the long axis USED to be")
    end)

    t:case("box overlap catches a capsule passing through it", function(a)
        -- THE CASE THAT NEEDS THE SEGMENT. Both endpoints are far outside a
        -- 4x4x4 box, but the segment skewers it. Testing endpoints, midpoints
        -- or centres all miss at least one arrangement of this.
        local volume = { shape = "BOX", size = Vector3.new(4, 4, 4) }

        a.isTrue(Overlap.box(ORIGIN, volume,
            Vector3.new(-20, 0, 0), Vector3.new(20, 0, 0), 0.25),
            "skewered along X")

        a.isTrue(Overlap.box(ORIGIN, volume,
            Vector3.new(-20, -20, 0), Vector3.new(20, 20, 0), 0.25),
            "skewered diagonally")

        a.isFalse(Overlap.box(ORIGIN, volume,
            Vector3.new(-20, 6, 0), Vector3.new(20, 6, 0), 0.25),
            "parallel and 6 above a box that reaches to 2")
    end)

    t:case("box overlap uses the volume's offset", function(a)
        -- `offset` was declared, validated and reach-accounted from the day
        -- HitVolume was written, and ignored by Overlap until 2026-08-16 --
        -- so a cleave declared four studs forward resolved centred on the
        -- attacker. This is the case that would have caught it.
        local volume = {
            shape = "BOX",
            size = Vector3.new(4, 4, 4),
            offset = CFrame.new(0, 0, -10),
        }
        local p

        p = Vector3.new(0, 0, -10)
        a.isTrue(Overlap.test(ORIGIN, volume, p, p, 0.5), "at the offset centre")

        p = Vector3.zero
        a.isFalse(Overlap.test(ORIGIN, volume, p, p, 0.5),
            "at the ANCHOR, which the volume has moved away from")
    end)

    -- CAPSULE ----------------------------------------------------------------

    t:case("capsule overlap measures to the nearest point on the segment", function(a)
        local volume = { shape = "CAPSULE", length = 10, radius = 1 }
        local p

        p = Vector3.new(0, 0, -5)
        a.isTrue(Overlap.capsule(ORIGIN, volume, p, p, 1), "on the line")

        p = Vector3.new(0, 1.5, -5)
        a.isTrue(Overlap.capsule(ORIGIN, volume, p, p, 1),
            "1.5 off the line, radii sum to 2")

        p = Vector3.new(0, 3, -5)
        a.isFalse(Overlap.capsule(ORIGIN, volume, p, p, 1), "3 off the line")

        p = Vector3.new(0, 0, -15)
        a.isFalse(Overlap.capsule(ORIGIN, volume, p, p, 1), "past the far end")
    end)

    t:case("capsule overlap detects what it starts inside", function(a)
        -- Unlike a raycast, which would not. A thrust that begins inside an
        -- enemy already standing on top of you has to register.
        local volume = { shape = "CAPSULE", length = 10, radius = 1 }
        a.isTrue(Overlap.capsule(ORIGIN, volume, Vector3.zero, Vector3.zero, 1),
            "at the origin")
    end)

    t:case("capsule overlap handles two crossing segments", function(a)
        -- Segment-to-segment, which is the case the point version could not
        -- express at all. A thrust down -Z against a target lying across it.
        local volume = { shape = "CAPSULE", length = 10, radius = 1 }

        a.isTrue(Overlap.capsule(ORIGIN, volume,
            Vector3.new(-6, 0, -5), Vector3.new(6, 0, -5), 0.5),
            "crossing the thrust at right angles, both ends well clear of it")

        a.isFalse(Overlap.capsule(ORIGIN, volume,
            Vector3.new(-6, 4, -5), Vector3.new(6, 4, -5), 0.5),
            "same crossing, lifted 4 clear of a 1.5 combined radius")
    end)

    t:case("capsule overlap handles PARALLEL segments", function(a)
        -- The degenerate branch: parallel segments make the closest-pair
        -- solve indeterminate, and without the guard it divides by zero and
        -- returns NaN -- which compares false and silently misses.
        local volume = { shape = "CAPSULE", length = 10, radius = 1 }

        a.isTrue(Overlap.capsule(ORIGIN, volume,
            Vector3.new(0, 1.5, -2), Vector3.new(0, 1.5, -8), 1),
            "running alongside the thrust, 1.5 apart, radii sum to 2")

        a.isFalse(Overlap.capsule(ORIGIN, volume,
            Vector3.new(0, 4, -2), Vector3.new(0, 4, -8), 1),
            "same, 4 apart")
    end)

    -- DISPATCH ---------------------------------------------------------------

    t:case("an unknown shape errors rather than quietly missing", function(a)
        -- A volume that never hits anything looks exactly like a balance
        -- problem, which is the worst possible disguise for a typo.
        a.throws(function()
            Overlap.test(ORIGIN, { shape = "TRAPEZOID" }, Vector3.zero, Vector3.zero, 1)
        end, "unknown shape")

        a.isTrue(Overlap.supports("ARC"))
        a.isFalse(Overlap.supports("TRAPEZOID"))
    end)

    return t:run()
end
