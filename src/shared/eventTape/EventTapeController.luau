local RemoteEventsEnum = require(script.Parent.Parent:WaitForChild("remoteEvents"):WaitForChild("RemoteEventsEnum"))

-- shared/eventTape/EventTapeController.lua
local EventTapeController = {}
EventTapeController.__index = EventTapeController

function EventTapeController.new(eventSystem)
    local self = setmetatable({}, EventTapeController)
    self._eventSystem = eventSystem
    self._eventHandlers = {} -- { [RemoteEvent] = handlerFunction }
    self._buffers = {} -- { [eventType] = {tapes} }
    return self
end

-- Call this to activate combat processing
function EventTapeController:enableCombatHeartbeat()
    game:GetService("RunService").Heartbeat:Connect(function()
        self:_processCombatBuffer()
    end)
end

-- Dynamic event registration
function EventTapeController:registerEvent(remoteEvent, handler)
    self._eventHandlers[remoteEvent] = handler or function(tape)
        self:_defaultEventHandler(remoteEvent.Name, tape)
    end
    self:_setupRemoteEvent(remoteEvent)
end

-- Must be implemented by child classes
function EventTapeController:_setupRemoteEvent(remoteEvent)
    error("Must implement in child class", 2)
end

function EventTapeController:send(remoteEventName, tape, target)
    error("Must implement in child class", 2)
end

-- Shared buffer logic
function EventTapeController:_defaultEventHandler(eventType, tape)
    self._buffers[eventType] = self._buffers[eventType] or {}
    table.insert(self._buffers[eventType], tape)
end

function EventTapeController:_processCombatBuffer()
    if self._buffers[RemoteEventsEnum.GlobalCombatRemoteEvent] then
        for _, tape in ipairs(self._buffers[RemoteEventsEnum.GlobalCombatRemoteEvent]) do
            self._eventSystem:processIncomingTape(tape)
        end
        self._buffers[RemoteEventsEnum.GlobalCombatRemoteEvent] = {}
    end
end

return EventTapeController