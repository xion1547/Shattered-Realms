-- src/gameModes/dungeon/server/diagnostics/SwingReport.luau
--
-- TEMPORARY, like PingProbe. One structured block per swing, so every stage
-- of DETECT can be checked against what it was designed to do instead of
-- inferred from whether a hit happened.
--
-- WHY THIS EXISTS AT ALL: nearly every failure in this layer is SILENT. A
-- wrong ping unit made lag compensation a no-op and nothing errored. A buffer
-- too short makes poseAt clamp and return a real position from the wrong
-- moment. A broadphase that culls nothing still returns correct hits. None of
-- those show up as a missing goblin -- they show up as a game that feels
-- slightly wrong months later. This prints the numbers that would have caught
-- each one.
--
-- IT REPORTS MISSES, NOT JUST HITS, and that is the point of the per-target
-- block. "Three hit" tells you nothing about the four that did not, and
-- "why did that one miss" is the only question anyone actually asks. Every
-- candidate the broadphase passed gets a line with the distance, the angle
-- and the limit each was compared against, so a wrong result can be
-- hand-checked instead of argued about.
--
-- READ IT LIKE THIS, in the order the stages run:
--
--   rewind exactly 0.1000s  -> the ping is contributing nothing and only
--                              INTERPOLATION_CONSTANT is left. That is the
--                              signature of the 1000x unit bug -- BUT it is
--                              also simply true in a solo Studio session,
--                              where GetNetworkPing genuinely returns 0.
--                              Only meaningful under Team Test or a real
--                              server, where it should read ~0.11-0.13.
--   origin nil              -> the attacker has no body. Nothing else can
--                              work; check the character attach.
--   broadphase N of N       -> the cull is passing everything. Correct when
--                              every dummy is genuinely in range, suspicious
--                              when they are not.
--   rewound == nil          -> poseAt found no samples at all.
--   CLAMPING                -> the buffer does not reach as far back as the
--                              rewind wants. Every hit is resolving against
--                              the oldest sample, at the wrong moment. This
--                              is the failure the HISTORY_SECONDS split
--                              exists to keep away, and it is printed in
--                              capitals because nothing else reveals it.
--   drift 0.00 everywhere   -> expected against anchored dummies. Rewind is
--                              RUNNING but is not being TESTED -- only a
--                              moving target proves it.

local serverRoot = script.Parent.Parent

local targeting = serverRoot:WaitForChild("resolution"):WaitForChild("targeting")
local authority = serverRoot:WaitForChild("services"):WaitForChild("authority")

local HitVolume = require(targeting:WaitForChild("HitVolume"))
local TargetResolution = require(targeting:WaitForChild("TargetResolution"))
local SpatialService = require(authority:WaitForChild("SpatialService"))

local SwingReport = {}

local function vec(v: Vector3?): string
    if not v then
        return "nil"
    end
    return string.format("(%.1f, %.1f, %.1f)", v.X, v.Y, v.Z)
end

local function idsOf(entities): string
    if #entities == 0 then
        return "none"
    end
    local names = {}
    for _, entity in ipairs(entities) do
        table.insert(names, tostring(entity.identity:getId()))
    end
    return table.concat(names, ", ")
end

-- A deliberate second copy of Overlap's helper. A diagnostic that CALLED the
-- code under test would agree with it by construction, including when both
-- are wrong -- the whole value here is an independent second opinion.
local function closestOnSegment(a: Vector3, b: Vector3, p: Vector3): Vector3
    local ab = b - a
    local lengthSquared = ab:Dot(ab)
    if lengthSquared <= 0 then
        return a
    end
    return a + ab * math.clamp((p - a):Dot(ab) / lengthSquared, 0, 1)
end

local function describeVolume(volume): string
    local base
    if volume.shape == HitVolume.Shape.ARC then
        base = string.format("ARC radius=%g angle=%g", volume.radius, volume.angle)
    elseif volume.shape == HitVolume.Shape.SPHERE then
        base = string.format("SPHERE radius=%g", volume.radius)
    elseif volume.shape == HitVolume.Shape.CAPSULE then
        base = string.format("CAPSULE length=%g radius=%g", volume.length, volume.radius)
    else
        base = string.format("BOX size=%s", tostring(volume.size))
    end

    if volume.offset then
        base ..= string.format("  offset=%s", vec(volume.offset.Position))
    end
    if (volume.activeWindow or 0) > 0 then
        base ..= string.format("  window=%.3fs samples=%d",
            volume.activeWindow, volume.samples or 1)
    end
    return base
