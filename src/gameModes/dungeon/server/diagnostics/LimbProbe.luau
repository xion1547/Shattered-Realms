-- src/gameModes/dungeon/server/diagnostics/LimbProbe.luau
--
-- TEMPORARY. Answers exactly one question and should be deleted once it has:
--
--     Does a SERVER script see a limb's CFrame change while an animation
--     plays on that rig?
--
-- That question decides whether a hitbox can be a real welded part whose
-- position the server records each tick (`motion = LIVE`), or whether a
-- player's hitbox path has to be recorded at dev time instead
-- (`motion = BAKED`). See HitDetection.md Part 9.
--
-- ============================================================================
-- THE MEASUREMENT, AND THE FALSE POSITIVE IT EXISTS TO AVOID
-- ============================================================================
--
-- The obvious version of this test logs a hand part's WORLD CFrame and watches
-- the numbers change. They always change. Walking moves the whole body, so a
-- world reading varies constantly whether or not a single joint ever bent, and
-- it would report success on a rig that is standing perfectly rigid.
--
-- The reading that means something is the limb RELATIVE TO THE ROOT:
--
--     rel = root.CFrame:Inverse() * limb.CFrame
--
-- That is invariant under walking, turning, falling and being teleported. It
-- changes if and only if the limb moved with respect to the body -- which is
-- the definition of the thing being asked about.
--
-- ============================================================================
-- WHY THERE IS A CONTROL, AND WHY IT IS NOT OPTIONAL
-- ============================================================================
--
-- Probe B builds a two-part rig from code and drives its joint from THIS
-- script, so the server is unambiguously the thing moving it. Its purpose is
-- not to discover anything -- the answer is known -- it is to prove the
-- instrument works.
--
--     B reports MOVING, A reports STATIC   -> A's answer is real
--     B reports STATIC                     -> THE MEASUREMENT IS BROKEN.
--                                             Report nothing. Fix this file.
--
-- A test with no control cannot distinguish "the limb did not move" from "I
-- measured the wrong thing", and those two produce identical output.
--
-- ============================================================================
-- WHAT EACH PROBE COVERS
-- ============================================================================
--
--   A  a player's own character        client plays the animation,
--      (default walk/idle animations)  client owns the rig.  THE REAL CASE.
--
--   B  a rig built here, joint driven  server plays it, server owns it.
--      by a sine wave from the server  CONTROL + the boss case.
--
--   C  a part WELDED to B's moving     does a weld carry a joint-driven
--      limb                            part, as a hitbox proxy would?
--
-- Probe A needs no uploaded animation. A player character is already running
-- Roblox's default animations, on the client, on a client-owned rig -- which
-- is precisely the configuration in question, available for free.
--
-- ============================================================================
-- THE TWO MARKERS
-- ============================================================================
--
-- Numbers are the evidence; the markers are so the answer is visible without
-- reading any. Two spheres ride your right hand:
--
--   GREEN   welded to the hand. Rides YOUR client's simulation.
--   RED     anchored, teleported each frame to where the SERVER thinks
--           your hand is.
--
-- Together   -> the server sees the animation.
-- Red frozen at the rest pose while green swings -> it does not.
-- Red trailing green by a fixed lag -> it does, late, and the lag is the
--           thing to measure next.
--
-- Deliberately NOT welded for the red one: teleporting from the server's own
-- reading is the entire point, and welding it would make it follow the client
-- and quietly show agreement that was never tested.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local DebugConfig = require(script.Parent:WaitForChild("DebugConfig"))

local LimbProbe = {}

local FLAG = "LimbProbe"

-- How often a summary block is printed. Long enough that a walk cycle
-- completes several times inside one window, short enough to iterate.
local REPORT_SECONDS = 3.0

-- Studs of variation, relative to the root, below which a reading is called
-- noise rather than motion. Physics jitter and float error live well under
-- this; a bending elbow is far above it. The RAW range is always printed
-- alongside the verdict, so this threshold informs the label and never hides
-- the number it was derived from.
local MOVEMENT_EPSILON = 0.05

