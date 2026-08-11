-- src/gameModes/dungeon/server/services/authority/BuffService.luau
--
-- AUTHORITY SERVICE. The single door to the Buffs component.
-- See Architecture-Reference.md Part 10.
--
-- A peer domain, not nested under Combat: a Buff is fundamentally "a
-- temporary modifier" with no inherent tie to combat, and Part 7's Buff
-- structure already declares `source = "ZONE"`. Nesting it would also make a
-- Hub-only buff structurally impossible once places exclude the Combat tree.

local BuffService = {}

function BuffService:boot()
    -- TODO: declare buff Facts once the vocabulary exists.
end

-- QUERY.
function BuffService:get(entity, buffType)
    return entity.buffs:findByType(buffType)
end

function BuffService:getAll(entity)
    return entity.buffs:getAll()
end

-- MUTATION. Resolves stackRule (STACK / REPLACE / REFRESH / IGNORE) before
-- touching the component -- the component only enforces "no duplicate ids".
function BuffService:apply(entity, buff, source)
    -- TODO: resolve the stack rule, set expiresAt from duration, add, then
    -- fire the Fact last.
end

function BuffService:remove(entity, buffId)
    -- TODO
end

-- Consumes a one-shot buff, e.g. duration = "UNTIL_HIT". The parry window
-- uses this: a conditional, combat-local modifier belongs here rather than
-- in StateFlags, which is for absolute gates every domain must check.
function BuffService:consume(entity, buffType)
    -- TODO
end

-- Scheduler entry point (Part 14). 60Hz -- expiry must be frame-accurate.
function BuffService:tick(deltaTime)
    -- TODO: sweep expiries and fire the corresponding Facts.
end

return BuffService
