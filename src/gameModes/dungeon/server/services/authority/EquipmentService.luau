-- src/gameModes/dungeon/server/services/authority/EquipmentService.luau
--
-- AUTHORITY SERVICE. The single door to the Equipment component.
-- See Architecture-Reference.md Part 10.
--
-- Deliberately independent of ResourceService: an equipped sword is not a
-- number that moves.
--
-- Equipped pets go through this same service -- a pet roster is bounded
-- slots with one occupant each, which is exactly what Equipment already is.
-- The difference is the side effect (a slot change spawns or despawns a live
-- entity), and a side effect is a game rule owned by a domain Service.

local EquipmentService = {}

function EquipmentService:boot()
    -- TODO: declare equip/unequip Facts once the vocabulary exists.
end

-- QUERY.
function EquipmentService:get(entity, slotName)
    return entity.equipment:get(slotName)
end

function EquipmentService:getAll(entity)
    return entity.equipment:getAll()
end

-- MUTATION. Returns the displaced occupant, if any, so the caller decides
-- where it goes -- this service does not assume an inventory exists.
function EquipmentService:attach(entity, slotName, item)
    -- TODO: validate the item may occupy this slot, attach, fire the Fact.
    -- No StatService.invalidate call is needed or wanted: the component's
    -- version bump is what makes the cache stale.
    return nil
end

function EquipmentService:detach(entity, slotName)
    -- TODO
    return nil
end

return EquipmentService