-- Probe B's joint is driven through this many radians, peak to peak. Chosen
-- large enough to be unmistakable both on screen and in the numbers.
local CONTROL_SWING_RADIANS = math.rad(70)
local CONTROL_PERIOD = 2.0

local MARKER_SIZE = Vector3.new(0.6, 0.6, 0.6)
local CLIENT_MARKER_COLOR = Color3.fromRGB(0, 255, 120)   -- welded, rides the client
local SERVER_MARKER_COLOR = Color3.fromRGB(255, 60, 60)   -- the server's belief

-- RANGE ACCUMULATOR ------------------------------------------------------
--
-- Min and max per axis rather than a running average: an average over a
-- symmetric swing is the rest pose, which would read as "not moving" for a
-- limb travelling two studs each way. The RANGE is what distinguishes motion
-- from stillness, and the mean actively hides it.

local function newRange()
    return {
        count = 0,
        minX = math.huge, maxX = -math.huge,
        minY = math.huge, maxY = -math.huge,
        minZ = math.huge, maxZ = -math.huge,
    }
end

local function feed(range, v: Vector3)
    range.count += 1
    range.minX = math.min(range.minX, v.X); range.maxX = math.max(range.maxX, v.X)
    range.minY = math.min(range.minY, v.Y); range.maxY = math.max(range.maxY, v.Y)
    range.minZ = math.min(range.minZ, v.Z); range.maxZ = math.max(range.maxZ, v.Z)
end

local function spans(range): (number, number, number)
    if range.count == 0 then
        return 0, 0, 0
    end
    return range.maxX - range.minX, range.maxY - range.minY, range.maxZ - range.minZ
end

local function verdict(range): string
    if range.count == 0 then
        return "NO DATA"
    end
    local dx, dy, dz = spans(range)
    local largest = math.max(dx, dy, dz)
    return largest >= MOVEMENT_EPSILON and "MOVING" or "STATIC"
end

local function describe(label: string, range): string
    local dx, dy, dz = spans(range)
    return string.format(
        "    %-22s range  X %6.3f  Y %6.3f  Z %6.3f   ->  %s",
        label, dx, dy, dz, verdict(range))
end

-- HELPERS ----------------------------------------------------------------

local function relativeTo(root: BasePart, part: BasePart): CFrame
    return root.CFrame:Inverse() * part.CFrame
end

-- Finds the joint parented to `part`, accepting EITHER kind.
--
-- Roblox's Avatar Joint Upgrade (live 2026-01-26) replaces Motor6D with
-- AnimationConstraint on R15 characters when `StarterPlayer.AvatarJointUpgrade`
-- is Enabled, and it is scheduled to become the default. Code that asks only
-- `:IsA("Motor6D")` finds nothing on an upgraded rig -- and would report a
-- missing joint as though it were a finding. Both classes carry a `Transform`,
-- so everything below reads the same either way.
local function findJoint(part: BasePart): Instance?
    for _, child in ipairs(part:GetChildren()) do
        if child:IsA("Motor6D") or child:IsA("AnimationConstraint") then
            return child
        end
    end
    return nil
end

local function isIdentity(cf: CFrame): boolean
    local x, y, z = cf.Position.X, cf.Position.Y, cf.Position.Z
    if math.abs(x) > 1e-4 or math.abs(y) > 1e-4 or math.abs(z) > 1e-4 then
        return false
    end
    -- LookVector is enough to catch a rotation; a joint that rotated without
    -- translating is the normal case for a bending elbow and must not read as
    -- identity.
    local look = cf.LookVector
    return math.abs(look.X) < 1e-4 and math.abs(look.Y) < 1e-4
        and math.abs(look.Z + 1) < 1e-4
end

local function makeMarker(name: string, color: Color3, anchored: boolean): Part
    local part = Instance.new("Part")
    part.Name = name
    part.Shape = Enum.PartType.Ball
    part.Size = MARKER_SIZE
    part.Color = color
    part.Material = Enum.Material.Neon
    part.Transparency = 0.35
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.Massless = true
    part.Anchored = anchored
    return part
