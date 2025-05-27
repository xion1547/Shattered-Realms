local RemoteEventsManager = require(script.Parent.Parent:WaitForChild("remoteEvents"):WaitForChild("RemoteEventsManager"))
local RunService = game:GetService("RunService")

-- Shared/EventTapeController.lua
local EventTapeController = {}
EventTapeController.__index = EventTapeController

function EventTapeController.new(eventSystem)
    local self = setmetatable({}, EventTapeController)
    self._eventSystem = eventSystem
    self._handlers = {} -- { eventType = {handlerFn, config} }
    self._buffers = {} -- { eventType = {tapes} }
    self._dirtyTapes = {} -- Client-only
    return self
end

function EventTapeController:registerAllEvents(handlerFolder)
    for _, module in ipairs(handlerFolder:GetChildren()) do
        if module:IsA("ModuleScript") then
            local success, handler = pcall(require, module)
            if success then
                self:registerEvent(handler.eventType, handler.handler, handler.config)
            end
        end
    end
end

function EventTapeController:registerEvent(eventType, handlerFn, config)
    self._handlers[eventType] = {
        handler = handlerFn,
        config = config or {}
    }
    
    -- Auto-connect RemoteEvent
    local remoteEvent = RemoteEventsManager.getEventStatic(eventType)
    if RunService:IsServer() then
        remoteEvent.OnServerEvent:Connect(function(player, tape)
            self:_handleIncoming(eventType, player, tape)
        end)
    else
        remoteEvent.OnClientEvent:Connect(function(tape)
            self:_handleIncoming(eventType, nil, tape)
        end)
    end
end

function EventTapeController:_handleIncoming(eventType, player, tape)
    local handler = self._handlers[eventType]
    if not handler then return end
    
    if handler.config.bufferEnabled then
        self._buffers[eventType] = self._buffers[eventType] or {}
        table.insert(self._buffers[eventType], {player = player, tape = tape})
    else
        handler.handler(self, tape, player)
    end
end

-- Abstract methods
function EventTapeController:send(eventType, tape, target)
    error("Implement in child class", 2)
end

function EventTapeController:processBuffer(eventType)
    error("Implement in child class", 2)
end

return EventTapeController