local EventType = require(script.Parent.EventType)

local Event = {}
Event.__index = Event

function Event.new(eventType, subType, data)
    local self = setmetatable({}, Event)
    self._eventType = Event.setEventType(self, eventType)
    self._subType = Event.setSubType(self, subType)
    self._data = data or {}
    self._timeStamp = os.time()
    return self
end

-- Accessor methods for the Event class
function Event:getEventType()
    return self._eventType
end

function Event:setEventType(eventType)
    if (eventType == nil or eventType == "") then
        error("Event type cannot be nil or empty")
    end
    if type(eventType) ~= "string" then
        error("Event type must be a string")
    end
    if (EventType[eventType] == nil) then
        error("Invalid event type: " .. tostring(eventType))
    end
    self._eventType = eventType
end

function Event:getSubType()
    return self._subType
end

function Event:setSubType(subType)
    if (subType == nil or subType == "") then
        error("SubType cannot be nil or empty")
    end
    if type(subType) ~= "string" then
        error("SubType must be a string")
    end
    if (EventType[self._eventType].subType[subType] == nil) then
        error("Invalid subType for event type " .. tostring(self._eventType) .. ": " .. tostring(subType))
    end
    self._subType = subType
end

function Event:getData()
    return self._data
end

function Event:getTimeStamp()
    return self._timeStamp
end

function Event:serialize()
    return {
        eventType = self._eventType,
        subType = self._subType,
        data = self._data,
        timeStamp = self._timeStamp
    }
end

function Event.deserialize(serializedEvent)
    if not serializedEvent or type(serializedEvent) ~= "table" then
        error("Invalid serialized event data")
    end

    local event = Event.new(
        serializedEvent.eventType,
        serializedEvent.subType,
        serializedEvent.data
    )
    event._timeStamp = serializedEvent.timeStamp
    return event
end

return Event