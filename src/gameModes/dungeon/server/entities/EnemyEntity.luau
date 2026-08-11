-- src/gameModes/dungeon/server/entities/EnemyEntity.luau
--
-- See Architecture-Reference.md Part 7. Deliberately the same shape as
-- PlayerEntity: the point of composition is that StatService, ResourceService
-- and the DamageResolution pipeline never learn which one they are holding.

local ServerStorage = game:GetService("ServerStorage")
local components = ServerStorage:WaitForChild("Shared"):WaitForChild("components")

local Identity = require(components:WaitForChild("Identity"))
local Stats = require(components:WaitForChild("Stats"))
local Buffs = require(components:WaitForChild("Buffs"))
local StateFlags = require(components:WaitForChild("StateFlags"))
local Equipment = require(components:WaitForChild("Equipment"))
local Inventory = require(components:WaitForChild("Inventory"))
local Resources = require(components:WaitForChild("Resources"))
local AIState = require(components:WaitForChild("AIState"))
local Spatial = require(components:WaitForChild("Spatial"))

local EnemyEntity = {}
EnemyEntity.__index = EnemyEntity

local nextId = 0
local function generateId()
    nextId += 1
    return "ENEMY_" .. nextId
end

-- `template` is a Content Layer definition (EnemyTemplates). It is read once,
-- here, to seed starting values -- and never consulted again. See Part 3's
-- Definition vs. Entity distinction.
function EnemyEntity.new(template)
    assert(type(template) == "table", "[EnemyEntity] a template is required")

    return setmetatable({
        identity = Identity.new("ENEMY", generateId()),
        stats = Stats.new(template.stats),
        buffs = Buffs.new(),
        stateFlags = StateFlags.new(),
        equipment = Equipment.new({ "weapon" }),
        inventory = Inventory.new({ maxSlots = template.lootSlots or 4 }),
        resources = Resources.new({ HP = template.hp, MaxHP = template.hp }),
        aiState = AIState.new(template.aiProfile),

        -- Unanchored until a body is spawned into the world. Same shape as
        -- PlayerEntity on purpose: the hit detection layer must never learn
        -- which one it is holding.
        spatial = Spatial.new(),

        lootTableId = template.lootTableId,
    }, EnemyEntity)
end

function EnemyEntity:getId()
    return self.identity:getId()
end

function EnemyEntity:destroy()
    -- TODO: release the world model and any per-entity connections.
end

return EnemyEntity
