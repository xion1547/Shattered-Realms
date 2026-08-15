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
--   buffer span < rewind    -> poseAt is CLAMPING. Hits resolve against the
--                              oldest sample. This is the failure the
--                              HISTORY_SECONDS split exists to keep away.

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

local function describeVolume(volume): string
    if volume.shape == HitVolume.Shape.ARC then
        return string.format("ARC radius=%g angle=%g", volume.radius, volume.angle)
    elseif volume.shape == HitVolume.Shape.SPHERE then
        return string.format("SPHERE radius=%g", volume.radius)
    elseif volume.shape == HitVolume.Shape.CAPSULE then
        return string.format("CAPSULE length=%g radius=%g", volume.length, volume.radius)
    end
    return string.format("BOX size=%s", tostring(volume.size))
end

-- Per-target line: did the rewind move anything, and did the buffer reach.
local function reportTarget(entity, at: number, now: number)
    local spatial = entity.spatial
    local id = tostring(entity.identity:getId())

    local live = spatial and spatial:getCFrame()
    local rewound = spatial and spatial:poseAt(at)

    if not rewound then
        print(string.format("    %-10s rewound=nil -- no samples recorded yet", id))
        return
    end

    local oldest = spatial:span(now)
    local drift = live and (live.Position - rewound.Position).Magnitude or 0

    print(string.format(
        "    %-10s live %s  rewound %s  moved %.2f studs  buffer reaches %.2fs back",
        id, vec(live and live.Position), vec(rewound.Position), drift, oldest))
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
        "    latency    roundTrip %.4fs  rewind %.4fs  (ceiling %.2fs, interp %.2fs)",
        roundTrip, rewind, constants.maxRewind, constants.interpolationConstant))

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

    for _, entity in ipairs(hits) do
        reportTarget(entity, query.at, now)
    end
end

return SwingReport
