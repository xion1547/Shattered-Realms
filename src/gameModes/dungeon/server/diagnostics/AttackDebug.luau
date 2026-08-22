-- src/gameModes/dungeon/server/diagnostics/AttackDebug.luau
--
-- Draws the attack volume the server actually resolved, for a third of a
-- second, in the world where it happened.
--
-- THIS IS THE OTHER HALF OF HurtboxDebug. That one draws what you HIT; this
-- draws what you SWING. Neither is visible in a normal session, and every
-- disagreement between the game's feel and its maths lives in the gap between
-- the two -- a swing that looks like it connected and did not is either a
-- volume narrower than it looks or a hurtbox smaller than the body, and you
-- cannot tell which without seeing both.
--
-- IT DRAWS THE RESOLVED VOLUME, NOT THE ANIMATION. The arc here is
-- `radius` and `angle` off the skill definition, positioned from the
-- attacker's live pose -- exactly the numbers TargetResolution used. If it
-- disagrees with the swing animation, THAT IS THE FINDING: the hit volume is
-- server math and never derives from the animation (Animation.md Part 11),
-- so the two are authored to match and nothing enforces it.
--
-- SPOKES RATHER THAN A SOLID WEDGE, because Roblox has no pie-slice
-- primitive and building one from a mesh is more work than a debug overlay
-- deserves. A fan of thin rays reads the angle and the reach immediately,
-- which is the whole job.
--
-- THE ORIGIN IS RE-READ RATHER THAN PASSED IN. TargetResolution computes it
-- privately, and exposing it to let a diagnostic in would widen a production
-- API for a temporary tool. `spatial:getCFrame()` is what that private
-- function reads too -- SwingReport already does the same thing.

local Debris = game:GetService("Debris")

local DebugConfig = require(script.Parent:WaitForChild("DebugConfig"))

local AttackDebug = {}

local FLAG = "Hitboxes"

-- Long enough to see at 60fps, short enough that ten swings do not fill the
-- screen with stale fans.
local LIFETIME = 0.35

local SPOKE_THICKNESS = 0.12
local SPOKE_COLOR = Color3.fromRGB(255, 200, 40)     -- the volume: amber
local HIT_COLOR = Color3.fromRGB(255, 40, 40)        -- what it caught: red
local MISS_MARKER = Color3.fromRGB(90, 90, 110)      -- considered, not hit

-- A sweeping blade is drawn cold at the start of its arc and hot at the end,
-- so which way it travelled is readable from a still image. Exposed rather
-- than kept private because the caller knows how far through the swing it is
-- and this file does not.
AttackDebug.SWEEP_START_COLOR = Color3.fromRGB(70, 150, 255)
AttackDebug.SWEEP_END_COLOR = Color3.fromRGB(255, 120, 0)

-- How many rays to fan across the arc. Odd, so one lands exactly on the
-- attacker's facing and the centre line is unambiguous.
local SPOKE_COUNT = 9

local function folder(): Folder
    local existing = workspace:FindFirstChild("AttackDebug")
    if existing then
        return existing
    end
    local created = Instance.new("Folder")
    created.Name = "AttackDebug"
    created.Parent = workspace
    return created
end

-- THE ACTIVE LIFETIME, set per call. A sweeping volume overrides it to
-- something much shorter, and that single number is the difference between
-- seeing a swing and seeing a pile.
--
-- Eight samples of a 0.35s swing are ~50ms apart. Drawn at the default 0.35s
-- lifetime, all eight are on screen simultaneously for most of the swing --
-- geometrically correct, and completely static to look at. Drawn at ~0.10s,
-- roughly two are alive at once and the blade visibly travels.
local activeLifetime = LIFETIME

local function transient(part: Part)
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.Massless = true
    part.CastShadow = false
    part.Material = Enum.Material.Neon
    part.Parent = folder()
    -- Debris rather than a manual task.delay: it survives this module being
    -- reloaded, and it cannot leak a part if the delay thread is killed.
    Debris:AddItem(part, activeLifetime)
end

