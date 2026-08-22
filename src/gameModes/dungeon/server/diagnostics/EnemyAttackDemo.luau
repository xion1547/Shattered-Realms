-- src/gameModes/dungeon/server/diagnostics/EnemyAttackDemo.luau
--
-- TEMPORARY, and the loudest thing in the project. Every dummy turns to face
-- the nearest player and swings on a timer, so the enemy->player direction can
-- be watched instead of reasoned about.
--
-- IT ADDS NO NEW HIT DETECTION. Same TargetResolution, same Overlap, same
-- volumes -- the only thing that differs from a player swing is the one
-- argument HitDetection.md §6 says differs:
--
--     player attack   at = now - rewindWindow    (they already saw it)
--     enemy attack    at = now                   (no rewind; the telegraph
--                                                 is the compensation)
--
-- THERE IS NO TELEGRAPH HERE, and that is a real shortcut. A real enemy
-- attack fires a telegraph, waits ~1s, then executes -- that windup IS the
-- lag compensation and it is why enemy attacks need no rewind. This fires
-- instantly, so a laggy player would be hit by something they never saw
-- coming. Fine for watching numbers move on localhost; not a pattern to copy.
--
-- HP LIVES HERE, not in ResourceService, deliberately. `.resources["HP"]` is
-- the real home (Architecture Part 8) and ResourceService is a stub -- putting
-- a fake HP number into the real component would be worse than keeping an
-- obviously temporary one in an obviously temporary file.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local serverRoot = script.Parent.Parent

local targeting = serverRoot:WaitForChild("resolution"):WaitForChild("targeting")
local authority = serverRoot:WaitForChild("services"):WaitForChild("authority")

local HitVolume = require(targeting:WaitForChild("HitVolume"))
local TargetQuery = require(targeting:WaitForChild("TargetQuery"))
local TargetResolution = require(targeting:WaitForChild("TargetResolution"))
local EntityService = require(authority:WaitForChild("EntityService"))
local SpatialService = require(authority:WaitForChild("SpatialService"))
local AttackDebug = require(script.Parent:WaitForChild("AttackDebug"))

local EventType = require(game:GetService("ReplicatedStorage")
    :WaitForChild("eventTape"):WaitForChild("event"):WaitForChild("EventType"))

local DebugConfig = require(script.Parent:WaitForChild("DebugConfig"))

local EnemyAttackDemo = {}

local INTERVAL = 2.0        -- seconds between one enemy's swings
local MAX_HP = 100
local DAMAGE = 20
local RESPAWN_DELAY = 2.0   -- how long a "dead" player stays at 0 before reset

-- Each enemy gets one of these by index, so all three shapes are on screen at
-- once and can be told apart at a glance. Short reach on purpose: you should
-- have to walk INTO one to get hit, or there is nothing to demonstrate.
local ATTACKS = {
    {
        label = "CLAW",
        volume = HitVolume.resolve({
            shape = HitVolume.Shape.ARC,
            radius = 9,
            angle = 100,
            maxTargets = 4,
        }),
    },
    {
        label = "SLAM",
        volume = HitVolume.resolve({
            shape = HitVolume.Shape.BOX,
            size = Vector3.new(10, 4, 6),
            offset = CFrame.new(0, 0, -4),
            maxTargets = 4,
        }),
    },
    {
        label = "LUNGE",
        volume = HitVolume.resolve({
            shape = HitVolume.Shape.CAPSULE,
            length = 12,
            radius = 2,
            maxTargets = 2,
        }),
    },
}

EnemyAttackDemo._router = nil
EnemyAttackDemo._connection = nil
EnemyAttackDemo._schedule = {}    -- entity -> { nextAt, attack }
EnemyAttackDemo._hp = {}          -- Player -> number
EnemyAttackDemo._downUntil = {}   -- Player -> server time

-- Only players can be hit by this. Without it an enemy's arc catches the nine
-- dummies standing next to it, which is correct behaviour for a system with no
-- opinion about factions -- TargetResolution finds bodies in a volume and
-- deliberately has no concept of sides (HitDetection.md §9). The RULE about
-- who may hit whom belongs to the caller, which is here.
local function playersOnly(entity): boolean
    return entity.identity:getType() == "PLAYER"
end

local function hpOf(player: Player): number
    local hp = EnemyAttackDemo._hp[player]
    if hp == nil then
        hp = MAX_HP
        EnemyAttackDemo._hp[player] = hp
    end
    return hp
end

-- Turn the whole model to face its target, yaw only.
--
-- Worth doing rather than letting them swing at whatever they happen to face:
-- an ARC from an enemy pointing the wrong way never connects, and "the enemy
-- never hits me" would read as broken detection rather than as bad facing.
local function faceTowards(entity, target: Vector3)
    local model = entity.model
    if not model or not model.PrimaryPart then
        return
    end

    local from = model.PrimaryPart.Position
    local flat = Vector3.new(target.X, from.Y, target.Z)
    if (flat - from).Magnitude < 0.05 then
        return
    end

    model:PivotTo(CFrame.lookAt(from, flat))
end

local function nearestPlayerEntity(fromPosition: Vector3)
    local best, bestDistance = nil, math.huge

    for _, player in ipairs(Players:GetPlayers()) do
        local entity = EntityService:get(player.UserId)
        local spatial = entity and entity.spatial
        local pose = spatial and spatial:getCFrame()
        if pose then
            local distance = (pose.Position - fromPosition).Magnitude
            if distance < bestDistance then
                best, bestDistance = { player = player, entity = entity }, distance
            end
        end
    end

    return best, bestDistance
