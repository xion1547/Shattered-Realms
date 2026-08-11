-- src/gameModes/dungeon/server/diagnostics/PingProbe.server.luau
--
-- TEMPORARY DIAGNOSTIC. Delete this file and its client half when the
-- question below is answered. It is deliberately self-contained -- it
-- creates its own RemoteEvent rather than touching RemoteEventsEnum -- so
-- removing it is two file deletions and nothing else.
--
-- IT ANSWERS ONE QUESTION: does Player:GetNetworkPing() return a FULL ROUND
-- TRIP or ONE WAY, and in what unit?
--
-- The answer sets SpatialService.PING_TO_ROUND_TRIP, which is currently a
-- guess. A 2x error there is invisible: too small and legitimate hits miss
-- on any real connection, too large and players land hits on positions half
-- a second stale. Neither throws.
--
-- HOW IT MEASURES. The server stamps a server-clock time, sends it to the
-- client, the client echoes it straight back, and the server subtracts.
-- That figure is a true round trip plus however long the client took to
-- turn the message around -- up to one frame, ~16ms at 60fps. The bias is
-- always POSITIVE (measured >= true), so the MINIMUM across samples is the
-- closest estimate, which is why the verdict uses min rather than mean.
--
-- WHERE TO RUN IT. Not a solo Studio playtest -- there is no network there
-- and every figure will be ~0. Use Team Test, a published place, or turn on
-- Studio's incoming replication lag. The probe says so itself if the
-- latency it sees is too small to characterise.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local serverRoot = game.ServerScriptService:WaitForChild("Server")
local SpatialService = require(serverRoot:WaitForChild("services"):WaitForChild("authority")
    :WaitForChild("SpatialService"))
local Spatial = require(ServerStorage:WaitForChild("Shared"):WaitForChild("components")
    :WaitForChild("Spatial"))

local SAMPLES_WANTED = 20
local SAMPLE_INTERVAL = 0.75
local SPATIAL_LOG_INTERVAL = 2
local REWIND_DEMO_WINDOW = 0.2

-- Below this there is no signal to measure -- the ratio would be noise
-- divided by noise.
local MIN_MEASURABLE_RTT = 0.005

local remote = Instance.new("RemoteEvent")
remote.Name = "PingProbeRemote"
remote.Parent = ReplicatedStorage

-- player -> { rtts = {}, pings = {}, entity = <stub>, done = boolean }
local probes = {}

local function median(values: { number }): number
    if #values == 0 then
        return 0
    end
    local sorted = table.clone(values)
    table.sort(sorted)
    local mid = #sorted // 2
    if #sorted % 2 == 1 then
        return sorted[mid + 1]
    end
    return (sorted[mid] + sorted[mid + 1]) / 2
end

local function minimum(values: { number }): number
    local best = math.huge
    for _, v in ipairs(values) do
        if v < best then
            best = v
        end
    end
    return best
end

-- Buckets the ratio of GetNetworkPing()'s reading to the measured round
-- trip in milliseconds. The four candidates are 2x and 1000x apart, so
-- generous tolerances still cannot confuse them for one another.
local function verdict(ratio: number): (string, string)
    if ratio >= 0.7 and ratio <= 1.4 then
        return "FULL ROUND TRIP, in MILLISECONDS", "1 / 1000"
    elseif ratio >= 0.33 and ratio < 0.7 then
        return "ONE WAY, in MILLISECONDS", "2 / 1000"
    elseif ratio >= 0.0007 and ratio <= 0.0014 then
        return "FULL ROUND TRIP, in SECONDS", "1"
    elseif ratio >= 0.00033 and ratio < 0.0007 then
        return "ONE WAY, in SECONDS", "2"
    end
    return "INCONCLUSIVE -- ratio matches none of the four candidates", "?"
end

