-- src/shared/components/ResourcesComponent.luau
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

local ResourcesComponent = {}
ResourcesComponent.__index = ResourcesComponent

function ResourcesComponent.new(initial)
    local values = {}
    if initial then
        for id, value in pairs(initial) do
            assert(type(value) == "number", "[ResourcesComponent] values must be numbers")
            values[id] = value
        end
    end

    return setmetatable({
        _values = values,
        version = 0,
    }, ResourcesComponent)
end

function ResourcesComponent:get(resourceId)
    return self._values[resourceId] or 0
end

function ResourcesComponent:has(resourceId)
    return self._values[resourceId] ~= nil
end

-- Raw set. ResourceService is the only legitimate caller: it has already
-- resolved floors, ceilings and behaviour tags before reaching here.
function ResourcesComponent:setRaw(resourceId, value)
    assert(type(resourceId) == "string", "[ResourcesComponent] resourceId must be a string")
    assert(type(value) == "number", "[ResourcesComponent] value must be a number")
    self._values[resourceId] = value
    self.version += 1
end

function ResourcesComponent:all()
    return table.clone(self._values)
end

return ResourcesComponent
