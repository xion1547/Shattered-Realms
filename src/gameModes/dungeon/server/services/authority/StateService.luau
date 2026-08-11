-- src/gameModes/dungeon/server/services/authority/StateService.luau
--
-- AUTHORITY SERVICE. The single gate every mutating Service checks.
-- See Architecture-Reference.md Part 9.
--
-- It stores nothing: the data lives on each entity's StateFlags component.
-- This service exists so there is exactly ONE door -- if every damage source
-- read entity.stateFlags directly, the first source that forgot would make
-- INVULNERABLE mean "immune to whatever remembered to look."
--
-- The gate is on the hot path of every mutation in the game, so `has` must
-- stay O(1) and unconditional. That is the actual reason these flags are not
-- a Buff category.

local StateService = {}

local FLAGS = {
    FROZEN = true,          -- cannot act; AI ticking skipped; timers frozen
    DYING = true,           -- one-way lock; rejects damage, buffs, AI
    INVULNERABLE = true,    -- cannot take damage from any source
    IMMOBILIZED = true,     -- cannot move or act, but can still be damaged
}

function StateService:boot()
    -- TODO: declare per-flag Facts once the vocabulary generates them.
end

function StateService:isDeclaredFlag(flag)
    return FLAGS[flag] == true
end

-- QUERY. The hot path.
function StateService:has(entity, flag)
    return entity.stateFlags:has(flag)
end

-- The one shared check every source calls before reducing HP, applying a
-- buff, or letting an AI act.
function StateService:canBeActedOn(entity)
    return not (entity.stateFlags:has("INVULNERABLE") or entity.stateFlags:has("DYING"))
end

function StateService:canAct(entity)
    return not (entity.stateFlags:has("FROZEN")
        or entity.stateFlags:has("DYING")
        or entity.stateFlags:has("IMMOBILIZED"))
end

-- MUTATION.
function StateService:set(entity, flag, duration, source)
    assert(self:isDeclaredFlag(flag), "[StateService] undeclared flag: " .. tostring(flag))
    -- TODO: DYING is a one-way lock and must refuse to be cleared. Enforce
    -- that here, then fire the Fact as the last step.
end

function StateService:clear(entity, flag, source)
    assert(self:isDeclaredFlag(flag), "[StateService] undeclared flag: " .. tostring(flag))
    -- TODO
end

return StateService