end

-- PROBE B — THE CONTROL --------------------------------------------------
--
-- A two-part rig assembled here so nothing about it is inherited or assumed:
-- an anchored root, an unanchored limb, one joint between them, and a proxy
-- part welded to the limb. This script writes the joint's Transform directly,
-- so if the server cannot observe THIS moving, it cannot observe anything and
-- no other reading in this file means anything.

local control = nil

local function buildControl()
    local model = Instance.new("Model")
    model.Name = "LimbProbeControl"

    local root = Instance.new("Part")
    root.Name = "ControlRoot"
    root.Size = Vector3.new(2, 2, 1)
    root.Position = Vector3.new(0, 6, -18)
    root.Anchored = true
    root.CanCollide = false
    root.Color = Color3.fromRGB(70, 70, 90)
    root.Parent = model

    local limb = Instance.new("Part")
    limb.Name = "ControlLimb"
    limb.Size = Vector3.new(0.8, 3, 0.8)
    limb.Anchored = false
    limb.CanCollide = false
    limb.Massless = true
    limb.Color = Color3.fromRGB(120, 160, 255)
    limb.Parent = model

    -- Motor6D rather than AnimationConstraint: this rig is ours, is not an
    -- avatar, and Motor6D remains correct for non-avatar mechanical rigs. The
    -- reader for it accepts both anyway.
    local motor = Instance.new("Motor6D")
    motor.Name = "ControlJoint"
    motor.Part0 = root
    motor.Part1 = limb
    motor.C0 = CFrame.new(0, 1, 0)
    motor.C1 = CFrame.new(0, -1.5, 0)
    motor.Parent = root

    -- PROBE C. A hitbox proxy is exactly this: a part welded to something the
    -- animation moves. If a weld does not carry it, the whole `motion = LIVE`
    -- idea fails here rather than in production.
    local proxy = makeMarker("ControlProxy", Color3.fromRGB(255, 200, 0), false)
    proxy.Size = Vector3.new(1.2, 1.2, 1.2)
    proxy.Parent = model

    model.Parent = workspace

    -- CFrame BEFORE the weld, or the weld records the wrong offset and pins
    -- the proxy wherever it happened to spawn.
    limb.CFrame = root.CFrame * CFrame.new(0, 2.5, 0)
    proxy.CFrame = limb.CFrame * CFrame.new(0, 1.5, 0)

    local weld = Instance.new("WeldConstraint")
    weld.Part0 = limb
    weld.Part1 = proxy
    weld.Parent = proxy

    return { model = model, root = root, limb = limb, motor = motor, proxy = proxy }
end

local function driveControl(elapsed: number)
    if not control then
        return
    end
    local phase = math.sin(elapsed * (2 * math.pi / CONTROL_PERIOD))
    control.motor.Transform = CFrame.Angles(phase * CONTROL_SWING_RADIANS * 0.5, 0, 0)
end

-- PROBE A — A PLAYER'S CHARACTER -----------------------------------------

local watched = {}    -- player -> state

local function limbOf(character: Model): BasePart?
    -- R15. RightHand is the furthest point of the arm chain and therefore the
    -- most sensitive to any joint in it bending -- an error at the shoulder is
    -- amplified all the way down, which is what we want to detect.
    return character:FindFirstChild("RightHand")
        or character:FindFirstChild("Right Arm")     -- R6 fallback
end