-- A thin bar from `from` to `to`.
--
-- `CFrame.lookAt` points a part's -Z at its target, and a Part's Size.Z runs
-- along that same local axis -- so a part of length `d` centred on the
-- midpoint and looking at `to` spans exactly from `from` to `to`.
local function ray(from: Vector3, to: Vector3, thickness: number, color: Color3)
    local delta = to - from
    local length = delta.Magnitude
    if length <= 0 then
        return
    end

    local part = Instance.new("Part")
    part.Size = Vector3.new(thickness, thickness, length)
    part.CFrame = CFrame.lookAt(from + delta * 0.5, to)
    part.Color = color
    part.Transparency = 0.25
    transient(part)
end

local function marker(position: Vector3, size: number, color: Color3, transparency: number)
    local part = Instance.new("Part")
    part.Shape = Enum.PartType.Ball
    part.Size = Vector3.new(size, size, size)
    part.CFrame = CFrame.new(position)
    part.Color = color
    part.Transparency = transparency
    transient(part)
end

local function block(cf: CFrame, size: Vector3, color: Color3, transparency: number)
    local part = Instance.new("Part")
    part.Size = size
    part.CFrame = cf
    part.Color = color
    part.Transparency = transparency
    transient(part)
end

-- AN ARC IS A CONE, NOT A FAN, and drawing it as a fan was a real bug.
--
-- `Overlap.arc` measures the full THREE-DIMENSIONAL angle between the
-- attacker's look direction and the target -- `acos(direction:Dot(look))`
-- with both as 3D vectors. So a 120-degree arc opens 60 degrees in EVERY
-- direction around the facing, including up and down.
--
-- This function used to rotate spokes about the Y axis only, so it drew a
-- flat horizontal slice of a shape that is round. The symptom: jump above an
-- enemy, swing, watch the yellow fan float clearly overhead -- and get a red
-- hit line anyway, because the cone reaches down to them and the drawing
-- never showed that.
--
-- TWO CROSSED FANS rather than a full cone mesh: horizontal and vertical,
-- sharing an apex. That reads as a cone immediately, costs twice the parts
-- instead of twenty times, and -- most importantly -- the vertical fan is the
-- one that would have made the bug obvious in a second.
local function drawFan(origin: CFrame, volume, rotate, thicknessScale: number)
    local apex = origin.Position
    local half = math.rad(volume.angle) * 0.5
    local reach = volume.radius

    for index = 0, SPOKE_COUNT - 1 do
        -- 0 -> -half, SPOKE_COUNT-1 -> +half.
        local t = SPOKE_COUNT > 1 and (index / (SPOKE_COUNT - 1)) or 0.5
        local offset = -half + t * (half * 2)

        -- Rotated in the attacker's OWN frame, not the world's, so a swing on
        -- a slope still draws in the plane it resolves in.
        local direction = (origin * rotate(offset)).LookVector

        -- The two edges get drawn thicker: they are the boundary a designer is
        -- actually tuning when they change `angle`.
        local isEdge = index == 0 or index == SPOKE_COUNT - 1
        ray(apex, apex + direction * reach,
            (isEdge and SPOKE_THICKNESS * 2.5 or SPOKE_THICKNESS) * thicknessScale,
            SPOKE_COLOR)
    end
end

local function drawArc(origin: CFrame, volume)
    -- Yaw: the sweep you think of as "the swing".
    drawFan(origin, volume, function(offset)
        return CFrame.Angles(0, offset, 0)
    end, 1)

    -- Pitch: the half nobody pictures, and the half that catches an enemy you
    -- jumped over. Drawn thinner so the horizontal fan still reads as the
    -- primary shape.
    drawFan(origin, volume, function(offset)
        return CFrame.Angles(offset, 0, 0)
    end, 0.55)
end

-- The box IS a Part, so it draws exactly -- no approximation, and the
-- rotation comes free from the CFrame. This is the one shape whose overlay
-- cannot possibly disagree with what the maths tested.
local function drawBox(origin: CFrame, volume)
    block(origin, volume.size, SPOKE_COLOR, 0.75)

    -- The forward face outlined, so which way the cleave points is readable
    -- from any camera angle. A translucent box alone is ambiguous.
    local halfDepth = volume.size.Z * 0.5
    local front = origin * CFrame.new(0, 0, -halfDepth)
    block(front, Vector3.new(volume.size.X, volume.size.Y, SPOKE_THICKNESS * 2),
        SPOKE_COLOR, 0.35)
end

