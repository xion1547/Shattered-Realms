-- src/shared/components/EquipmentComponent.luau
--
-- Named slots holding entities. See Architecture-Reference.md Part 7.
--
-- Equipped pets use this too, with numbered slots -- the bookkeeping for a
-- pet roster (bounded slots, one occupant each, a capacity ceiling) is
-- identical to equipment, so PetRoster collapsed into this component. What
-- differs is the side effect (equipping a pet spawns an entity), and a side
-- effect is a game rule that belongs to a Service.

local EquipmentComponent = {}
EquipmentComponent.__index = EquipmentComponent

function EquipmentComponent.new(slotNames)
    assert(type(slotNames) == "table" and #slotNames > 0, "[EquipmentComponent] declare at least one slot")

    local slots, allowed = {}, {}
    for _, name in ipairs(slotNames) do
        assert(type(name) == "string", "[EquipmentComponent] slot names must be strings")
        slots[name] = nil
        allowed[name] = true
    end

    return setmetatable({
        _slots = slots,
        _allowed = allowed,
        _order = table.clone(slotNames),
        version = 0,
    }, EquipmentComponent)
end

function EquipmentComponent:hasSlot(slotName)
    return self._allowed[slotName] == true
end

function EquipmentComponent:get(slotName)
    assert(self:hasSlot(slotName), "[EquipmentComponent] undeclared slot: " .. tostring(slotName))
    return self._slots[slotName]
end

-- Returns the previous occupant so a Service can decide what to do with it.
function EquipmentComponent:attach(slotName, item)
    assert(self:hasSlot(slotName), "[EquipmentComponent] undeclared slot: " .. tostring(slotName))
    local previous = self._slots[slotName]
    self._slots[slotName] = item
    self.version += 1
    return previous
end

function EquipmentComponent:detach(slotName)
    assert(self:hasSlot(slotName), "[EquipmentComponent] undeclared slot: " .. tostring(slotName))
    local previous = self._slots[slotName]
    if previous == nil then
        return nil
    end
    self._slots[slotName] = nil
    self.version += 1
    return previous
end

function EquipmentComponent:firstEmptySlot()
    for _, name in ipairs(self._order) do
        if self._slots[name] == nil then
            return name
        end
    end
    return nil
end

function EquipmentComponent:getAll()
    local out = {}
    for _, name in ipairs(self._order) do
        if self._slots[name] ~= nil then
            out[name] = self._slots[name]
        end
    end
    return out
end

return EquipmentComponent