local function attachPlayer(player: Player, character: Model)
    local root = character:WaitForChild("HumanoidRootPart", 10)
    local humanoid = character:WaitForChild("Humanoid", 10)
    if not root or not humanoid then
        warn(string.format("[LimbProbe] %s: no root or humanoid, skipping", player.Name))
        return
    end

    local limb = limbOf(character)
    if not limb then
        warn(string.format(
            "[LimbProbe] %s: no RightHand or Right Arm -- unexpected rig, skipping",
            player.Name))
        return
    end

    -- Welded, not teleported. A weld puts it in the character's own physics
    -- assembly, so it is simulated by whoever owns the character -- the client
    -- -- and therefore shows the CLIENT's truth. Teleporting it from here
    -- would show the server's, which is the other marker's job.
    local clientMarker = makeMarker("LimbProbe_Client", CLIENT_MARKER_COLOR, false)
    clientMarker.CFrame = limb.CFrame
    clientMarker.Parent = character
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = limb
    weld.Part1 = clientMarker
    weld.Parent = clientMarker

    local serverMarker = makeMarker("LimbProbe_Server", SERVER_MARKER_COLOR, true)
    serverMarker.CFrame = limb.CFrame
    serverMarker.Parent = workspace

    watched[player] = {
        character = character,
        root = root,
        limb = limb,
        humanoid = humanoid,
        joint = findJoint(limb),
        serverMarker = serverMarker,
        limbRange = newRange(),
        markerRange = newRange(),
        transformIdentity = 0,
        transformTotal = 0,
        states = {},
    }

    local jointDesc = "NONE FOUND"
    local joint = watched[player].joint
    if joint then
        jointDesc = string.format("%s (%s)", joint.Name, joint.ClassName)
    end

    print(string.format(
        "[LimbProbe] watching %s | limb=%s | joint=%s | network owner=%s",
        player.Name, limb.Name, jointDesc,
        (function()
            -- A part with no network owner is server-simulated. A character
            -- should report its own player; anything else is worth seeing,
            -- because ownership is the property that decides who can lie.
            local ok, owner = pcall(function() return root:GetNetworkOwner() end)
            if not ok then return "unreadable" end
            return owner and owner.Name or "SERVER"
        end)()))
end

local function releasePlayer(player: Player)
    local state = watched[player]
    if not state then
        return
    end
    if state.serverMarker then
        state.serverMarker:Destroy()
    end
    watched[player] = nil
end

-- SAMPLING ---------------------------------------------------------------

local function sample()
    for player, state in pairs(watched) do
        local character = state.character
        if not character or not character.Parent
            or not state.root.Parent or not state.limb.Parent then
            releasePlayer(player)
            continue
        end

        local rel = relativeTo(state.root, state.limb)
        feed(state.limbRange, rel.Position)

        -- The server's belief, drawn. Uses the server's own reading of the
        -- limb, never the client's.
        state.serverMarker.CFrame = state.limb.CFrame

        local marker = character:FindFirstChild("LimbProbe_Client")
        if marker and marker:IsA("BasePart") then
            feed(state.markerRange, relativeTo(state.root, marker).Position)
        end

        if state.joint then
            state.transformTotal += 1
            if isIdentity(state.joint.Transform) then
                state.transformIdentity += 1
            end
        end

        local humanoidState = state.humanoid and state.humanoid:GetState().Name or "?"
        state.states[humanoidState] = (state.states[humanoidState] or 0) + 1
    end

    if control and control.limb.Parent then
        control.limbRange = control.limbRange or newRange()
        control.proxyRange = control.proxyRange or newRange()
        feed(control.limbRange, relativeTo(control.root, control.limb).Position)
        feed(control.proxyRange, relativeTo(control.root, control.proxy).Position)
    end
end

-- REPORTING --------------------------------------------------------------

local function playingTrackCount(character: Model): (number, string)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
    if not animator then
        return -1, "no Animator"
    end

    local ok, tracks = pcall(function()
        return animator:GetPlayingAnimationTracks()
    end)
    if not ok or type(tracks) ~= "table" then
        return -1, "unreadable"
    end

    local names = {}
    for _, track in ipairs(tracks) do
        table.insert(names, track.Name)
    end
    return #tracks, #names > 0 and table.concat(names, ", ") or "none"
end

local function dominantState(states): string
    local best, bestCount = "?", -1
    for name, count in pairs(states) do
        if count > bestCount then
            best, bestCount = name, count
        end
    end
    return best
end

