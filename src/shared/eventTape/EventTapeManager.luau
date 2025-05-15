local EventTape = require(script.Parent:WaitForChild("event"):WaitForChild("EventTape"))
local EventDeserializer = require(script.Parent:WaitForChild("event"):WaitForChild("EventDeserializer"))

local EventManager = {}
EventManager.__index = EventManager

function EventManager.new()
    local self = setmetatable({
        _tape = EventTape.new(),
        _controller = nil,
        _system = nil
    }, EventManager)
    
    self:createNewTape()
    return self
end

function EventManager:init(controllerClass, systemClass, handlerFolder)
    self._controller = controllerClass.new(self)
    local eventDeserializer = EventDeserializer.new(script.Parent:WaitForChild("event"))
    eventDeserializer.preloadModules()
    self._system = systemClass.new(self, handlerFolder, eventDeserializer)
    return self
end

function EventManager:renewTape()
    table.clear(self._tape)
end

function EventManager:getController()
    return self._controller
end

function EventManager:getSystem()
    return self._system
end

return EventManager