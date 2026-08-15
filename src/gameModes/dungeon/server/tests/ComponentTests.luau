-- src/gameModes/dungeon/server/tests/ComponentTests.luau
--
-- Components own invariants, not just data (Part 7). These test the
-- invariants -- the things that must be true by looking at the component
-- alone, with no game rules involved.

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

local TestRunner = require(script.Parent:WaitForChild("TestRunner"))

return function()
    local t = TestRunner.new("Components")

    -- IdentityComponent ------------------------------------------------------------

    t:case("IdentityComponent exposes type, id and owner", function(a)
        local identity = IdentityComponent.new(IdentityRegistry.PET, "PET_1", 12345)
        a.equal(identity:getType(), IdentityRegistry.PET)
        a.equal(identity:getId(), "PET_1")
        a.isTrue(identity:isOwnedBy(12345))
        a.isFalse(identity:isOwnedBy(999))
        a.isFalse(IdentityComponent.new(IdentityRegistry.ENEMY, "E_1"):isOwnedBy(12345),
            "unowned entities belong to nobody")
    end)

    t:case("IdentityComponent rejects an entity type the registry does not declare", function(a)
        -- The whole reason the registry exists. A typo used to produce an
        -- entity of type "ENEMEY" that every later type check silently
        -- disagreed with, forever, with nothing thrown.
        a.throws(function() IdentityComponent.new("ENEMEY", "E_1") end, "unknown entity type")
        a.throws(function() IdentityComponent.new("", "E_1") end, "unknown entity type")
        a.throws(function() IdentityComponent.new(IdentityRegistry.ENEMY, nil) end, "id required")

        a.isTrue(IdentityRegistry.isValidIdentity(IdentityRegistry.BOSS))
        a.isFalse(IdentityRegistry.isValidIdentity("isValidIdentity"),
            "a function on the registry is not an entity type")
    end)

    -- StatsComponent ---------------------------------------------------------------

    t:case("StatsComponent bumps its version on every change", function(a)
        -- The version is what makes StatService's cache correct without
        -- anyone remembering to call invalidate().
        local stats = StatsComponent.new({ attack = 10 })
        a.equal(stats.version, 0)
        a.equal(stats:getBase("attack"), 10)
        a.equal(stats:getBase("nonexistent"), 0, "an unknown stat reads as 0")

        stats:setBase("attack", 15)
        a.equal(stats.version, 1, "a mutation must invalidate any cache recorded against version 0")

        stats:addBase("attack", 5)
        a.equal(stats:getBase("attack"), 20)
        a.equal(stats.version, 2)
    end)

    t:case("StatsComponent rejects non-numeric values", function(a)
        local stats = StatsComponent.new()
        a.throws(function() stats:setBase("attack", "lots") end, "must be numbers")
    end)

    -- ResourcesComponent -----------------------------------------------------------

    t:case("ResourcesComponent reads an unknown id as zero", function(a)
        local resources = ResourcesComponent.new({ Gold = 50 })
        a.equal(resources:get("Gold"), 50)
        a.equal(resources:get("RaidTokens"), 0, "an unknown resource reads as 0, it does not error")
        a.isTrue(resources:has("Gold"))
        a.isFalse(resources:has("RaidTokens"))
    end)

    t:case("ResourcesComponent holds HP like any other number", function(a)
        -- HP lives here, not in a separate Vitals component -- two homes for
        -- one number is how they drift apart.
        local resources = ResourcesComponent.new({ HP = 100, MaxHP = 100 })
        resources:setRaw("HP", 60)
        a.equal(resources:get("HP"), 60)
        a.equal(resources.version, 1)
    end)

    -- StateFlagsComponent ----------------------------------------------------------

    t:case("StateFlagsComponent sets and clears", function(a)
        local flags = StateFlagsComponent.new()
        a.isFalse(flags:has("FROZEN"))

        flags:set("FROZEN")
        a.isTrue(flags:has("FROZEN"))

        flags:clear("FROZEN")
        a.isFalse(flags:has("FROZEN"))
    end)

    t:case("a timed flag expires on read", function(a)
        local flags = StateFlagsComponent.new()
        flags:set("INVULNERABLE", 0.001)
        a.isTrue(flags:has("INVULNERABLE"), "still live immediately after being set")

        local deadline = os.clock() + 0.05
        repeat until os.clock() > deadline
        a.isFalse(flags:has("INVULNERABLE"), "an expired flag must read as absent")
    end)

    t:case("flags are independent and can co-occur", function(a)
        -- IMMOBILIZED and INVULNERABLE are distinct: one blocks acting, the
        -- other blocks damage, and both can be true at once.
        local flags = StateFlagsComponent.new()
        flags:set("IMMOBILIZED")
        flags:set("INVULNERABLE")
        a.isTrue(flags:has("IMMOBILIZED"))
        a.isTrue(flags:has("INVULNERABLE"))
        a.equal(#flags:active(), 2)
    end)

    t:case("StateFlagsComponent rejects a non-positive duration", function(a)
        local flags = StateFlagsComponent.new()
        a.throws(function() flags:set("FROZEN", 0) end, "must be positive")
    end)

    -- BuffsComponent ---------------------------------------------------------------

    t:case("BuffsComponent refuses duplicate ids", function(a)
        local buffs = BuffsComponent.new()
        a.isTrue(buffs:add({ id = "b1", type = "ATTACK_UP" }))

        local ok, reason = buffs:add({ id = "b1", type = "ATTACK_UP" })
        a.isFalse(ok)
        a.equal(reason, "DUPLICATE_ID")
    end)

    t:case("BuffsComponent sweeps expiries before returning", function(a)
        local buffs = BuffsComponent.new()
        buffs:add({ id = "live", type = "ATTACK_UP" })
        buffs:add({ id = "dead", type = "SPEED_UP", expiresAt = os.clock() - 1 })

        local all = buffs:getAll()
        a.equal(#all, 1, "an expired buff must never be visible to a caller")
        a.equal(all[1].id, "live")
        a.isNil(buffs:get("dead"))
    end)

    t:case("BuffsComponent bumps its version on add and remove", function(a)
        local buffs = BuffsComponent.new()
        buffs:add({ id = "b1", type = "ATTACK_UP" })
        a.equal(buffs.version, 1)
        a.isTrue(buffs:remove("b1"))
        a.equal(buffs.version, 2)
        a.isFalse(buffs:remove("b1"), "removing what is not there is not a mutation")
    end)

    t:case("BuffsComponent finds by type", function(a)
        local buffs = BuffsComponent.new()
        buffs:add({ id = "b1", type = "PARRY_WINDOW" })
        a.notNil(buffs:findByType("PARRY_WINDOW"), "the parry window is a Buff, not a StateFlag")
        a.isNil(buffs:findByType("NOTHING"))
    end)

    -- EquipmentComponent -----------------------------------------------------------

    t:case("EquipmentComponent only accepts declared slots", function(a)
        local equipment = EquipmentComponent.new({ "weapon", "armor" })
        a.isTrue(equipment:hasSlot("weapon"))
        a.isFalse(equipment:hasSlot("hat"))
        a.throws(function() equipment:attach("hat", {}) end, "undeclared slot")
    end)

    t:case("attach returns the displaced occupant", function(a)
        local equipment = EquipmentComponent.new({ "weapon" })
        local sword = { id = "SWORD" }
        local axe = { id = "AXE" }

        a.isNil(equipment:attach("weapon", sword), "an empty slot displaces nothing")
        a.equal(equipment:attach("weapon", axe), sword, "the caller decides where the old item goes")
        a.equal(equipment:get("weapon"), axe)
    end)

    t:case("EquipmentComponent bumps its version only on real changes", function(a)
        local equipment = EquipmentComponent.new({ "weapon" })
        equipment:attach("weapon", { id = "SWORD" })
        a.equal(equipment.version, 1)

        equipment:detach("weapon")
        a.equal(equipment.version, 2)

        equipment:detach("weapon")
        a.equal(equipment.version, 2, "detaching an empty slot is not a change")
    end)

    t:case("EquipmentComponent models a pet roster with numbered slots", function(a)
        -- PetRoster collapsed into this component: bounded slots with one
        -- occupant each is exactly what EquipmentComponent already is.
        local pets = EquipmentComponent.new({ "pet1", "pet2", "pet3" })
        a.equal(pets:firstEmptySlot(), "pet1")
        pets:attach("pet1", { id = "PET_A" })
        a.equal(pets:firstEmptySlot(), "pet2")
    end)

    -- InventoryComponent -----------------------------------------------------------

    t:case("InventoryComponent enforces its capacity", function(a)
        local inventory = InventoryComponent.new({ maxSlots = 2 })
        a.isTrue(inventory:add({ itemId = "A" }))
        a.isTrue(inventory:add({ itemId = "B" }))

        local ok, reason = inventory:add({ itemId = "C" })
        a.isFalse(ok)
        a.equal(reason, "INVENTORY_FULL")
        a.equal(inventory:count(), 2)
    end)

    t:case("InventoryComponent merges stackables instead of filling a slot", function(a)
        local inventory = InventoryComponent.new({ maxSlots = 2 })
        inventory:add({ itemId = "POTION", quantity = 3, stackable = true })
        inventory:add({ itemId = "POTION", quantity = 2, stackable = true })

        a.equal(inventory:count(), 1, "a stack must not consume a second slot")
        a.equal(inventory:getSlot(1).quantity, 5)
    end)

    t:case("a non-stackable item takes its own slot", function(a)
        local inventory = InventoryComponent.new({ maxSlots = 3 })
        inventory:add({ itemId = "SWORD" })
        inventory:add({ itemId = "SWORD" })
        a.equal(inventory:count(), 2)
    end)

    t:case("InventoryComponent keeps slot indices stable across removal", function(a)
        local inventory = InventoryComponent.new({ maxSlots = 3 })
        inventory:add({ itemId = "A" })
        inventory:add({ itemId = "B" })
        inventory:add({ itemId = "C" })

        inventory:removeSlot(2)
        a.equal(inventory:getSlot(1).itemId, "A")
        a.isNil(inventory:getSlot(2), "the hole stays a hole")
        a.equal(inventory:getSlot(3).itemId, "C", "C must not shuffle down into slot 2")
        a.equal(inventory:nextEmptySlot(), 2, "the freed slot is the next one filled")
    end)

    t:case("InventoryComponent rejects over-removal", function(a)
        local inventory = InventoryComponent.new({ maxSlots = 2 })
        inventory:add({ itemId = "POTION", quantity = 2, stackable = true })

        local ok, reason = inventory:removeSlot(1, 5)
        a.isFalse(ok)
        a.equal(reason, "INSUFFICIENT_QUANTITY")

        ok, reason = inventory:removeSlot(2)
        a.isFalse(ok)
        a.equal(reason, "EMPTY_SLOT")
    end)

    t:case("the same component works for any entity type", function(a)
        -- The whole point of composition: nothing here knows or cares
        -- whether its owner is a player, a pet, a boss or a loot container.
        local playerBag = InventoryComponent.new({ maxSlots = 30 })
        local petBag = InventoryComponent.new({ maxSlots = 5 })
        a.isTrue(playerBag:add({ itemId = "A" }))
        a.isTrue(petBag:add({ itemId = "A" }))
    end)

    return t:run()
end