local function report(player: Player)
    local probe = probes[player]
    if not probe or probe.done then
        return
    end
    probe.done = true

    local rttMinSeconds = minimum(probe.rtts)
    local rttMinMs = rttMinSeconds * 1000
    local rttMedMs = median(probe.rtts) * 1000
    local pingMed = median(probe.pings)

    print("[PingProbe] ======================================================")
    print(string.format("[PingProbe]  RESULT for %s", player.Name))
    print(string.format("[PingProbe]    samples                     %d", #probe.rtts))
    print(string.format("[PingProbe]    measured round trip (min)   %.2f ms", rttMinMs))
    print(string.format("[PingProbe]    measured round trip (med)   %.2f ms", rttMedMs))
    print(string.format("[PingProbe]    GetNetworkPing() (median)   %.4f", pingMed))

    if rttMinSeconds < MIN_MEASURABLE_RTT then
        print("[PingProbe]")
        print("[PingProbe]    NO VERDICT -- round trip is under 5ms, so there is no")
        print("[PingProbe]    latency here to characterise. This is what a solo Studio")
        print("[PingProbe]    playtest looks like. Re-run under Team Test, a published")
        print("[PingProbe]    place, or Studio's incoming replication lag setting.")
        print("[PingProbe] ======================================================")
        return
    end

    local ratio = pingMed / rttMinMs
    local reading, factor = verdict(ratio)

    print("[PingProbe]")
    print(string.format("[PingProbe]    ping / roundTripMs          %.5f", ratio))
    print(string.format("[PingProbe]    ping / roundTripSeconds     %.2f", pingMed / rttMinSeconds))
    print("[PingProbe]")
    print(string.format("[PingProbe]    VERDICT  %s", reading))
    print(string.format("[PingProbe]    SpatialService PING_TO_ROUND_TRIP should be:  %s", factor))

    local current = SpatialService:constants().pingToRoundTrip
    print(string.format("[PingProbe]    it is currently:                              %s",
        tostring(current)))
    print("[PingProbe]")
    print("[PingProbe]    Cross-check this against the ping Roblox itself reports")
    print("[PingProbe]    (F9 console, Network tab). If GetNetworkPing() matches what")
    print("[PingProbe]    Roblox displays, Roblox is displaying the same figure -- that")
    print("[PingProbe]    tells you nothing about which one it is. The measured round")
    print("[PingProbe]    trip above is the independent number.")
    print("[PingProbe] ======================================================")
end

remote.OnServerEvent:Connect(function(player, sentAt)
    local probe = probes[player]
    if not probe or type(sentAt) ~= "number" then
        return
    end

    local roundTrip = workspace:GetServerTimeNow() - sentAt
    if roundTrip < 0 then
        return
    end

    local ok, ping = pcall(player.GetNetworkPing, player)
    if not ok or type(ping) ~= "number" then
        return
    end

    table.insert(probe.rtts, roundTrip)
    table.insert(probe.pings, ping)

    print(string.format(
        "[PingProbe] %s  sample %d/%d   roundTrip=%.2fms   GetNetworkPing()=%.4f",
        player.Name, #probe.rtts, SAMPLES_WANTED, roundTrip * 1000, ping))

    if #probe.rtts >= SAMPLES_WANTED then
        report(player)
    end
end)

-- The spatial half. A stub entity rather than a real PlayerEntity: this is
-- testing Spatial and SpatialService, not the entity wiring, and building a
-- second PlayerEntity alongside ServerManager's would be a confusing lie.
local function attachCharacter(player: Player, character: Model)
    local root = character:WaitForChild("HumanoidRootPart", 10)
    if not root then
        warn(string.format("[PingProbe] %s has no HumanoidRootPart", player.Name))
        return
    end

    local probe = probes[player]
    if not probe then
        return
    end

    probe.entity = { spatial = Spatial.new() }
    SpatialService:attach(probe.entity, root, 2.5)

    print(string.format("[PingProbe] attached %s  (attached entities: %d)",
        player.Name, SpatialService:attachedCount()))
end

Players.PlayerAdded:Connect(function(player)
    probes[player] = { rtts = {}, pings = {}, done = false }

    player.CharacterAdded:Connect(function(character)
        attachCharacter(player, character)
    end)
    if player.Character then
        attachCharacter(player, player.Character)
    end

    task.spawn(function()
        while player.Parent and probes[player] and not probes[player].done do
            remote:FireClient(player, workspace:GetServerTimeNow())
            task.wait(SAMPLE_INTERVAL)
        end
    end)
end)

Players.PlayerRemoving:Connect(function(player)
    local probe = probes[player]
    if probe and probe.entity then
        SpatialService:detach(probe.entity)
    end
    probes[player] = nil
end)

-- Proves the ring buffer and the interpolation actually work: walk around
-- and the rewound position should trail the live one by roughly your speed
-- times the window. Stand still and it should read ~0.
task.spawn(function()
    local constants = SpatialService:constants()
    print(string.format(
        "[PingProbe] SpatialService constants: sampleHz=%d maxRewind=%.2fs interp=%.2fs history=%d",
        constants.sampleHz, constants.maxRewind,
        constants.interpolationConstant, constants.historyLength))

    while true do
        task.wait(SPATIAL_LOG_INTERVAL)

        for player, probe in pairs(probes) do
            local entity = probe.entity
            if entity and SpatialService:isAttached(entity) then
                local now = workspace:GetServerTimeNow()
                local live = entity.spatial:getCFrame()
                local past = SpatialService:poseAt(entity, now - REWIND_DEMO_WINDOW)
                local oldest, newest = entity.spatial:span(now)

                if live and past then
                    print(string.format(
                        "[PingProbe] %s  samples=%d  buffer spans %.2fs..%.2fs ago  "
                            .. "moved %.2f studs in the last %.2fs  rewindWindow=%.3fs",
                        player.Name,
                        entity.spatial:sampleCount(),
                        oldest, newest,
                        (live.Position - past.Position).Magnitude,
                        REWIND_DEMO_WINDOW,
                        SpatialService:rewindWindowFor(player)))
                end
            end
        end
    end
end)

print("[PingProbe] running -- walk around, then read the RESULT block")
