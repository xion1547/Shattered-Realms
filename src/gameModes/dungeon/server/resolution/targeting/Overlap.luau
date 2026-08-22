-- src/gameModes/dungeon/server/resolution/targeting/Overlap.luau
--
-- PURE MATH. No requires, no state, no engine calls. See HitDetection.md §7.
--
-- Every function answers one question: does a CAPSULE -- the segment from `a`
-- to `b`, thickened by `radius` -- overlap this volume, placed at `origin`?
--
-- THE TARGET IS A CAPSULE, and that is the decision the whole file rests on.
-- A capsule has a RADIUS, and having a radius is what keeps the arc test both
-- exact and cheap: `asin(radius / distance)` gives the target's angular
-- half-width in one step (see Overlap.arc). An oriented box has no radius, so
-- the same test degrades to sampling eight corners and approximating in all
-- three dimensions. That is why an earlier revision of this file targeted
-- boxes and was reversed -- HitDetection.md §7.0.1 carries the argument.
--
-- A SPHERE TARGET IS THE DEGENERATE CASE: pass `a == b` and the segment has
-- zero length, so every function below collapses to the sphere behaviour this
-- file used to have. Nothing special-cases it.
--
-- SQUARED DISTANCES WHEREVER POSSIBLE. Comparing d^2 against r^2 is the same
-- test as comparing d against r, without the square root. These run once per
-- candidate per sample, so the square roots that DO survive are the ones the
-- angle test genuinely needs.
--
-- NOTHING HERE ALLOCATES. No tables, no closures, per call. The three
-- candidate points in `arc` are three calls to a file-local function rather
-- than a loop over an array, for exactly that reason.

local Overlap = {}

-- GEOMETRY HELPERS ------------------------------------------------------

-- The point on segment `a`->`b` nearest to `p`.
--
-- `t` is how far along the segment the answer sits: 0 is `a`, 1 is `b`.
-- It comes from projecting `ap` onto `ab`:
--
--     t = (ap . ab) / (ab . ab)
--
-- A dot product is |u||v|cos(angle), so `ap . ab` is the length of ap's
-- SHADOW along ab, scaled by |ab|. Dividing by |ab| once makes it a real
-- length; dividing again expresses it as a fraction of the segment. Two
-- divisions by |ab| is one division by |ab|^2, which is `ab . ab` -- so the
-- formula never takes a square root.
--
-- CLAMPING TO [0,1] IS WHAT MAKES IT A SEGMENT. Without it this returns the
-- nearest point on the infinite LINE, which for a capsule is a point outside
-- the body entirely.
local function closestPointOnSegment(a: Vector3, b: Vector3, p: Vector3): Vector3
    local ab = b - a
    local lengthSquared = ab:Dot(ab)

    -- Zero-length segment: the caller passed a sphere. Also the guard that
    -- keeps the division below from producing NaN.
    if lengthSquared <= 0 then
        return a
    end

    local t = math.clamp((p - a):Dot(ab) / lengthSquared, 0, 1)
    return a + ab * t
end

-- Is point `p` inside the cone with apex `apex`, axis `look`, half-angle
-- `halfAngle` and squared reach `reachSquared`, given that the body around
-- `p` has thickness `radius`?
--
-- THE ANGULAR HALF-WIDTH IS THE WHOLE POINT, and skipping it is the classic
-- bug. Testing only whether the target's CENTRE is inside the cone misses a
-- boss whose centre sits just outside the arc while ten studs of its body are
-- inside it.
--
-- Where asin comes from: draw the triangle from the apex to the body's centre
-- (length d) and from the apex to where a line just grazes the body's
-- surface. A tangent touches perpendicular to the radius, so that triangle is
-- right-angled with hypotenuse d and opposite side `radius`:
--
--     sin(halfWidth) = radius / d      ->      halfWidth = asin(radius / d)
--
-- CALLERS MUST HAVE ALREADY RULED OUT the apex being inside the body. If they
-- have, then d > radius for every point on the segment, so `radius / d` is
-- below 1 and asin is defined. The clamps below are for floating point drift
-- at the boundary, not for that case.
local function withinCone(
    apex: Vector3,
    look: Vector3,
    halfAngle: number,
    reachSquared: number,
    radius: number,
    p: Vector3
): boolean
    local toP = p - apex
    local distanceSquared = toP:Dot(toP)

    if distanceSquared > reachSquared then
        return false
    end

    -- A zero-thickness target sitting exactly on the apex. No direction to
    -- measure, and the divide below would produce NaN.
    if distanceSquared <= 0 then
        return true
    end

    local distance = math.sqrt(distanceSquared)

    -- `toP / distance` rather than `toP.Unit`: .Unit recomputes the magnitude,
    -- and we already paid for it.
    local direction = toP / distance

    -- Two unit vectors dotted give the cosine of the angle between them.
    -- CLAMPED because floating point can return 1.0000001 here, and acos of
    -- that is NaN -- which compares false against everything and would make
    -- the hit silently vanish rather than error.
    local angleToPoint = math.acos(math.clamp(direction:Dot(look), -1, 1))
    local halfWidth = math.asin(math.clamp(radius / distance, -1, 1))

    return (angleToPoint - halfWidth) <= halfAngle
