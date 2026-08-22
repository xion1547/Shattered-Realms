-- src/gameModes/dungeon/server/diagnostics/LimbProbe.luau
--
-- TEMPORARY. Answers one question, then gets deleted:
--
--     When the server reconstructs where a limb WAS at a past moment, how far
--     off is that from where the client actually saw it?
--
-- Answer in studs. That number decides whether a player's hitbox can be a
-- welded part the server records each tick (`motion = LIVE`), or has to be a
-- path recorded at dev time (`motion = BAKED`). HitDetection.md Part 9.
--
-- ============================================================================
-- THE THREE VERSIONS, AND WHY EACH ONE WAS WRONG
-- ============================================================================
--
-- v1  Measured RANGE OF MOTION on each side over a 3s window and subtracted.
--     Useless: the windows covered different seconds of a non-repeatable
--     input (walking), so the difference measured the walking.
--
-- v2  Client reports its pose stamped with a server time; server rewinds its
--     own history to that stamp and subtracts. Correct in shape, and it
--     produced ~0.9 studs of error.
--
--     STILL NOT CONCLUSIVE, because it assumed the two clocks agree. If the
--     client's estimate of server time is off by 50ms, and an arm covers two
--     studs in a third of a second, that mismatch alone manufactures ~0.33
--     studs of error out of a perfectly healthy system.
--
-- v3  (this one) Does not trust the stamp. For every client report it tries a
--     RANGE of moments either side of the stamp and finds which one matches
--     best.
--
--         best match at offset ~0     -> the clocks agree. The leftover error
--                                        is real divergence.
--         best match at offset 0.06   -> 60ms of skew was inflating v2, and
--                                        the error at the best offset is the
--                                        true fidelity.
--
--     This is ordinary signal alignment: slide one trace against the other
--     until they line up, and read off both the shift and the residual.
--
-- ============================================================================
-- THE DENOMINATOR, WHICH v2 OMITTED AND WHICH MAKES THE NUMBER READABLE
-- ============================================================================
--
-- "0.2 studs of error" means nothing alone. Against a limb that barely moved
-- it is terrible; against a limb that travelled three studs it is excellent.
-- So the report also carries how far the limb actually moved in the same
-- window, and the error as a percentage of it.
--
-- ============================================================================
-- THE CONTROL
-- ============================================================================
--
-- Probe B builds a rig here and drives its joint from this script, purely to
-- prove the measurement works. If B reads STATIC, this file is broken and
-- nothing else it prints means anything.
--
-- CONFIRMED: the client sees B as STATIC, and that is CORRECT -- a `Transform`
-- written by a script does not replicate in either direction, which is why NPC
-- animations must go through an Animator. So this control does NOT model a
-- server-animated boss; that case needs one real uploaded animation and stays
-- untested. Stated plainly because a control that silently covers less than it
-- appears to is worse than no control.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DebugConfig = require(script.Parent:WaitForChild("DebugConfig"))

local LimbProbe = {}

local FLAG = "LimbProbe"
local REMOTE_NAME = "LimbProbeRemote"
local REPORT_SECONDS = 3.0
local HISTORY_SECONDS = 2.0

-- OFFSET SEARCH ----------------------------------------------------------
--
-- How far either side of the client's stamp to look, and how finely.
--
-- NOT WIDER THAN THIS, deliberately. Walking is PERIODIC -- an arm returns to
-- roughly the same place about twice a second. Search far enough and the
-- aligner will happily lock onto the NEXT swing and report a confident,
-- meaningless offset. A fifth of a second is comfortably inside one cycle.
local SEARCH_SECONDS = 0.20
local SEARCH_STEP = 0.005

-- Below this, a best-offset is treated as "the clocks agree" rather than a
-- finding. Two frames.
local SKEW_NOISE_FLOOR = 0.033

