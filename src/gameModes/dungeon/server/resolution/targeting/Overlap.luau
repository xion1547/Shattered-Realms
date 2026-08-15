-- src/gameModes/dungeon/server/resolution/targeting/Overlap.luau
--
-- PURE MATH. No requires, no state, no engine calls. See HitDetection.md.
--
-- Every function answers one question: does a SPHERE of `radius` centred on
-- `point` overlap this volume, placed at `origin`?
--
-- THE TARGET IS ALWAYS A SPHERE, and that is the decision the whole file
-- rests on. A sphere is rotation-invariant, so none of these tests care
-- which way the target is facing -- which means none of them need separating
-- axis tests, and none of them get more expensive when the target is
-- rewound to an old orientation. Volume-vs-box would need SAT per candidate
-- per sample; volume-vs-sphere is closed form every time.
--
-- SQUARED DISTANCES THROUGHOUT. Comparing d^2 against r^2 is the same test
-- as comparing d against r, without the square root. These run once per
-- candidate per sample.

local Overlap = {}

-- SPHERE ---------------------------------------------------------------
--
-- The simplest case, and the one every other shape degenerates to when its
-- defining dimension goes to zero.
function Overlap.sphere(origin: CFrame, volume, point: Vector3, radius: number): boolean
    local delta = point - origin.Position
    local reach = volume.radius + radius
    return delta:Dot(delta) <= reach * reach
end

-- BOX (oriented) -------------------------------------------------------
--
-- Transform the target's centre into the box's own space, clamp it to the
-- box extents, and measure how far the real centre is from that clamped
-- point. That distance is exactly the distance from the sphere's centre to
-- the nearest point on the box -- which is the definition of the test.
--
-- Works for a rotated box for free, because PointToObjectSpace already
-- undid the rotation. There is no separate axis-aligned path.
function Overlap.box(origin: CFrame, volume, point: Vector3, radius: number): boolean
    local localPoint = origin:PointToObjectSpace(point)
    local half = volume.size * 0.5

    local clamped = Vector3.new(
        math.clamp(localPoint.X, -half.X, half.X),
        math.clamp(localPoint.Y, -half.Y, half.Y),
        math.clamp(localPoint.Z, -half.Z, half.Z))

    local delta = localPoint - clamped
    return delta:Dot(delta) <= radius * radius
end

-- ARC (cone) -----------------------------------------------------------
--
-- The standard melee swing: everything within `radius`, inside `angle`
-- degrees of where the attacker is facing.
--
-- THE SPHERE'S OWN RADIUS PARTICIPATES IN THE ANGLE TEST, and skipping that
-- is the classic bug. Testing only whether the target's CENTRE is inside the
-- cone means a boss whose centre sits just outside the arc is missed
-- entirely, even when ten studs of its body are inside it. So the target's
-- angular half-width -- asin(radius / distance) -- is subtracted from the
-- angle to its centre before the comparison.
--
-- The full angle is the total sweep, so it is halved here. A 90-degree arc
-- reaches 45 degrees either side of centre, which is what a designer typing
-- `angle = 90` means.
function Overlap.arc(origin: CFrame, volume, point: Vector3, radius: number): boolean
    local toTarget = point - origin.Position
    local distanceSquared = toTarget:Dot(toTarget)

    local reach = volume.radius + radius
    if distanceSquared > reach * reach then
        return false
    end

    local distance = math.sqrt(distanceSquared)

    -- The attacker is standing inside the target. There is no meaningful
    -- direction to the centre, and every answer to "which way is it" is
    -- arbitrary -- so it hits, regardless of facing.
    if distance <= radius then
        return true
    end

    local angleToCentre = math.acos(math.clamp(toTarget.Unit:Dot(origin.LookVector), -1, 1))
    local angularHalfWidth = math.asin(math.clamp(radius / distance, -1, 1))

    return (angleToCentre - angularHalfWidth) <= math.rad(volume.angle) * 0.5
end

-- CAPSULE --------------------------------------------------------------
--
-- A thrust, beam, or dash: a line segment from the origin along its facing,
-- with thickness. Closest point on the segment, then a sphere test against
-- it.
--
-- Note this is a swept sphere, NOT a raycast -- it detects targets it
-- starts already touching. A raycast would not, and a thrust that begins
-- inside an enemy already standing on top of you is exactly the case that
-- has to register.
function Overlap.capsule(origin: CFrame, volume, point: Vector3, radius: number): boolean
    local start = origin.Position
    local axis = origin.LookVector * volume.length

    local axisLengthSquared = axis:Dot(axis)
    local closest
    if axisLengthSquared <= 0 then
        closest = start
    else
        local t = math.clamp((point - start):Dot(axis) / axisLengthSquared, 0, 1)
        closest = start + axis * t
    end

    local delta = point - closest
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

function Overlap.test(origin: CFrame, volume, point: Vector3, radius: number): boolean
    local fn = BY_SHAPE[volume.shape]
    if not fn then
        error(string.format("[Overlap] unknown shape: %s", tostring(volume.shape)), 0)
    end
    return fn(origin, volume, point, radius)
end

function Overlap.supports(shape: string): boolean
    return BY_SHAPE[shape] ~= nil
end

return Overlap
