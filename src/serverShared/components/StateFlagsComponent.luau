-- src/shared/components/StateFlagsComponent.luau
--
-- Composable status flags. See Architecture-Reference.md Part 9.
--
-- Flat and O(1) on purpose: this is read by every mutation in the game, so
-- it must never require walking a list or evaluating stack rules. That
-- performance shape is the actual reason these are not a Buff category,
-- despite Buff already declaring `category = "STATUS"`.
--
-- The component owns local truth: a flag is set or it is not, and a timed
-- flag knows its own expiry. WHO may set WHICH flag on WHICH entity is a
-- game rule and belongs to StateService.

local StateFlagsComponent = {}
StateFlagsComponent.__index = StateFlagsComponent

function StateFlagsComponent.new()
    return setmetatable({
        _flags = {},    -- flag -> true | expiryTimestamp
    }, StateFlagsComponent)
end

function StateFlagsComponent:has(flag)
    local value = self._flags[flag]
    if value == nil then
        return false
    end
    if value ~= true and os.clock() >= value then
        self._flags[flag] = nil
        return false
    end
    return true
end

-- `duration` nil means "until explicitly cleared".
function StateFlagsComponent:set(flag, duration)
    assert(type(flag) == "string", "[StateFlagsComponent] flag must be a string")
    if duration == nil then
        self._flags[flag] = true
    else
        assert(type(duration) == "number" and duration > 0, "[StateFlagsComponent] duration must be positive")
        self._flags[flag] = os.clock() + duration
    end
end

function StateFlagsComponent:clear(flag)
    self._flags[flag] = nil
end

function StateFlagsComponent:active()
    local out = {}
    for flag in pairs(self._flags) do
        if self:has(flag) then
            table.insert(out, flag)
        end
    end
    table.sort(out)
    return out
end

return StateFlagsComponent