-- Verdict thresholds in studs. OPINIONS, not measurements -- the raw figures
-- are always printed beside them. For scale: BASIC_SWING is a capsule 6.5
-- studs long and 0.5 thick.
local FAITHFUL_STUDS = 0.15
local DEGRADED_STUDS = 0.50

local CONTROL_SWING_RADIANS = math.rad(70)
local CONTROL_PERIOD = 2.0

-- Bigger than v2's 0.6. The whole point is seeing the gap, and a gap of 0.9
-- studs between two half-stud balls at arm's length is easy to miss.
local MARKER_SIZE = Vector3.new(1.1, 1.1, 1.1)
local CLIENT_MARKER_COLOR = Color3.fromRGB(0, 255, 120)
local SERVER_MARKER_COLOR = Color3.fromRGB(255, 40, 40)

-- HELPERS ----------------------------------------------------------------

local function relativeTo(root: BasePart, part: BasePart): CFrame
    return root.CFrame:Inverse() * part.CFrame
end

-- Accepts either joint class. This place has Avatar Joint Upgrade enabled --
-- v1 confirmed `RightWrist (AnimationConstraint)` -- and asking only for
-- Motor6D would report a missing joint as though that were a result.
local function findJoint(part: BasePart): Instance?
    for _, child in ipairs(part:GetChildren()) do
        if child:IsA("Motor6D") or child:IsA("AnimationConstraint") then
            return child
        end
    end
    return nil
end

local function makeMarker(name: string, color: Color3, anchored: boolean): Part
    local part = Instance.new("Part")
    part.Name = name
    part.Shape = Enum.PartType.Ball
    part.Size = MARKER_SIZE
    part.Color = color
    part.Material = Enum.Material.Neon
    part.Transparency = 0.2
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.Massless = true
    part.Anchored = anchored
    return part
end

local function limbOf(character: Model): BasePart?
    return character:FindFirstChild("RightHand")
        or character:FindFirstChild("Right Arm")
end

-- ACCUMULATOR ------------------------------------------------------------
--
-- Mean AND max, never mean alone. A limb that tracks well for most of a cycle
-- and is a stud out at the peak has a flattering mean and a disqualifying max
-- -- and the peak of the swing is exactly when an attack lands.

local function newAcc()
    return { count = 0, sum = 0, max = 0 }
end

local function feed(acc, value: number)
    acc.count += 1
    acc.sum += value
    acc.max = math.max(acc.max, value)
end

local function mean(acc): number
    return acc.count > 0 and (acc.sum / acc.count) or 0
end

-- PROBE B — THE CONTROL --------------------------------------------------

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

    local motor = Instance.new("Motor6D")
    motor.Name = "ControlJoint"
    motor.Part0 = root
    motor.Part1 = limb
    motor.C0 = CFrame.new(0, 1, 0)
    motor.C1 = CFrame.new(0, -1.5, 0)
    motor.Parent = root

    model.Parent = workspace
    limb.CFrame = root.CFrame * CFrame.new(0, 2.5, 0)

    return { model = model, root = root, limb = limb, motor = motor,
             moved = 0, samples = 0, base = nil }
end

local function driveControl(elapsed: number)
    if not control then
        return
    end
    local phase = math.sin(elapsed * (2 * math.pi / CONTROL_PERIOD))
    control.motor.Transform = CFrame.Angles(phase * CONTROL_SWING_RADIANS * 0.5, 0, 0)
end

-- PROBE A — A PLAYER'S CHARACTER -----------------------------------------

local watched = {}
local remote = nil

