-- src/shared/components/Buffs.luau
--
-- Active buffs on an entity. See Architecture-Reference.md Part 7.
--
-- Invariants owned here: no duplicate buff ids, and expired buffs are gone
-- before getAll() returns. Stack/replace/refresh/ignore resolution is a game
-- rule and belongs to BuffService.

local Buffs = {}
Buffs.__index = Buffs

function Buffs.new()
    return setmetatable({
        _buffs = {},    -- id -> Buff
        version = 0,
    }, Buffs)
end

local function isExpired(buff, now)
    return buff.expiresAt ~= nil and now >= buff.expiresAt
end

function Buffs:add(buff)
    assert(type(buff) == "table" and type(buff.id) == "string", "[Buffs] buff needs a string id")
    if self._buffs[buff.id] then
        return false, "DUPLICATE_ID"
    end
    self._buffs[buff.id] = buff
    self.version += 1
    return true
end

function Buffs:remove(buffId)
    if not self._buffs[buffId] then
        return false
    end
    self._buffs[buffId] = nil
    self.version += 1
    return true
end

function Buffs:get(buffId)
    local buff = self._buffs[buffId]
    if buff and isExpired(buff, os.clock()) then
        self:remove(buffId)
        return nil
    end
    return buff
end

-- Sweeps expiries before returning, so no caller ever sees a stale buff.
function Buffs:getAll()
    local now = os.clock()
    local out = {}
    for id, buff in pairs(self._buffs) do
        if isExpired(buff, now) then
            self._buffs[id] = nil
            self.version += 1
        else
            table.insert(out, buff)
        end
    end
    return out
end

function Buffs:findByType(buffType)
    for _, buff in ipairs(self:getAll()) do
        if buff.type == buffType then
            return buff
        end
    end
    return nil
end

return Buffs
