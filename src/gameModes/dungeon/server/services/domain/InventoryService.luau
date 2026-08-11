-- src/gameModes/dungeon/server/services/domain/InventoryService.luau
--
-- DOMAIN SERVICE. Cross-entity item rules and item-action requests.
-- See Architecture-Reference.md Parts 7 and 10.
--
-- Moved here from authority/ on evidence, not taste: Part 7's own worked
-- example has InventoryService.pickup calling DropService.isInRange and
-- ZoneService.canPickupHere. An authority service is a LEAF -- it may not
-- require a domain service -- so a service that inherently needs two of them
-- cannot be one. Equipment/Resource/State/Stat/Buff stay authority because
-- their operations are pure mechanics that never consult another domain.
--
-- The split with the Inventory component is the model for this whole
-- architecture in miniature:
--   component -> capacity, stack merging, stable slot indices (local truth,
--                checkable by looking at itself alone)
--   service   -> "can this player pick this up right now, given their zone
--                and range" (needs more than one thing at once)

local InventoryService = {}

function InventoryService:boot()
    -- TODO: declare item Facts once the vocabulary exists.
end

-- Routed from EventTape: eventType INVENTORY resolves here.
function InventoryService:OnAction(player, event)
    -- TODO: dispatch on event:getSubType() -- LOOT, EQUIP_GEAR, UNEQUIP_GEAR,
    -- EQUIP_ECHO, UNEQUIP_ECHO. Sub-type dispatch is this domain's own
    -- business from here on, not EventTape's (Part 12).
end

function InventoryService:add(entity, entry)
    -- TODO: game-rule checks, then entity.inventory:add(entry), then Fact.
    return false, "NOT_IMPLEMENTED"
end

function InventoryService:remove(entity, slotIndex, quantity)
    -- TODO
    return false, "NOT_IMPLEMENTED"
end

-- Cross-entity: this is the case that makes it a Service rather than a
-- component method, since it has to reason about two entities at once.
function InventoryService:transfer(fromEntity, toEntity, slotIndex, quantity)
    -- TODO
    return false, "NOT_IMPLEMENTED"
end

return InventoryService
