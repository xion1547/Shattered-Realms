-- AnimationEventType.lua
local AnimationEventType = {
    -- Required fields
    id = "string",
    subType = "string",
    
    -- Optional fields (with type and default values)
    params = {
        range = { type = "number", optional = true },
        speed = { type = "number", optional = true, default = 1.0 },
        looped = { type = "boolean", optional = true },
        status = { type = "string", optional = true },
    }
}

return setmetatable(AnimationEventType, {
    __index = function(_, k)
        error(string.format("Invalid AnimationEventType field: %s", k))
    end
})