end

-- SPHERE ---------------------------------------------------------------
--
-- A capsule is every point within `radius` of its segment, and a sphere
-- volume is every point within `volume.radius` of its centre. So they touch
-- exactly when the segment comes within the SUM of the two radii -- which is
-- one point-to-segment distance and one comparison.
function Overlap.sphere(origin: CFrame, volume, a: Vector3, b: Vector3, radius: number): boolean
    local centre = origin.Position
    local nearest = closestPointOnSegment(a, b, centre)
    local delta = nearest - centre
    local reach = volume.radius + radius
    return delta:Dot(delta) <= reach * reach
end

-- ARC (cone) -----------------------------------------------------------
--
-- The standard melee swing: everything within `radius`, inside `angle`
-- degrees of where the attacker is facing.
--
-- The full angle is the total sweep, so it is halved here. A 90-degree arc
-- reaches 45 degrees either side of centre, which is what a designer typing
-- `angle = 90` means.
--
-- THREE CANDIDATE POINTS, not one. The angle from the axis to a point sliding
-- along the segment varies smoothly and has a single minimum, which sits
-- either at an end or somewhere in the middle. `a` and `b` catch the ends;
-- `nearest` catches the case that fails without it -- a long capsule lying
-- across the front of the swing, where neither endpoint is inside the cone
-- but its belly is.
--
-- This is the one approximation in this file and HitDetection.md §7.4 names
-- it: exact in the radial direction (the asin term handles thickness
-- precisely), approximate along the segment.
function Overlap.arc(origin: CFrame, volume, a: Vector3, b: Vector3, radius: number): boolean
    local apex = origin.Position
    local look = origin.LookVector
    local reach = volume.radius + radius
    local reachSquared = reach * reach
    local halfAngle = math.rad(volume.angle) * 0.5

    -- Cheapest rejection first, and it produces the third candidate as a
    -- side effect rather than as extra work.
    local nearest = closestPointOnSegment(a, b, apex)
    local toNearest = nearest - apex
    local nearestDistanceSquared = toNearest:Dot(toNearest)

    if nearestDistanceSquared > reachSquared then
        return false
    end

    -- THE ATTACKER IS STANDING INSIDE THE TARGET. Every answer to "which way
    -- is it" is arbitrary, so it hits regardless of facing.
    --
    -- This also establishes the precondition withinCone relies on: past this
    -- line, every point on the segment is further than `radius` from the
    -- apex, so `radius / distance` is below 1 and asin is well defined.
    if nearestDistanceSquared <= radius * radius then
        return true
    end

    return withinCone(apex, look, halfAngle, reachSquared, radius, a)
        or withinCone(apex, look, halfAngle, reachSquared, radius, b)
        or withinCone(apex, look, halfAngle, reachSquared, radius, nearest)
end

-- BOX (oriented) -------------------------------------------------------
--
-- Everything happens in the box's OBJECT SPACE, where the box is axis-aligned
-- and centred on the origin -- so an oriented box needs no separate code path
-- and no separating-axis test. `PointToObjectSpace` is a rigid transform
-- (rotation plus translation), so it preserves distances: a distance measured
-- in local space is the same number in world space.
--
-- SEGMENT-TO-BOX DISTANCE BY ALTERNATING PROJECTION. The exact closed form
-- needs case analysis over faces, edges and corners -- roughly fifty lines
-- with several ways to get an edge case subtly wrong. Instead: guess a point,
-- snap it into the box, snap that back onto the segment, repeat. Both shapes
-- are convex, so each step can only ever shorten the distance, and it settles
-- on the true closest pair within a few passes at these scales.
--
-- If the segment passes THROUGH the box it converges on the first pass: the
-- clamp returns the point unchanged, the distance is zero, and the test
-- passes. No special case needed.
local BOX_REFINEMENTS = 4

local function clampIntoBox(p: Vector3, half: Vector3): Vector3
    return Vector3.new(
        math.clamp(p.X, -half.X, half.X),
        math.clamp(p.Y, -half.Y, half.Y),
        math.clamp(p.Z, -half.Z, half.Z))
end

function Overlap.box(origin: CFrame, volume, a: Vector3, b: Vector3, radius: number): boolean
    local half = volume.size * 0.5
    local localA = origin:PointToObjectSpace(a)
    local localB = origin:PointToObjectSpace(b)

    -- Starting from the midpoint rather than an endpoint: it is the guess
    -- least likely to be on the wrong side of the box for a segment that
    -- straddles it.
    local onSegment = (localA + localB) * 0.5
    local inBox = clampIntoBox(onSegment, half)

    for _ = 1, BOX_REFINEMENTS do
        onSegment = closestPointOnSegment(localA, localB, inBox)
        inBox = clampIntoBox(onSegment, half)
    end

    local delta = onSegment - inBox
    return delta:Dot(delta) <= radius * radius