local function attachPlayer(player: Player, character: Model)
    local root = character:WaitForChild("HumanoidRootPart", 10)
    local humanoid = character:WaitForChild("Humanoid", 10)
    if not root or not humanoid then
        warn(string.format("[LimbProbe] %s: no root or humanoid", player.Name))
        return
    end

    local limb = limbOf(character)
    if not limb then
        warn(string.format("[LimbProbe] %s: no RightHand -- unexpected rig", player.Name))
        return
    end

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

        times = {},
        poses = {},

        naive = newAcc(),        -- error at the client's stamp, no realignment
        aligned = newAcc(),      -- error at the best-matching offset
        offsets = {},            -- every best offset found, for the median
        travel = newAcc(),       -- how far the limb actually moved. The denominator
        lastPose = nil,
        stale = 0,
        expected = 0,
    }

    local joint = watched[player].joint
    print(string.format(
        "[LimbProbe] watching %s | limb=%s | joint=%s",
        player.Name, limb.Name,
        joint and string.format("%s (%s)", joint.Name, joint.ClassName) or "NONE FOUND"))
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

local function poseAt(state, t: number): CFrame?
    local times, poses = state.times, state.poses
    local n = #times
    if n == 0 or t <= times[1] then
        return nil
    end
    if t >= times[n] then
        return poses[n]
    end

    local lo, hi = 1, n
    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        if times[mid] <= t then
            lo = mid
        else
            hi = mid - 1
        end
    end

    local ta, tb = times[lo], times[lo + 1]
    local span = tb - ta
    if span <= 0 then
        return poses[lo]
    end
    return poses[lo]:Lerp(poses[lo + 1], (t - ta) / span)
end

local function onClientReport(player: Player, t: number, clientPose: CFrame)
    local state = watched[player]
    if not state or typeof(clientPose) ~= "CFrame" or type(t) ~= "number" then
        return
    end

    local atStamp = poseAt(state, t)
    if not atStamp then
        state.stale += 1
        return
    end
    feed(state.naive, (atStamp.Position - clientPose.Position).Magnitude)

    -- THE ALIGNMENT SEARCH. Slide the lookup either side of the stamp and keep
    -- whichever moment the server's own history matches the client's reading
    -- best. The residual at that moment is the fidelity; the shift is the skew.
    local bestError, bestOffset = math.huge, 0
    local offset = -SEARCH_SECONDS
    while offset <= SEARCH_SECONDS do
        local candidate = poseAt(state, t + offset)
        if candidate then
            local err = (candidate.Position - clientPose.Position).Magnitude
            if err < bestError then
                bestError, bestOffset = err, offset
            end
        end
        offset += SEARCH_STEP
    end

    if bestError < math.huge then
        feed(state.aligned, bestError)
        table.insert(state.offsets, bestOffset)
    end
end

-- SAMPLING ---------------------------------------------------------------

local function sample(now: number)
    for player, state in pairs(watched) do
        local character = state.character
        if not character or not character.Parent
            or not state.root.Parent or not state.limb.Parent then
            releasePlayer(player)
            continue
        end

        local rel = relativeTo(state.root, state.limb)

        -- The denominator: total path length the limb travelled, as the SERVER
        -- saw it. Compared against the error, it turns "0.2 studs" into "10% of
        -- the motion", which is the form the number can actually be judged in.
        if state.lastPose then
            feed(state.travel, (rel.Position - state.lastPose.Position).Magnitude)
        end
        state.lastPose = rel

        table.insert(state.times, now)
        table.insert(state.poses, rel)
        while #state.times > 1 and (now - state.times[1]) > HISTORY_SECONDS do
            table.remove(state.times, 1)
            table.remove(state.poses, 1)
        end

        state.serverMarker.CFrame = state.limb.CFrame
    end

    if control and control.limb.Parent then
        local rel = relativeTo(control.root, control.limb)
        control.base = control.base or rel.Position
        control.moved = math.max(control.moved, (rel.Position - control.base).Magnitude)
        control.samples += 1
    end
end

-- REPORTING --------------------------------------------------------------