end

local function applyDamage(player: Player, amount: number, sourceId: string, label: string)
    local now = workspace:GetServerTimeNow()

    -- Already down and waiting to reset. Without this, ten enemies keep
    -- hammering a corpse and the log becomes unreadable.
    if (EnemyAttackDemo._downUntil[player] or 0) > now then
        return
    end

    local hp = math.max(0, hpOf(player) - amount)
    EnemyAttackDemo._hp[player] = hp

    if DebugConfig.get("DamageLog") then
        print(string.format(
            "[EnemyAttackDemo] %s hit %s for %d -- HP %d/%d",
            sourceId, player.Name, amount, hp, MAX_HP))
    end

    -- THE PUSH IS THE POINT. This is the server telling the client a fact it
    -- did not ask for, down the same EventTape remote everything else uses --
    -- not a bespoke RemoteEvent for health. Architecture Part 12 leaves the
    -- outbound shape open; this is the minimum that works.
    if EnemyAttackDemo._router then
        EnemyAttackDemo._router:push(player, EventType.COMBAT, {
            kind = "DAMAGED",
            amount = amount,
            hp = hp,
            maxHp = MAX_HP,
            source = sourceId,
            attack = label,
        })
    end

    if hp <= 0 then
        EnemyAttackDemo._downUntil[player] = now + RESPAWN_DELAY
        print(string.format("[EnemyAttackDemo] %s is down -- resetting in %.1fs",
            player.Name, RESPAWN_DELAY))

        task.delay(RESPAWN_DELAY, function()
            EnemyAttackDemo._hp[player] = MAX_HP
            if EnemyAttackDemo._router then
                EnemyAttackDemo._router:push(player, EventType.COMBAT, {
                    kind = "HEALED",
                    hp = MAX_HP,
                    maxHp = MAX_HP,
                })
            end
            print(string.format("[EnemyAttackDemo] %s reset to %d HP", player.Name, MAX_HP))
        end)
    end
end

local function swing(entity, attack)
    local spatial = entity.spatial
    local pose = spatial and spatial:getCFrame()
    if not pose then
        return
    end

    local nearest = nearestPlayerEntity(pose.Position)
    if not nearest then
        return
    end

    local targetPose = nearest.entity.spatial:getCFrame()
    if targetPose then
        faceTowards(entity, targetPose.Position)
    end

    -- `at = now`. NO REWIND, and this single argument is the entire difference
    -- between the two directions of combat.
    local query = TargetQuery.new({
        attacker = entity,
        volume = attack.volume,
        at = workspace:GetServerTimeNow(),
        filter = playersOnly,
    })

    local hits = TargetResolution.resolve(query)

    -- RED AND BRIEF, so incoming attacks are distinguishable from your own at
    -- a glance. Ten enemies swinging every two seconds is five volumes a
    -- second on screen; at the default amber and 0.35s they blend into your
    -- own swings and the display stops meaning anything.
    AttackDebug.show(query, hits, nil, {
        lifetime = 0.18,
        color = Color3.fromRGB(255, 70, 70),
    })

    for _, victim in ipairs(hits) do
        local player = Players:GetPlayerByUserId(victim.identity:getId())
        if player then
            applyDamage(player, DAMAGE, tostring(entity.identity:getId()), attack.label)
        end
    end
end

function EnemyAttackDemo.start(router)
    if EnemyAttackDemo._connection then
        return
    end

    EnemyAttackDemo._router = router

    -- Built from the SPATIAL ATTACH SET rather than from EntityService,
    -- because that is the set of things that can actually swing and be swung
    -- at -- and because it is the one place "is this thing in the world right
    -- now" is already answered (HitDetection.md §4: the watch list is the
    -- target list).
    --
    -- STAGGERED, not synchronised. Ten enemies firing on the same frame reads
    -- as one event and makes it impossible to tell which volume caught you.
    -- Spreading them across the interval turns a wall of output into a
    -- sequence.
    local now = workspace:GetServerTimeNow()
    local index = 0

    SpatialService:forEachAttached(function(entity)
        if entity.identity:getType() == "PLAYER" then
            return
        end

        index += 1
        EnemyAttackDemo._schedule[entity] = {
            nextAt = now + (index / 12) * INTERVAL,
            attack = ATTACKS[((index - 1) % #ATTACKS) + 1],
        }
    end)

    print(string.format(
        "[EnemyAttackDemo] %d enemies armed -- one swing each per %.1fs, %d damage, %d HP",
        index, INTERVAL, DAMAGE, MAX_HP))

    EnemyAttackDemo._connection = RunService.Heartbeat:Connect(function()
        if not DebugConfig.get("EnemyAttacks") then
            return
        end

        local serverNow = workspace:GetServerTimeNow()

        for entity, slot in pairs(EnemyAttackDemo._schedule) do
            if serverNow >= slot.nextAt then
                slot.nextAt = serverNow + INTERVAL
                swing(entity, slot.attack)
            end
        end
    end)
end

function EnemyAttackDemo.stop()
    if EnemyAttackDemo._connection then
        EnemyAttackDemo._connection:Disconnect()
        EnemyAttackDemo._connection = nil
    end
    table.clear(EnemyAttackDemo._schedule)
end

return EnemyAttackDemo
