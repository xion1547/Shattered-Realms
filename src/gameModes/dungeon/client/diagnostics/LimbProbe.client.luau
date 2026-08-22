-- src/gameModes/dungeon/client/diagnostics/LimbProbe.client.luau
--
-- TEMPORARY. The client half of the limb-visibility probe. Delete alongside
-- the server half once the question is answered.
--
-- ============================================================================
-- WHY BOTH HALVES ARE NEEDED
-- ============================================================================
--
-- The server half alone can say "I see the limb move X studs." That number is
-- meaningless on its own, because there is nothing to compare it to. A limb
-- that genuinely travels 1.9 studs and is seen as 1.9 is a pass; one that
-- travels 1.9 and is seen as 0.2 is a heavily damped read that would LOOK like
-- a pass under a threshold test.
--
--     client 1.883, server 1.881   ->  faithful
--     client 1.883, server 0.000   ->  invisible.  motion = LIVE is dead for players
--     client 1.883, server 0.204   ->  DAMPED. The worst outcome, because it
--                                      passes a naive test and produces
--                                      hitboxes that are subtly wrong forever
--
-- The third row is the reason this file exists. A yes/no test cannot see it.
--
-- ============================================================================
-- IT ALSO TESTS THE REVERSE DIRECTION
-- ============================================================================
--
-- The server half drives a control rig's joint from the server. Whether THAT
-- reaches the client is the boss case: a server-animated enemy whose limbs
-- every client must see in the right place. Same measurement, opposite way.
--
-- Reads the flag straight off Workspace rather than through DebugConfig --
-- that module is server-only, and the attribute it publishes replicates.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local FLAG_ATTRIBUTE = "DebugLimbProbe"
local REPORT_SECONDS = 3.0
local MOVEMENT_EPSILON = 0.05

local player = Players.LocalPlayer

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
    return math.max(dx, dy, dz) >= MOVEMENT_EPSILON and "MOVING" or "STATIC"
end

local function describe(label: string, range): string
    local dx, dy, dz = spans(range)
    return string.format(
        "    %-22s range  X %6.3f  Y %6.3f  Z %6.3f   ->  %s",
        label, dx, dy, dz, verdict(range))
end

local function relativeTo(root: BasePart, part: BasePart): CFrame
    return root.CFrame:Inverse() * part.CFrame
end

-- Same dual-class lookup as the server half: an upgraded R15 rig carries
-- AnimationConstraints rather than Motor6Ds, and asking only for one would
-- report a missing joint as if that were a result.
local function findJoint(part: BasePart): Instance?
    for _, child in ipairs(part:GetChildren()) do
        if child:IsA("Motor6D") or child:IsA("AnimationConstraint") then
            return child
        end
    end
    return nil
end

local function isIdentity(cf: CFrame): boolean
    local p = cf.Position
    if math.abs(p.X) > 1e-4 or math.abs(p.Y) > 1e-4 or math.abs(p.Z) > 1e-4 then
        return false
    end
    local look = cf.LookVector
    return math.abs(look.X) < 1e-4 and math.abs(look.Y) < 1e-4
        and math.abs(look.Z + 1) < 1e-4
end

local limbRange = newRange()
local markerRange = newRange()
local controlRange = newRange()
local transformIdentity, transformTotal = 0, 0
local states = {}

local function currentParts()
    local character = player.Character
    if not character then
        return nil
    end
    local root = character:FindFirstChild("HumanoidRootPart")
    local limb = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
    if not root or not limb then
        return nil
    end
    return character, root, limb
end

local function dominantState(): string
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
        "-------- LimbProbe CLIENT  %.1fs window -------------------------",
        window))
    print(string.format("  samples %d   humanoid mostly %s",
        limbRange.count, dominantState()))
    print(describe("limb rel root", limbRange))
    print(describe("welded marker rel root", markerRange))

    if transformTotal > 0 then
        print(string.format(
            "    %-22s identity on %d/%d samples   ->  %s",
            "joint.Transform", transformIdentity, transformTotal,
            transformIdentity == transformTotal and "NEVER WRITTEN" or "WRITTEN"))
    else
        print("    joint.Transform        no joint found")
    end

    print(describe("CONTROL limb rel root", controlRange))
    print("    ^ server-driven rig, seen from here. This is the BOSS case.")
    print("  Compare these numbers against the server block printed above.")
    print("----------------------------------------------------------------")

    limbRange = newRange()
    markerRange = newRange()
    controlRange = newRange()
    transformIdentity, transformTotal = 0, 0
    states = {}
end

local sinceReport = 0

RunService.Heartbeat:Connect(function(dt)
    if workspace:GetAttribute(FLAG_ATTRIBUTE) ~= true then
        return
    end

    local character, root, limb = currentParts()
    if character then
        feed(limbRange, relativeTo(root, limb).Position)

        local marker = character:FindFirstChild("LimbProbe_Client")
        if marker and marker:IsA("BasePart") then
            feed(markerRange, relativeTo(root, marker).Position)
        end

        local joint = findJoint(limb)
        if joint then
            transformTotal += 1
            if isIdentity(joint.Transform) then
                transformIdentity += 1
            end
        end

        local humanoid = character:FindFirstChildOfClass("Humanoid")
        local name = humanoid and humanoid:GetState().Name or "?"
        states[name] = (states[name] or 0) + 1
    end

    local controlModel = workspace:FindFirstChild("LimbProbeControl")
    if controlModel then
        local controlRoot = controlModel:FindFirstChild("ControlRoot")
        local controlLimb = controlModel:FindFirstChild("ControlLimb")
        if controlRoot and controlLimb then
            feed(controlRange, relativeTo(controlRoot, controlLimb).Position)
        end
    end

    sinceReport += dt
    if sinceReport >= REPORT_SECONDS then
        report(sinceReport)
        sinceReport = 0
    end
end)
