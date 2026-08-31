-- src/gameModes/dungeon/server/entities/EnemyEntity.luau
--
-- See Architecture-Reference.md Part 7. Deliberately the same shape as
-- PlayerEntity: the point of composition is that StatService, ResourceService
-- and the DamageResolution pipeline never learn which one they are holding.

local ServerStorage = game:GetService("ServerStorage")
local components = ServerStorage:WaitForChild("Shared"):WaitForChild("components")

local IdentityRegistry = require(ServerStorage:WaitForChild("Shared")
    :WaitForChild("registries"):WaitForChild("IdentityRegistry"))

local IdentityComponent = require(components:WaitForChild("IdentityComponent"))
local StatsComponent = require(components:WaitForChild("StatsComponent"))
local BuffsComponent = require(components:WaitForChild("BuffsComponent"))
local StateFlagsComponent = require(components:WaitForChild("StateFlagsComponent"))
local EquipmentComponent = require(components:WaitForChild("EquipmentComponent"))
local InventoryComponent = require(components:WaitForChild("InventoryComponent"))
local ResourcesComponent = require(components:WaitForChild("ResourcesComponent"))
local AIStateComponent = require(components:WaitForChild("AIStateComponent"))
local SpatialComponent = require(components:WaitForChild("SpatialComponent"))

local EnemyEntity = {}
EnemyEntity.__index = EnemyEntity

local nextId = 0
local function generateId()
    nextId += 1
    return "ENEMY_" .. nextId
end

-- `template` is a Content Layer definition (`definitions/enemies/<Name>.luau`,
-- handed over by `DefinitionLoader`). It is read once,
-- here, to seed starting values -- and never consulted again. See Part 3's
-- Definition vs. Entity distinction.
function EnemyEntity.new(template)
    assert(type(template) == "table", "[EnemyEntity] a template is required")

    return setmetatable({
        identity = IdentityComponent.new(IdentityRegistry.ENEMY, generateId()),
        stats = StatsComponent.new(template.stats),
        buffs = BuffsComponent.new(),
        stateFlags = StateFlagsComponent.new(),
        equipment = EquipmentComponent.new({ "weapon" }),
        inventory = InventoryComponent.new({ maxSlots = template.lootSlots or 4 }),
        resources = ResourcesComponent.new({ HP = template.hp, MaxHP = template.hp }),
        aiState = AIStateComponent.new(template.aiProfile),

        -- Unanchored until a body is spawned into the world. Same shape as
        -- PlayerEntity on purpose: the hit detection layer must never learn
        -- which one it is holding.
        spatial = SpatialComponent.new(),

        lootTableId = template.lootTableId,
    }, EnemyEntity)
end

-- NO getId() SHORTCUT HERE, DELIBERATELY. An id comes from the identity
-- component and only from there: `entity.identity:getId()`. A convenience
-- method meant two valid spellings existed for the same value, and the
-- codebase had already split -- StatService, SkillService, AIService and
-- TargetResolution went through the component while ServerManager took the
-- shortcut. One path removes the choice.
--
-- It also keeps the Entity type honest: with no method to declare, an entity
-- is exactly "a thing holding an identity", which a bare table satisfies.

function EnemyEntity:destroy()
    -- TODO: release the world model and any per-entity connections.
end

return EnemyEntity
