-- src/serverShared/components/IdentityComponent.luau
--
-- Who this entity is. See Architecture-Reference.md Part 7.
-- The id is immutable after creation -- everything else in the game holds
-- references keyed on it.
--
-- The entity type is validated against IdentityRegistry rather than accepted
-- as a bare string. A typo used to produce an entity of type "ENEMEY" that
-- every type check silently disagreed with, forever, with nothing thrown.

local ServerStorage = game:GetService("ServerStorage")
local registries = ServerStorage:WaitForChild("Shared"):WaitForChild("registries")

local IdentityRegistry = require(registries:WaitForChild("IdentityRegistry"))

local IdentityComponent = {}
IdentityComponent.__index = IdentityComponent

-- The stored shape. Private -- callers hold an `Identity`, declared at the
-- bottom, which carries the methods too.
type State = {
    _type: string,
    -- Players are keyed by UserId (a number), spawned entities by a
    -- generated string ("ENEMY_1"). Both are legal, and code that assumes
    -- one is why ServerManager's add/remove pair could disagree.
    _id: string | number,
    _ownerId: (string | number)?,
}

function IdentityComponent.new(entityType: string, id: string | number, ownerId: (string | number)?)
    assert(id ~= nil, "[IdentityComponent] id required")
    assert(IdentityRegistry.isValidIdentity(entityType), string.format(
        "[IdentityComponent] unknown entity type: %s (see IdentityRegistry)",
        tostring(entityType)))

    return setmetatable({
        _type = entityType,
        _id = id,
        _ownerId = ownerId,   -- set for owned entities (a pet's player)
    } :: State, IdentityComponent)
end

function IdentityComponent.getId(self: State): string | number
    return self._id
end

function IdentityComponent.getType(self: State): string
    return self._type
end

function IdentityComponent.getOwnerId(self: State): (string | number)?
    return self._ownerId
end

function IdentityComponent.isOwnedBy(self: State, ownerId: string | number): boolean
    return self._ownerId ~= nil and self._ownerId == ownerId
end

-- EXPORTED, and declared AFTER the methods on purpose.
--
-- `export` is what makes this visible as `IdentityComponent.Identity` from
-- another file -- without it the type is file-local, which is why
-- EntityService could not see it.
--
-- Declared last because `typeof(setmetatable(...))` reads whatever methods
-- exist on IdentityComponent at this point in the file. Put this above the
-- methods and it resolves to a table with fields and no methods, so
-- `identity:getId()` stops type-checking while still running fine -- the
-- worst kind of wrong.
export type Identity = typeof(setmetatable({} :: State, IdentityComponent))

return IdentityComponent
