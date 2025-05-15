local Event = require(script.Parent.Parent:WaitForChild("Event"))
local EventType = require(script.Parent.Parent:WaitForChild("EventType"))
local AnimationEventType = require(script.Parent:WaitForChild("AnimationEventType"))

local AnimationEvent = setmetatable({}, { __index = Event })
AnimationEvent.__index = AnimationEvent

function AnimationEvent.new(subType, id, params)
    -- Type checking during creation
    assert(type(id) == AnimationEventType.id, "ID must be string")
    assert(EventType.ANIMATION.subType[subType], "Invalid subType")
    
    -- Apply default values for optional params
    local processedParams = {}
    for field, config in pairs(AnimationEventType.params) do
        -- If explicitly provided, validate the type
        if params[field] ~= nil then
            assert(type(params[field]) == config.type, 
                string.format("%s must be %s", field, config.type))
            processedParams[field] = params[field]
        elseif not config.optional then
            -- If not provided and not optional, apply default value
            processedParams[field] = config.default
        end
    end

    local self = Event.new(EventType.ANIMATION.type, subType , {
        id = id,
        params = processedParams  or {}
    })
    setmetatable(self, AnimationEvent)
    return self
end

function AnimationEvent:getId()
    return self:data().id
end
function AnimationEvent:setId(id)
    assert(type(id) == AnimationEventType.id, "ID must be string")
    self:data().id = id
end
function AnimationEvent:getParams()
    return self:data().params
end
function AnimationEvent:setParams(params)
    assert(type(params) == "table", "Params must be a table")
    self:data().params = params
end
function AnimationEvent:getRange()
    local range = self:getParams().range
    assert(typeof(range) == "number", "Range must exist in order to get it from AnimationEvent")
    return range
end
function AnimationEvent:setRange(range)
    assert(type(range) == "number", "Range must be a number")
    self:getParams().range = range
end
function AnimationEvent:getStatus()
    local status = self:getParams().status
    assert(typeof(status) == "string", "Status must exist in order to get it from AnimationEvent")
    return status
end
function AnimationEvent:setStatus(status)
    assert(type(status) == "string", "Status must be a string")
    self:getParams().status = status
end

function AnimationEvent:validate()
    if not EventType.ANIMATION.subType[self:getSubType()] then
        error("Invalid subType for AnimationEvent: " .. tostring(self:getSubType()))
    end
    if not self:getId().id then
        return false, "AnimationEvent must have an id"
    end
    return true
end

function AnimationEvent:serialize()
    local serializedData = Event.serialize(self)
    serializedData.data.id = self:getId()
    serializedData.data.params = self:getParams()
    return serializedData
end

function AnimationEvent.deserialize(serializedEvent)
    if not serializedEvent or type(serializedEvent) ~= "table" then
        error("Invalid serialized event data")
    end

    local event = Event.deserialize(serializedEvent)
    local animationEvent = AnimationEvent.new(
        event:getSubType(),
        event:data().id,
        event:data().params
    )
    animationEvent:setTimeStamp(event:getTimeStamp())
    return animationEvent
end

return AnimationEvent