end

-- Per-candidate block: where it was, where it WAS, and the numbers the test
-- compared. Written so a wrong answer can be recomputed by hand from the
-- line itself.
local function reportCandidate(entity, origin: CFrame, volume, at: number, now: number, wasHit: boolean)
    local spatial = entity.spatial
    local id = tostring(entity.identity:getId())
    local mark = wasHit and "HIT " or "miss"

    local live = spatial and spatial:getCFrame()
    local rewound = spatial and spatial:poseAt(at)

    if not rewound then
        print(string.format("    %s %-10s rewound=nil -- no samples recorded yet", mark, id))
        return
    end

    local drift = live and (live.Position - rewound.Position).Magnitude or 0
    local oldest = spatial:span(now)
    local wanted = math.max(0, now - at)
    local clamping = oldest < wanted

    -- The hurtbox as the narrow phase saw it: at the REWOUND pose, because a
    -- capsule leans with the body.
    local capA, capB = spatial:endpoints(rewound)
    local radius = spatial.radius

    print(string.format("    %s %-10s live %s  rewound %s  drift %.2f",
        mark, id, vec(live and live.Position), vec(rewound.Position), drift))

    print(string.format("         %-10s capsule %s..%s  r=%.2f  halfHeight=%.2f",
        "", vec(capA), vec(capB), radius, spatial.halfHeight))

    -- Volume-relative geometry. The offset is applied first, exactly as
    -- Overlap.test does -- reporting against the un-offset anchor would make
    -- a correct cleave look broken.
    local volumeOrigin = volume.offset and (origin * volume.offset) or origin
    local apex = volumeOrigin.Position
    local nearest = closestOnSegment(capA, capB, apex)
    local distance = (nearest - apex).Magnitude

    if volume.shape == HitVolume.Shape.ARC then
        local reach = volume.radius + radius
        local limit = volume.angle * 0.5

        if distance <= radius then
            print(string.format(
                "         %-10s distance %.2f (reach %.2f)  attacker is INSIDE the body -- facing ignored",
                "", distance, reach))
        else
            local toNearest = (nearest - apex) / distance
            local angle = math.deg(math.acos(math.clamp(toNearest:Dot(volumeOrigin.LookVector), -1, 1)))
            local halfWidth = math.deg(math.asin(math.clamp(radius / distance, -1, 1)))
            local effective = angle - halfWidth

            -- NAMES WHICH TEST FAILED, because the two numbers are printed
            -- side by side and it is genuinely ambiguous otherwise: a target
            -- can be well inside the angle and simply too far away, which
            -- reads as an angle pass right next to a miss.
            local why = ""
            if not wasHit then
                if distance > reach then
                    why = "  <- OUT OF RANGE"
                elseif effective > limit then
                    why = "  <- OUT OF ANGLE"
                end
            end

            print(string.format(
                "         %-10s distance %.2f (reach %.2f)  angle %.1f -> %.1f after width (limit %.1f)%s",
                "", distance, reach, angle, effective, limit, why))
        end

    elseif volume.shape == HitVolume.Shape.BOX then
        -- DISTANCE FROM THE ORIGIN IS THE WRONG NUMBER FOR A BOX, and an
        -- earlier version of this report printed it anyway -- which is why a
        -- hit at "distance 8.64" sat next to a miss at "14.63" and explained
        -- nothing. A box has no radius; what matters is how far the hurtbox
        -- sits OUTSIDE the box's faces.
        local half = volume.size * 0.5
        local localA = volumeOrigin:PointToObjectSpace(capA)
        local localB = volumeOrigin:PointToObjectSpace(capB)
        local nearestLocal = closestOnSegment(localA, localB, Vector3.zero)
        local clamped = Vector3.new(
            math.clamp(nearestLocal.X, -half.X, half.X),
            math.clamp(nearestLocal.Y, -half.Y, half.Y),
            math.clamp(nearestLocal.Z, -half.Z, half.Z))
        local gap = (nearestLocal - clamped).Magnitude

        print(string.format(
            "         %-10s box-local %s  half-extents %s  gap %.2f (radius %.2f)%s",
            "", vec(nearestLocal), vec(half), gap, radius,
            (not wasHit and gap > radius) and "  <- OUTSIDE THE BOX" or ""))

    elseif volume.shape == HitVolume.Shape.CAPSULE then
        -- Segment to segment, by two rounds of alternating projection --
        -- close enough for a report, and deliberately NOT the routine Overlap
        -- uses, so this stays an independent second opinion.
        local vStart = volumeOrigin.Position
        local vEnd = vStart + volumeOrigin.LookVector * volume.length
        local onVolume = closestOnSegment(vStart, vEnd, (capA + capB) * 0.5)
        local onTarget = closestOnSegment(capA, capB, onVolume)
        onVolume = closestOnSegment(vStart, vEnd, onTarget)

        local gap = (onVolume - onTarget).Magnitude
        local reach = volume.radius + radius

        print(string.format(
            "         %-10s blade %s..%s  gap %.2f (radii sum %.2f)%s",
            "", vec(vStart), vec(vEnd), gap, reach,
            (not wasHit and gap > reach) and "  <- BLADE PASSED CLEAR" or ""))

    else
        print(string.format("         %-10s distance %.2f to nearest point on the hurtbox",
            "", distance))
    end

    if clamping then
        print(string.format(
            "         %-10s *** CLAMPING: buffer reaches %.2fs back, rewind wants %.2fs ***",
            "", oldest, wanted))
    end
