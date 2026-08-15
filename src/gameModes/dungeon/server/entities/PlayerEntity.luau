-- src/gameModes/dungeon/server/entities/PlayerEntity.luau
--
-- A container assembled from Components, with no logic of its own beyond
-- what its Components enforce. See Architecture-Reference.md Part 7.
--
-- The previous version was a pre-architecture object: flat health/gold/level
-- fields plus takeDamage/gainGold/levelUp methods that mutated them
-- directly. Every one of those methods was a second door into state that
-- bypassed validation -- which is exactly what "ResourceService is the only
-- door into Gold" (Part 11.5) depends on not existing. There are no mutation
-- methods here. Services mutate Components; Entities just hold them.

-- Components live in ServerStorage, never ReplicatedStorage: an entity's
-- internals are server truth, and anything in ReplicatedStorage can be
-- dumped by a client (Part 13).
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
local SpatialComponent = require(components:WaitForChild("SpatialComponent"))

local PlayerEntity = {}
PlayerEntity.__index = PlayerEntity

-- TODO: this composition should be declared in the Content Layer as a
-- component manifest per entity type, so a variant is a data edit rather
-- than a new entity module (Part 7). Hardcoded until a third entity type
-- needs a variation.
function PlayerEntity.new(player: Player)
    assert(player, "[PlayerEntity] a Player is required")

    return setmetatable({
        player = player,

        identity = IdentityComponent.new(IdentityRegistry.PLAYER, player.UserId),
        stats = StatsComponent.new({ attack = 10, defense = 5, speed = 8, critChance = 0.05 }),
        buffs = BuffsComponent.new(),
        stateFlags = StateFlagsComponent.new(),
        equipment = EquipmentComponent.new({ "weapon", "armor", "accessory" }),
        inventory = InventoryComponent.new({ maxSlots = 30 }),
        resources = ResourcesComponent.new({ HP = 100, MaxHP = 100, Gold = 0, EXP = 0, Level = 1 }),

        -- Unanchored until a character spawns. SpatialService:attach binds
        -- it to a body and starts sampling; nothing here knows when that is.
        spatial = SpatialComponent.new(),

        -- Equipped pets are EquipmentComponent slots, not a PetRoster component.
        pets = EquipmentComponent.new({ "pet1", "pet2", "pet3", "pet4", "pet5" }),
    }, PlayerEntity)
end

-- NO getId() SHORTCUT HERE, DELIBERATELY -- see the note in EnemyEntity.
-- An id comes from `entity.identity:getId()` and nowhere else.

-- Releases anything holding a reference to this entity. Called by
-- SessionService on leave, before the session Fact is announced.
function PlayerEntity:destroy()
    -- TODO: disconnect per-entity Signal handles and cancel pending timers
    -- once anything creates them.
    self.player = nil
end

return PlayerEntity
