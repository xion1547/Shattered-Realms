-- src/gameModes/dungeon/server/diagnostics/SweepTrace.luau
--
-- TEMPORARY. Records where the BLADE was and where every HURTBOX was, at each
-- sample of a swing, and prints the pair as a table when the swing ends.
--
-- WHY THIS IS NOT "TRACKING THE HITBOX". It is easy to read this file as
-- storing hitbox history, and it is not -- the distinction matters enough to
-- state twice:
--
--   A HURTBOX IS OBSERVED STATE. "Where was that body 100ms ago" is a real
--   question with a real answer, so it lives in a ring buffer and gets looked
--   up. That is SpatialService.
--
--   A HITBOX IS GENERATED DATA. It is a claim the attack makes, computed from
--   the attacker's pose plus the move's numbers at the instant it is needed.
--   "Where was the hitbox 100ms ago" is meaningless -- it did not exist. This
--   is how fighting games have always done it: hitbox geometry is part of the
--   MOVE's per-frame definition, not something tracked at runtime.
--
-- So nothing here is required for resolution. It is required for ARGUING with
-- resolution -- for putting the blade's position and the body's position side
-- by side with a number between them, so a wrong answer can be pointed at
-- instead of debated.
--
-- IT ALSO MAKES THE ONCE-PER-ATTACK RULE VISIBLE. A body the blade passes
-- through on samples 3, 4 and 5 shows `in-volume` three times and `COUNTED`
-- once. That is dedup across the activation, and it is the thing you cannot
-- confirm from a hit count alone.

local Debris = game:GetService("Debris")

local DebugConfig = require(script.Parent:WaitForChild("DebugConfig"))

local SweepTrace = {}

local TRACE_FLAG = "SweepTrace"

-- The whole arc, left on screen after the blade itself has gone, so the path
-- can be looked at as a shape rather than remembered as a motion. Its own
-- flag, because the drawing is useful on its own and the table is heavy.
local PATH_FLAG = "SweepPath"
local PATH_LIFETIME = 4
local PATH_THICKNESS = 0.08

local traces = setmetatable({}, { __mode = "k" })   -- sweep -> rows

local function vec(v: Vector3?): string
    if not v then
        return "nil"
    end
    return string.format("(%.1f, %.1f, %.1f)", v.X, v.Y, v.Z)
end

-- Deliberately a second implementation of the same maths Overlap uses. A
-- diagnostic that calls the code under test agrees with it by construction --
-- including when both are wrong.
local function closestOnSegment(a: Vector3, b: Vector3, p: Vector3): Vector3
    local ab = b - a
    local lengthSquared = ab:Dot(ab)
    if lengthSquared <= 0 then
        return a
    end
    return a + ab * math.clamp((p - a):Dot(ab) / lengthSquared, 0, 1)
end

-- Two rounds of alternating projection. Good enough to report with, and not
-- the routine Overlap uses.
local function segmentGap(a1: Vector3, b1: Vector3, a2: Vector3, b2: Vector3): number
    local p = closestOnSegment(a1, b1, (a2 + b2) * 0.5)
    local q = closestOnSegment(a2, b2, p)
    p = closestOnSegment(a1, b1, q)
    return (p - q).Magnitude
end

-- The blade as a segment, in world space, for whichever shape this volume is.
-- ARC and BOX have no segment of their own, so their "blade" is the reach line
-- along the facing -- which is what a designer means when they point at the
-- middle of a fan.
local function bladeOf(origin: CFrame, volume): (Vector3, Vector3)
    local start = origin.Position

    if volume.shape == "CAPSULE" then
        return start, start + origin.LookVector * volume.length
    elseif volume.shape == "BOX" then
        return start, start + origin.LookVector * (volume.size.Z * 0.5)
    end

    return start, start + origin.LookVector * (volume.radius or 1)
end

local function drawPath(a: Vector3, b: Vector3, fraction: number)
    if not DebugConfig.get(PATH_FLAG) then
        return
    end

    local folder = workspace:FindFirstChild("SweepTrace")
    if not folder then
        folder = Instance.new("Folder")
        folder.Name = "SweepTrace"
        folder.Parent = workspace
    end

    local delta = b - a
    local length = delta.Magnitude
    if length <= 0 then
        return
    end

    local part = Instance.new("Part")
    part.Size = Vector3.new(PATH_THICKNESS, PATH_THICKNESS, length)
    part.CFrame = CFrame.lookAt(a + delta * 0.5, b)
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.CastShadow = false
    part.Material = Enum.Material.Neon
    -- Cold at the start of the arc, hot at the end, matching AttackDebug's
    -- live blade -- so the ghost path and the animation read as one thing.
    part.Color = Color3.fromRGB(70, 150, 255):Lerp(Color3.fromRGB(255, 120, 0), fraction)
    part.Transparency = 0.45
    part.Parent = folder

    Debris:AddItem(part, PATH_LIFETIME)
