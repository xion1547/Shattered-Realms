-- src/shared/components/InventoryComponent.luau
--
-- Ordered item slots with a capacity. See Architecture-Reference.md Part 7.
--
-- Invariants owned here: capacity, stable slot indices, stack merging. These
-- are InventoryComponent rules and hold whether the owner is a player, a pet, a boss
-- or a loot container. "Can this player pick this up right now, given zone
-- and range" is a game rule and belongs to InventoryService.

local InventoryComponent = {}
InventoryComponent.__index = InventoryComponent

function InventoryComponent.new(config)
    local maxSlots = config and config.maxSlots or 30
    assert(type(maxSlots) == "number" and maxSlots > 0, "[InventoryComponent] maxSlots must be positive")

    return setmetatable({
        _slots = {},        -- index -> { itemId, quantity, item }
        _maxSlots = maxSlots,
        _used = 0,
        version = 0,
    }, InventoryComponent)
end

function InventoryComponent:isFull()
    return self._used >= self._maxSlots
end

function InventoryComponent:getSlot(index)
    return self._slots[index]
end

function InventoryComponent:count()
    return self._used
end

function InventoryComponent:findStackable(itemId)
    for index, slot in pairs(self._slots) do
        if slot.itemId == itemId and slot.stackable then
            return index
        end
    end
    return nil
end

function InventoryComponent:nextEmptySlot()
    for index = 1, self._maxSlots do
        if self._slots[index] == nil then
            return index
        end
    end
    return nil
end

-- Returns (true) or (false, reason). A refusal here is a component-level
-- invariant, never a game rule.
function InventoryComponent:add(entry)
    assert(type(entry) == "table" and type(entry.itemId) == "string",
        "[InventoryComponent] entry needs a string itemId")

    local quantity = entry.quantity or 1

    if entry.stackable then
        local existing = self:findStackable(entry.itemId)
        if existing then
            self._slots[existing].quantity += quantity
            self.version += 1
            return true
        end
    end

    if self:isFull() then
        return false, "INVENTORY_FULL"
    end

    local index = self:nextEmptySlot()
    if not index then
        return false, "INVENTORY_FULL"
    end

    self._slots[index] = {
        itemId = entry.itemId,
        quantity = quantity,
        stackable = entry.stackable or false,
        item = entry.item,
    }
    self._used += 1
    self.version += 1
    return true
end

function InventoryComponent:removeSlot(index, quantity)
    local slot = self._slots[index]
    if not slot then
        return false, "EMPTY_SLOT"
    end

    quantity = quantity or slot.quantity
    if quantity > slot.quantity then
        return false, "INSUFFICIENT_QUANTITY"
    end

    slot.quantity -= quantity
    if slot.quantity <= 0 then
        self._slots[index] = nil
        self._used -= 1
    end
    self.version += 1
    return true
end

function InventoryComponent:getAll()
    local out = {}
    for index, slot in pairs(self._slots) do
        out[index] = slot
    end
    return out
end

return InventoryComponent
