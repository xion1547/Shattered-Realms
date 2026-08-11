-- src/shared/components/Stats.luau
--
-- Base stats plus a version counter. See Architecture-Reference.md Part 7.
--
-- The version is what makes StatService's cache correct without anyone
-- remembering to call invalidate(): every mutation bumps it, and a cache
-- entry recorded against an older version is stale by definition. A missed
-- invalidate is impossible because there is no invalidate.

local Stats = {}
Stats.__index = Stats

function Stats.new(base)
    return setmetatable({
        _base = base and table.clone(base) or {},
        version = 0,
    }, Stats)
end

function Stats:getBase(statName)
    return self._base[statName] or 0
end

function Stats:setBase(statName, value)
    assert(type(value) == "number", "[Stats] stat values must be numbers")
    self._base[statName] = value
    self.version += 1
end

function Stats:addBase(statName, delta)
    self:setBase(statName, self:getBase(statName) + delta)
end

function Stats:all()
    return table.clone(self._base)
end

return Stats