end

-- Latched at the START of a swing, not read per sample. A flag flipped
-- mid-swing would otherwise produce a half-recorded trace whose gaps look
-- like missed samples rather than like a toggle.
function SweepTrace.begin(sweep)
    if DebugConfig.get(TRACE_FLAG) or DebugConfig.get(PATH_FLAG) then
        traces[sweep] = {}
    end
end

-- Called once per sample, with everything that sample saw. `candidates` is
-- the broadphase survivors -- the point is to record the ones that were
-- CONSIDERED and missed, not only the ones that connected.
function SweepTrace.sample(sweep, index: number, angle: number, origin: CFrame, candidates, hits, newlyCounted)
    local rows = traces[sweep]
    if not rows then
        return
    end

    local volume = sweep.volume
    local bladeA, bladeB = bladeOf(origin, volume)

    local wedges = sweep.wedges or volume.samples
    local fraction = wedges > 1 and ((index - 1) / (wedges - 1)) or 0.5
    drawPath(bladeA, bladeB, fraction)

    local inVolume = {}
    for _, entity in ipairs(hits) do
        inVolume[entity] = true
    end

    local targets = {}
    for _, entity in ipairs(candidates) do
        if entity ~= sweep.attacker then
            local spatial = entity.spatial
            local pose = spatial and spatial:poseAt(sweep.lastAt or 0)
            if pose then
                local hurtA, hurtB = spatial:endpoints(pose)
                table.insert(targets, {
                    id = tostring(entity.identity:getId()),
                    hurtA = hurtA,
                    hurtB = hurtB,
                    gap = segmentGap(bladeA, bladeB, hurtA, hurtB),
                    reach = (volume.radius or 0) + spatial.radius,
                    inVolume = inVolume[entity] == true,
                    counted = newlyCounted[entity] == true,
                })
            end
        end
    end

    table.insert(rows, {
        index = index,
        angle = math.deg(angle),
        bladeA = bladeA,
        bladeB = bladeB,
        targets = targets,
    })
end

function SweepTrace.finish(sweep)
    local rows = traces[sweep]
    if not rows or #rows == 0 then
        return
    end
    traces[sweep] = nil

    -- The path may have been drawn without the table being wanted.
    if not DebugConfig.get(TRACE_FLAG) then
        return
    end

    local wedges = sweep.wedges or sweep.volume.samples

    print(string.format(
        "======== SWEEP #%d TRACE -- %s, %g deg over %.2fs in %d wedges of %.1f deg ========",
        sweep.id, sweep.volume.shape, sweep.volume.sweep,
        sweep.volume.activeWindow, wedges, sweep.instant.angle))

    -- Per-sample: where the blade was, and every body it was measured against.
    for _, row in ipairs(rows) do
        print(string.format("  wedge %d/%d  centred %+6.1f  reach %s -> %s",
            row.index, wedges, row.angle,
            vec(row.bladeA), vec(row.bladeB)))

        if #row.targets == 0 then
            print("      (no candidates in broadphase)")
        end

        for _, t in ipairs(row.targets) do
            local mark
            if t.counted then
                mark = "COUNTED "     -- in the volume, and new to this swing
            elseif t.inVolume then
                mark = "in-volume"    -- in the volume, already counted
            else
                mark = "  ---    "
            end

            print(string.format(
                "      %s %-10s hurtbox %s..%s  gap %6.2f (reach %5.2f)",
                mark, t.id, vec(t.hurtA), vec(t.hurtB), t.gap, t.reach))
        end
    end

    -- The summary that makes the once-per-attack rule checkable: how many
    -- samples each body was inside the volume for, against the one time it
    -- was counted.
    local appearances = {}
    local order = {}
    for _, row in ipairs(rows) do
        for _, t in ipairs(row.targets) do
            if t.inVolume then
                if appearances[t.id] == nil then
                    appearances[t.id] = 0
                    table.insert(order, t.id)
                end
                appearances[t.id] += 1
            end
        end
    end

    if #order == 0 then
        print("  ---- nothing entered the volume at any sample ----")
    else
        print("  ---- once per attack ----")
        for _, id in ipairs(order) do
            print(string.format(
                "      %-10s inside the volume on %d sample(s), counted 1 time",
                id, appearances[id]))
        end
    end

    print(string.rep("=", 72))
end

return SweepTrace