local function median(values): number
    if #values == 0 then
        return 0
    end
    local sorted = table.clone(values)
    table.sort(sorted)
    return sorted[math.ceil(#sorted / 2)]
end

local function verdictFor(studs: number): string
    if studs < FAITHFUL_STUDS then
        return "FAITHFUL   -- LIVE works for players"
    elseif studs < DEGRADED_STUDS then
        return "DEGRADED   -- judgement call"
    end
    return "UNUSABLE   -- players need BAKED"
end

local function report(window: number)
    print("")
    print("======== LimbProbe v3 =========================================")

    if control then
        local ok = control.moved >= 0.05
        print(string.format("  [B] CONTROL  moved %.3f studs  ->  %s",
            control.moved, ok and "INSTRUMENT OK" or "*** BROKEN, IGNORE EVERYTHING BELOW"))
        control.moved, control.samples, control.base = 0, 0, nil
    else
        print("  [B] CONTROL  NOT BUILT -- nothing below can be trusted")
    end

    for player, state in pairs(watched) do
        print("")
        print(string.format("  [A] %s", player.Name))

        if state.aligned.count == 0 then
            print("      no usable client reports -- is the client half running?")
        else
            local travelled = state.travel.sum
            local naiveMean, alignedMean = mean(state.naive), mean(state.aligned)
            local skew = median(state.offsets)

            print(string.format(
                "      %d reports compared   limb travelled %.2f studs this window",
                state.aligned.count, travelled))
            print(string.format(
                "      at the client's stamp   mean %6.3f   max %6.3f studs",
                naiveMean, state.naive.max))
            print(string.format(
                "      best alignment          mean %6.3f   max %6.3f studs   at %+.3fs",
                alignedMean, state.aligned.max, skew))

            if math.abs(skew) >= SKEW_NOISE_FLOOR then
                print(string.format(
                    "      ->  CLOCK SKEW of %.0fms was inflating the naive figure.",
                    skew * 1000))
                print(string.format(
                    "          The real error is %.3f studs, not %.3f.",
                    alignedMean, naiveMean))
            else
                print("      ->  No meaningful skew. The naive figure was already honest.")
            end

            if math.abs(skew) >= SEARCH_SECONDS - SEARCH_STEP then
                print("      ->  *** best offset is at the edge of the search range.")
                print("          The true offset is outside it; widen SEARCH_SECONDS.")
            end

            if travelled > 0.01 then
                print(string.format(
                    "      error is %.0f%% of how far the limb actually moved",
                    (alignedMean / travelled) * 100))
            end

            print(string.format("      VERDICT  %.3f studs  ->  %s",
                alignedMean, verdictFor(alignedMean)))

            if state.stale > 0 then
                print(string.format("      (%d report(s) older than history, dropped)",
                    state.stale))
            end
        end

        state.naive, state.aligned, state.travel = newAcc(), newAcc(), newAcc()
        state.offsets = {}
        state.stale = 0
    end

    if next(watched) == nil then
        print("")
        print("  [A] nobody watched -- join or respawn")
    end

    print("  -------------------------------------------------------------")
    print("  Give each a FULL window: stand still, walk straight, jump.")
    print("  Two balls sit on your right hand -- GREEN is yours, RED is the")
    print("  server's belief. The gap between them is this number, visible.")
    print("===============================================================")
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

    -- Its own remote, created and destroyed with the probe. Deliberately not
    -- routed through EventTape: throwaway diagnostic traffic has no business in
    -- the ordered, validated, rate-limited path real gameplay uses.
    remote = Instance.new("RemoteEvent")
    remote.Name = REMOTE_NAME
    remote.Parent = ReplicatedStorage
    table.insert(connections, remote.OnServerEvent:Connect(onClientReport))

    control = buildControl()

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
        sample(workspace:GetServerTimeNow())

        if sinceReport >= REPORT_SECONDS then
            report(sinceReport)
            sinceReport = 0
        end
    end))

    print("[LimbProbe v3] started -- now separates clock skew from real error.")
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
    if remote then
        remote:Destroy()
        remote = nil
    end
end

return LimbProbe
