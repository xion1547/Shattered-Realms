-- src/shared/components/Identity.luau
--
-- Who this entity is. See Architecture-Reference.md Part 7.
-- The id is immutable after creation -- everything else in the game holds
-- references keyed on it.

local Identity = {}
Identity.__index = Identity

function Identity.new(entityType, id, ownerId)
    assert(type(entityType) == "string" and entityType ~= "", "[Identity] entityType required")
    assert(id ~= nil, "[Identity] id required")

    return setmetatable({
        _type = entityType,   -- "PLAYER" | "ENEMY" | "BOSS" | "PET" | "ITEM"
        _id = id,
        _ownerId = ownerId,   -- set for owned entities (a pet's player)
    }, Identity)
end

function Identity:getId()
    return self._id
end

function Identity:getType()
    return self._type
end

function Identity:getOwnerId()
    return self._ownerId
end

function Identity:isOwnedBy(ownerId)
    return self._ownerId ~= nil and self._ownerId == ownerId
end

return Identity
