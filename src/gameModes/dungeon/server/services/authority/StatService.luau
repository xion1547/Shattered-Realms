-- src/gameModes/dungeon/server/services/authority/StatService.luau
--
-- AUTHORITY SERVICE. The only place a final stat is computed.
-- See Architecture-Reference.md Part 10.
--
-- Pure QUERY: never mutates, never persists, never fires a Signal. That is
-- what makes it safe to call from inside a DamageResolution step, where no
-- step is allowed to touch the world.
--
-- Nothing reads raw stats for a game decision. Nothing. If any service
-- boundary is violated, bugs appear in one system; if this one is, every
-- system that touches combat, UI, AI and equipment shows a different wrong
-- number with no single source to trace.

local StatService = {}

StatService._cache = {}   -- entityId -> statName -> { value, versions... }

function StatService:boot()
    -- Nothing to declare: a query service owns no Facts.
end

-- Version-based invalidation, not explicit invalidate() calls. An explicit
-- call can be forgotten, and a forgotten one means stale stats with no
-- error. A version mismatch cannot be forgotten because nobody has to
-- remember anything.
function StatService:compute(entity, statName)
    local entityId = entity.identity:getId()
    local perEntity = self._cache[entityId]
    local cached = perEntity and perEntity[statName]

    if cached
        and cached.statVersion == entity.stats.version
        and cached.buffVersion == entity.buffs.version
        and cached.equipVersion == entity.equipment.version
    then
        return cached.value
    end

    -- TODO: base + equipment contributions + buff modifiers + level scaling.
    local value = entity.stats:getBase(statName)

    if not perEntity then
        perEntity = {}
        self._cache[entityId] = perEntity
    end
    perEntity[statName] = {
        value = value,
        statVersion = entity.stats.version,
        buffVersion = entity.buffs.version,
        equipVersion = entity.equipment.version,
    }

    return value
end

function StatService:forget(entity)
    self._cache[entity.identity:getId()] = nil
end

return StatService
