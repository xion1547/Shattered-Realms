-- src/shared/components/Resources.luau
--
-- Every numeric quantity an entity carries: HP, Gold, EXP, ShieldHits.
-- See Architecture-Reference.md Part 8.
--
-- HP lives here, not in a separate Vitals component. Part 7's component
-- table still lists `Vitals | hp, maxHp, isDead`, which predates Part 8's
-- resolution -- every combat path in the document calls
-- ResourceService.drain(entity, "HP", ...) and ResourceDefinitions declares
-- an "HP" entry with `ceiling = "MaxHP"`. Two homes for one number is how
-- they drift apart, so there is only this one.
--
-- This component owns local truth only: values are numbers, and an unknown
-- id reads as 0. Floors, ceilings and behaviour tags are game rules and
-- belong to ResourceService.

local Resources = {}
Resources.__index = Resources

function Resources.new(initial)
    local values = {}
    if initial then
        for id, value in pairs(initial) do
            assert(type(value) == "number", "[Resources] values must be numbers")
            values[id] = value
        end
    end

    return setmetatable({
        _values = values,
        version = 0,
    }, Resources)
end

function Resources:get(resourceId)
    return self._values[resourceId] or 0
end

function Resources:has(resourceId)
    return self._values[resourceId] ~= nil
end

-- Raw set. ResourceService is the only legitimate caller: it has already
-- resolved floors, ceilings and behaviour tags before reaching here.
function Resources:setRaw(resourceId, value)
    assert(type(resourceId) == "string", "[Resources] resourceId must be a string")
    assert(type(value) == "number", "[Resources] value must be a number")
    self._values[resourceId] = value
    self.version += 1
end

function Resources:all()
    return table.clone(self._values)
end

return Resources
