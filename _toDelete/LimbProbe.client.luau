-- src/gameModes/dungeon/client/diagnostics/LimbProbe.client.luau
--
-- TEMPORARY. The client half of the limb-visibility probe. Delete alongside
-- the server half once the question is answered.
--
-- ============================================================================
-- ITS ONLY JOB
-- ============================================================================
--
-- Report, ~15 times a second:
--
--     "at server time T, my right hand was HERE relative to my root"
--
-- The server rewinds its own history to T and subtracts. That difference, in
-- studs, is the whole finding. Everything else in either file exists to make
-- that number trustworthy.
--
-- THIS FILE DELIBERATELY COMPUTES NOTHING. v1 had both halves measuring range
-- of motion independently and compared the two, which cannot work -- the
-- windows covered different seconds of a non-repeatable input (walking), so
-- the difference between them measured the walking, not the replication.
--
-- One side measures, one side reports. The comparison happens in exactly one
-- place, against one clock.
--
-- ============================================================================
-- WHY `workspace:GetServerTimeNow()` AND NOTHING ELSE
-- ============================================================================
--
-- It is synchronised across every peer, which `os.clock()` and `tick()` are
-- not -- those have per-process origins and would make the two halves compare
-- readings from unrelated timelines while looking perfectly reasonable.
--
-- It is also the same clock the real rewind uses, which is the point: this
-- probe is a miniature of production, not an analogy for it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FLAG_ATTRIBUTE = "DebugLimbProbe"
local REMOTE_NAME = "LimbProbeRemote"

-- Fast enough that a walk cycle is sampled many times over; slow enough that
-- this is not a meaningful amount of traffic. The server samples every frame
-- regardless, so this rate limits how many COMPARISONS happen, never how
-- finely the server's own history is recorded.
local REPORTS_PER_SECOND = 15

local player = Players.LocalPlayer

local function limbOf(character: Model): BasePart?
    return character:FindFirstChild("RightHand")
        or character:FindFirstChild("Right Arm")
end

local remote = ReplicatedStorage:WaitForChild(REMOTE_NAME, 30)
if not remote then
    -- Not a warning worth shouting about: the probe is off, or the server half
    -- has already been deleted, which is the intended end state for both files.
    return
end

local interval = 1 / REPORTS_PER_SECOND
local sinceSend = 0

RunService.Heartbeat:Connect(function(dt)
    if workspace:GetAttribute(FLAG_ATTRIBUTE) ~= true then
        return
    end

    sinceSend += dt
    if sinceSend < interval then
        return
    end
    sinceSend = 0

    local character = player.Character
    if not character then
        return
    end
    local root = character:FindFirstChild("HumanoidRootPart")
    local limb = character and limbOf(character)
    if not root or not limb then
        return
    end

    -- RELATIVE TO THE ROOT, never world space. A world reading changes when
    -- you walk, so comparing two world readings taken a round trip apart would
    -- measure how far you travelled in between and report it as replication
    -- error. Relative to the root, walking is invisible and only the limb
    -- moving with respect to the body registers.
    local rel = root.CFrame:Inverse() * limb.CFrame

    -- The timestamp is read at the same instant as the pose, not when the
    -- packet lands. The travel time is precisely what the server is rewinding
    -- to undo, so stamping on arrival would cancel out the thing being
    -- measured and this probe would always report success.
    remote:FireServer(workspace:GetServerTimeNow(), rel)
end)