-- Same three pieces HurtboxDebug uses for a hurtbox capsule -- two balls and
-- a shaft -- because it is the same shape, and drawing it two different ways
-- would invite the two from ever being compared.
local function drawCapsule(origin: CFrame, volume)
    local start = origin.Position
    local finish = start + origin.LookVector * volume.length
    local diameter = volume.radius * 2

    marker(start, diameter, SPOKE_COLOR, 0.75)
    marker(finish, diameter, SPOKE_COLOR, 0.75)

    local delta = finish - start
    block(CFrame.lookAt(start + delta * 0.5, finish),
        Vector3.new(diameter, diameter, delta.Magnitude), SPOKE_COLOR, 0.75)
end

-- THE OFFSET IS APPLIED HERE TOO, and it must stay in step with
-- Overlap.test -- an overlay drawn at the anchor while the maths resolved
-- four studs forward is worse than no overlay, because it makes a correct
-- system look broken.
local function drawVolume(origin: CFrame, volume)
    if volume.offset then
        origin = origin * volume.offset
    end

    if volume.shape == "ARC" then
        drawArc(origin, volume)
    elseif volume.shape == "BOX" then
        drawBox(origin, volume)
    elseif volume.shape == "CAPSULE" then
        drawCapsule(origin, volume)
    elseif volume.shape == "SPHERE" then
        marker(origin.Position, volume.radius * 2, SPOKE_COLOR, 0.8)
    else
        -- An unknown shape draws nothing rather than guessing. Overlap.test
        -- will have errored on it already.
        return
    end
end

-- `hits` is what TargetResolution returned. `candidates` is optional -- pass
-- the broadphase survivors and everything considered-but-missed gets a faint
-- grey dot, which is how you tell "the volume missed it" apart from "the
-- broadphase never offered it".
-- `opts` is optional: { lifetime, color }. A sweeping volume passes a short
-- lifetime so the blade animates, and a colour that shifts across the swing so
-- the direction of travel is readable even in a screenshot.
function AttackDebug.show(query, hits, candidates, opts)
    if not DebugConfig.get(FLAG) then
        return
    end

    local attacker = query.attacker
    local spatial = attacker and attacker.spatial
    local pose = spatial and spatial:getCFrame()
    if not pose then
        return
    end

    activeLifetime = (opts and opts.lifetime) or LIFETIME
    local restoreColor = SPOKE_COLOR
    if opts and opts.color then
        SPOKE_COLOR = opts.color
    end

    -- THE SWING ANGLE IS APPLIED HERE, exactly as TargetResolution._origin
    -- applies it -- rotation first, then the volume's own offset inside
    -- drawVolume. An overlay drawn at the un-rotated facing while the maths
    -- resolved a rotated blade would make a working swing look broken, which
    -- is the specific failure this whole file exists to prevent.
    local origin = pose
    if query.sweepAngle and query.sweepAngle ~= 0 then
        origin = origin * CFrame.Angles(0, query.sweepAngle, 0)
    end

    drawVolume(origin, query.volume)

    if candidates then
        for _, entity in ipairs(candidates) do
            local pose = entity.spatial and entity.spatial:getCFrame()
            if pose then
                marker(pose.Position, 1.2, MISS_MARKER, 0.6)
            end
        end
    end

    for _, entity in ipairs(hits) do
        local hitPose = entity.spatial and entity.spatial:getCFrame()
        if hitPose then
            -- A bright ball at the body, plus a line back to the attacker, so
            -- a hit at the edge of a wide fan is unambiguous about WHICH
            -- attacker caught it once there is more than one.
            --
            -- HIT MARKERS OUTLIVE THE BLADE, deliberately: the blade is drawn
            -- for ~0.1s so the swing animates, but a flash that brief is easy
            -- to miss entirely. The hit keeps the full lifetime so what was
            -- caught is still readable after the blade has moved on.
            activeLifetime = LIFETIME
            marker(hitPose.Position, 2.4, HIT_COLOR, 0.35)
            ray(origin.Position, hitPose.Position, SPOKE_THICKNESS * 1.5, HIT_COLOR)
        end
    end

    -- SPOKE_COLOR is a file-local the caller is allowed to tint for one call.
    -- Restored unconditionally, because leaving it set would silently recolour
    -- every subsequent swing -- the kind of bug that looks like a rendering
    -- glitch and is actually state.
    SPOKE_COLOR = restoreColor
    activeLifetime = LIFETIME
end

return AttackDebug