local function report(window: number)
    print("")
    print(string.format(
        "======== LimbProbe  %.1fs window ================================",
        window))

    -- CONTROL FIRST, DELIBERATELY. It is the thing that licenses reading
    -- anything below it, so it should be the first thing seen and the first
    -- thing checked when a result looks surprising.
    if control and control.limbRange then
        print("  [B] CONTROL  server-built rig, joint driven by this script")
        print(describe("limb rel root", control.limbRange))
        print("  [C] PROXY    part WELDED to that limb")
        print(describe("proxy rel root", control.proxyRange))
        if verdict(control.limbRange) ~= "MOVING" then
            print("    *** CONTROL IS NOT MOVING. The measurement is broken.")
            print("    *** Every reading below is meaningless. Do not report it.")
        end
        control.limbRange = newRange()
        control.proxyRange = newRange()
    else
        print("  [B] CONTROL  NOT BUILT -- nothing below can be trusted")
    end

    local any = false
    for player, state in pairs(watched) do
        any = true
        local trackCount, trackNames = playingTrackCount(state.character)

        print("")
        print(string.format(
            "  [A] PLAYER  %s   client-owned rig, client-played animations",
            player.Name))
        print(string.format(
            "    samples %d   humanoid mostly %s   tracks playing %s (%s)",
            state.limbRange.count, dominantState(state.states),
            trackCount >= 0 and tostring(trackCount) or "?", trackNames))
        print(describe("limb rel root", state.limbRange))
        print(describe("welded marker rel root", state.markerRange))

        if state.joint and state.transformTotal > 0 then
            print(string.format(
                "    %-22s identity on %d/%d samples   ->  %s",
                "joint.Transform",
                state.transformIdentity, state.transformTotal,
                state.transformIdentity == state.transformTotal
                    and "NEVER WRITTEN (server side)" or "WRITTEN"))
        else
            print("    joint.Transform        no joint found on the limb")
        end

        state.limbRange = newRange()
        state.markerRange = newRange()
        state.transformIdentity, state.transformTotal = 0, 0
        state.states = {}
    end

    if not any then
        print("")
        print("  [A] PLAYER   nobody being watched -- join, or respawn")
    end

    print("  ---------------------------------------------------------------")
    print("  Walk around, jump, and stand still for part of a window.")
    print("  Watch the two spheres on your right hand:")
    print("    GREEN welded (your client)   RED teleported (the server's belief)")
    print("================================================================")
end

-- LIFECYCLE --------------------------------------------------------------

local connections = {}
local running = false

function LimbProbe.start()
    if running then
        return
    end
    if not DebugConfig.get(FLAG) then
        print("[LimbProbe] off. workspace:SetAttribute(\"DebugLimbProbe\", true) to enable")
        return
    end
    running = true

    control = buildControl()
    control.limbRange = newRange()
    control.proxyRange = newRange()

    local function bind(player: Player)
        if player.Character then
            task.spawn(attachPlayer, player, player.Character)
        end
        table.insert(connections, player.CharacterAdded:Connect(function(character)
            releasePlayer(player)
            task.spawn(attachPlayer, player, character)
        end))
        table.insert(connections, player.CharacterRemoving:Connect(function()
            releasePlayer(player)
        end))
    end

    for _, player in ipairs(Players:GetPlayers()) do
        bind(player)
    end
    table.insert(connections, Players.PlayerAdded:Connect(bind))
    table.insert(connections, Players.PlayerRemoving:Connect(releasePlayer))

    local elapsed, sinceReport = 0, 0
    table.insert(connections, RunService.Heartbeat:Connect(function(dt)
        elapsed += dt
        sinceReport += dt

        driveControl(elapsed)
        sample()

        if sinceReport >= REPORT_SECONDS then
            report(sinceReport)
            sinceReport = 0
        end
    end))

    print("[LimbProbe] started. Control rig at (0, 6, -18). "
        .. "First report in " .. REPORT_SECONDS .. "s.")
end

function LimbProbe.stop()
    running = false
    for _, connection in ipairs(connections) do
        connection:Disconnect()
    end
    table.clear(connections)

    for player in pairs(watched) do
        releasePlayer(player)
    end
    if control and control.model then
        control.model:Destroy()
    end
    control = nil
end

return LimbProbe