end

-- `query` must be the SAME query object that produced `hits`, or the
-- broadphase figure below describes a different swing than the result does.
--
-- The event id is printed so a line here can be matched to the line
-- InputSystem printed when it sent -- which is what proves the wire, rather
-- than assuming it because something arrived.
function SwingReport.report(player: Player, event, query, hits)
    local now = workspace:GetServerTimeNow()

    local roundTrip = SpatialService:roundTripOf(player)
    local rewind = SpatialService:rewindWindowFor(player)
    local constants = SpatialService:constants()

    print(string.format("[Swing] %s  event=%s  subType=%s",
        player.Name, tostring(event:getEventId()), tostring(event:getSubType())))

    print(string.format(
        "    clock      now %.3f  resolving at %.3f  (%.4fs in the past)",
        now, query.at, now - query.at))

    print(string.format(
        "    latency    roundTrip %.4fs  rewind %.4fs  (ceiling %.2fs, interp %.2fs, pingx%d)",
        roundTrip, rewind, constants.maxRewind, constants.interpolationConstant,
        constants.pingToRoundTrip))

    local origin = TargetResolution.originOf(query)
    if not origin then
        print("    origin     nil -- the attacker has no body; nothing downstream can run")
        return
    end

    print(string.format("    origin     %s  facing %s",
        vec(origin.Position), vec(origin.LookVector)))

    print(string.format("    volume     %s  maxTargets=%s  reach=%.1f",
        describeVolume(query.volume),
        tostring(query.volume.maxTargets),
        HitVolume.reach(query.volume)))

    -- Recomputed with the same inputs TargetResolution uses, so the number
    -- reported is the number the cull actually saw.
    local window = math.max(0, now - query.at) + (query.volume.activeWindow or 0)
    local margin = TargetResolution.constants().maxEntitySpeed * window
    local candidates = SpatialService:candidatesNear(
        origin.Position, HitVolume.reach(query.volume), margin)

    print(string.format(
        "    broadphase %d of %d attached passed the cull  (margin %.1f studs)",
        #candidates, SpatialService:attachedCount(), margin))

    print(string.format("    narrow     %d hit: %s", #hits, idsOf(hits)))

    if query.preferredId ~= nil then
        local matched = #hits > 0 and tostring(hits[1].identity:getId()) == tostring(query.preferredId)
        print(string.format("    preferred  %s -- %s",
            tostring(query.preferredId),
            matched and "in the set, sorted first" or "not in the resolved set, ignored"))
    end

    -- Every candidate, hit or not. A set lookup so the mark is O(1) rather
    -- than a scan per candidate -- irrelevant at this size, but this runs
    -- inside a combat path and copying a bad habit here is how it spreads.
    local isHit = {}
    for _, entity in ipairs(hits) do
        isHit[entity] = true
    end

    for _, entity in ipairs(candidates) do
        if entity ~= query.attacker then
            reportCandidate(entity, origin, query.volume, query.at, now, isHit[entity] == true)
        end
    end
end

return SwingReport
