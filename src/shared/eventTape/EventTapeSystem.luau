-- This module defines the EventTapeSystem class, which manages event tapes and their handlers.
-- It provides methods to add tapes to a buffer, process incoming tapes, and load event handlers from a specified folder.
local EventTapeSystem = {}
EventTapeSystem.__index = EventTapeSystem

function EventTapeSystem.new(manager, handlerFolder, eventDeserializer)
    local self = setmetatable({}, EventTapeSystem)
    self._manager = manager  -- Initialize an empty tape
    self._handlers = {}  -- Initialize an empty table for handlers
    self._eventBuffer = {}  -- Initialize an empty table for event buffer
    self._processingBuffer = {} -- Initialize an empty table for processing buffer
    self._eventDeserializer = eventDeserializer
    assert(self._eventDeserializer, "EventDeserializer is required")
    assert(self._eventDeserializer.deserialize, "EventDeserializer must have a deserialize method")
    assert(next(self._eventDeserializer._moduleCache) ~= nil, "EventDeserializer must have preloaded modules")
    assert(handlerFolder:IsA("Folder"), "Handler folder must be a Folder instance")
    self:_loadHandlers(handlerFolder)
    return self
end

function EventTapeSystem:getHandlers()
    return self._handlers
end

function EventTapeSystem:setManager(manager)
    self._manager = manager
end

function EventTapeSystem:getManager()
    return self._manager
end

function EventTapeSystem:setHandlers(handlerConfig)
    self._handlers[handlerConfig.eventType] = handlerConfig.handler
end

function EventTapeSystem:_loadHandlers(handlerFolder)
    for _, moduleScript in ipairs(handlerFolder:GetChildren()) do
        if moduleScript:IsA("ModuleScript") then
            local success, handlerConfig = pcall(require, moduleScript)
            if success and handlerConfig.eventType and handlerConfig.handler then
                self:setHandlers(handlerConfig)
            end
        end
    end
end

function EventTapeSystem:_validateEvent(event)
    assert(event:getTimeStamp(), "Event must have a timestamp")
    assert(event:getEventType(), "Event must have a type")
    assert(event:getData(), "Event must have data")
    assert(event:getSubType(), "Event must have a subtype")
end

function EventTapeSystem:addToBuffer(tape)
    assert(tape and tape.resetPointer, "Invalid tape object")
    for index, event in ipairs(tape:getEvents()) do
        self:_validateEvent(event)
        local deserialized = self._eventDeserializer:deserialize(event)
        self:_validateEvent(deserialized) -- Verify deserialization
        tape[index] = deserialized
    end
    table.insert(self._eventBuffer, {
        tape = tape,
        timeStamp = os.clock() -- For sorting tapes
    })
end

function EventTapeSystem:processBuffer()
    -- Atomic swap (thread safe)
    if #self._eventBuffer == 0 then return end
    self._processingBuffer, self._eventBuffer = self._eventBuffer, {}

    -- Sort the processing buffer by timestamp
    table.sort(self._processingBuffer, function(a, b) 
        return a.timeStamp < b.timeStamp
    end)

    -- Process tapes with error handling
    for _, bufferedTape in ipairs(self._processingBuffer) do
        local success, err = pcall(function()
            if not bufferedTape.tape:isEmpty() then
                self:processIncomingTape(bufferedTape.tape)
            end
        end)
        
        if not success then
            warn("[EventTapeSystem] Tape processing failed:", err)
        end
    end

    table.clear(self._processingBuffer) -- Clear the processing buffer
end

function EventTapeSystem:processIncomingTape(tape)
    if not tape or type(tape) ~= "table" then
        error("Invalid tape data")
    end

    tape:resetPointer()

    for _, event in ipairs(tape:getEvents()) do
        local eventType = event:getEventType()
        local handler = self._handlers[eventType]

        if handler then
            local success, err = pcall(handler, event)
            if not success then
                warn(string.format(
                    "[EventTapeSystem] Error processing event of type '%s': %s",
                    eventType,
                    err
                ))
            end
        else
            warn(string.format(
                "[EventTapeSystem] No handler found for event type '%s'",
                eventType
            ))
        end

        tape:advancePointer()
    end
end

return EventTapeSystem