end

-- CAPSULE --------------------------------------------------------------
--
-- A thrust, beam, or dash: a segment from the origin along its facing, with
-- thickness. Against a capsule target this is segment-to-segment distance
-- compared against the summed radii -- the cleanest of the four, because two
-- capsules are the same kind of object and the test is symmetric.
--
-- Note this is a swept volume, NOT a raycast -- it detects targets it starts
-- already touching. A raycast would not, and a thrust that begins inside an
-- enemy already standing on top of you is exactly the case that has to
-- register.

local EPSILON = 1e-8

-- The classic segment-segment closest-pair routine (Ericson, *Real-Time
-- Collision Detection*). Written out rather than approximated because the
-- degenerate cases are the whole difficulty and each one is a real shape:
--
--   both segments are points        two spheres
--   one segment is a point          a sphere against a capsule
--   the segments are PARALLEL       `denom` is zero and `s` is unconstrained,
--                                   so pick an end and let the clamps below
--                                   find the answer -- without this branch it
--                                   divides by zero and returns NaN, which
--                                   compares false and silently misses
--
-- `s` and `t` are positions along each segment in [0,1], the same parameter
-- `closestPointOnSegment` computes for the simpler one-segment case.
local function closestPointsBetweenSegments(
    p1: Vector3, q1: Vector3,
    p2: Vector3, q2: Vector3
): (Vector3, Vector3)
    local d1 = q1 - p1
    local d2 = q2 - p2
    local r = p1 - p2

    local a = d1:Dot(d1)
    local e = d2:Dot(d2)
    local f = d2:Dot(r)

    if a <= EPSILON and e <= EPSILON then
        return p1, p2
    end

    local s, t

    if a <= EPSILON then
        s = 0
        t = math.clamp(f / e, 0, 1)
    else
        local c = d1:Dot(r)
        if e <= EPSILON then
            t = 0
            s = math.clamp(-c / a, 0, 1)
        else
            local b = d1:Dot(d2)
            local denom = a * e - b * b

            if denom > EPSILON then
                s = math.clamp((b * f - c * e) / denom, 0, 1)
            else
                s = 0
            end

            t = (b * s + f) / e

            -- `t` left its segment, so pin it and re-solve `s` against the
            -- pinned end. Skipping this is the classic bug: it returns a
            -- closest pair that is not on either segment.
            if t < 0 then
                t = 0
                s = math.clamp(-c / a, 0, 1)
            elseif t > 1 then
                t = 1
                s = math.clamp((b - c) / a, 0, 1)
            end
        end
    end

    return p1 + d1 * s, p2 + d2 * t
end

function Overlap.capsule(origin: CFrame, volume, a: Vector3, b: Vector3, radius: number): boolean
    local start = origin.Position
    local finish = start + origin.LookVector * volume.length

    local onVolume, onTarget = closestPointsBetweenSegments(start, finish, a, b)

    local delta = onVolume - onTarget
    local reach = volume.radius + radius
    return delta:Dot(delta) <= reach * reach
end

-- DISPATCH -------------------------------------------------------------
--
-- A table rather than an if-chain so that adding a shape is one entry and
-- one function, and so an unknown shape fails loudly at the call site
-- rather than silently returning false -- a volume that never hits anything
-- is a bug that looks exactly like a balance problem.
local BY_SHAPE = {
    SPHERE = Overlap.sphere,
    BOX = Overlap.box,
    ARC = Overlap.arc,
    CAPSULE = Overlap.capsule,
}

-- `a` and `b` are the target capsule's segment endpoints IN WORLD SPACE, and
-- `radius` is its thickness. Converting a hitzone's part CFrame and local
-- axis into those two points is TargetResolution's job -- this file knows
-- nothing about hitzones, parts or entities.
function Overlap.test(origin: CFrame, volume, a: Vector3, b: Vector3, radius: number): boolean
    local fn = BY_SHAPE[volume.shape]
    if not fn then
        error(string.format("[Overlap] unknown shape: %s", tostring(volume.shape)), 0)
    end

    -- `offset` DISPLACES THE VOLUME FROM ITS ANCHOR, in the anchor's own local
    -- space -- so `CFrame.new(0, 0, -4)` is "four studs in front of me",
    -- whichever way I am facing, and it rotates with me.
    --
    -- APPLIED HERE RATHER THAN IN EACH SHAPE, so every shape gets it for free
    -- and none of them can forget. Until 2026-08-16 the field was declared in
    -- HitVolume, validated by HitVolume.validate, and accounted for in
    -- HitVolume.reach -- and then silently ignored by the only code that
    -- decides whether anything is hit. A cleave declared four studs forward
    -- resolved centred on the attacker, and every part of the system except
    -- this one agreed it should not have.
    if volume.offset then
        origin = origin * volume.offset
    end

    return fn(origin, volume, a, b, radius)
end

function Overlap.supports(shape: string): boolean
    return BY_SHAPE[shape] ~= nil
end

return Overlap
