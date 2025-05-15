local EventTape = {}
EventTape.__index = EventTape

function EventTape.new()
    local self = setmetatable({}, EventTape)
    self._events = {}
    self._pointer = 0
    return self
end

function EventTape:getEvents()
    assert(typeof(self._events) == "table", "Events should be stored in a table")
    return self._events
end

function EventTape:getPointer()
    assert(typeof(self._pointer) == "number", "Pointer should be a number")
    return self._pointer
end

function EventTape:addEvent(event)
    assert(typeof(event) == "table", "Event must be a table")
    table.insert(self._events, event)
end

function EventTape:advancePointer()
    assert(typeof(self._pointer) == "number", "Pointer should be a number")
    self._pointer = self._pointer + 1
end

function EventTape:isEmpty()
    return #self._events == 0
end

function EventTape:resetPointer()
    self._pointer = 0
end

function EventTape:serialize()
    return {
        events = self._events,
        pointer = self._pointer
    }
end

function EventTape.deserialize(serializedTape)
    if not serializedTape or type(serializedTape) ~= "table" then
        error("Invalid serialized tape data")
    end

    local tape = EventTape.new()
    tape._events = serializedTape.events or {}
    tape._pointer = serializedTape.pointer or 0
    return tape
end

return EventTape