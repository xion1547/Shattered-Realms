local EventDeserializer = {}
EventDeserializer.__index = EventDeserializer

function EventDeserializer.new(moduleRootPath)
    assert(typeof(moduleRootPath) == "Instance", "moduleRootPath must be an Instance (e.g., ReplicatedStorage.EventTape)")
    local self = setmetatable({}, EventDeserializer)
    self._moduleCache = {}
    self._moduleRoot = moduleRootPath
    return self
end

-- Preloads all modules into cache (call once at startup)
function EventDeserializer:preloadModules()
    for _, module in ipairs(self._moduleRoot:GetDescendants()) do
        if module:IsA("ModuleScript") and module.Name:match("Event$") then
            self:_requireModule(module)
        end
    end
end

-- Internal: Safely require + cache a module
function EventDeserializer:_requireModule(module)
    if self._moduleCache[module] then return self._moduleCache[module] end

    local success, result = pcall(require, module)
    if not success then
        warn(`[EventDeserializer] Failed to load module {module.Name}: {result}`)
        return nil
    end

    assert(type(result) == "table", `Module {module.Name} must return a table`)
    assert(type(result.deserialize) == "function", `Module {module.Name} must have a deserialize function`)

        self._moduleCache[module] = result
    return result
end

-- Main deserialization method
function EventDeserializer:deserialize(event)
    local eventType = event:getEventType()
    assert(type(eventType) == "string" and eventType ~= "", "Event type must be a non-empty string")

    -- Find the module (cached or load dynamically)
    local moduleName = eventType .. "Event"
    local module = self._moduleRoot:FindFirstChild(moduleName, true)
    assert(module, `Event module not found: {moduleName}`)

    local eventModule = self:_requireModule(module)
    assert(eventModule, `Failed to load module: {moduleName}`)

    return eventModule.deserialize(event)
end

return EventDeserializer