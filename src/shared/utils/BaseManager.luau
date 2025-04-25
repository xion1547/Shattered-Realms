-- src/client/utils/BaseManager.lua
local BaseManager = {}
BaseManager.__index = BaseManager

-- Helper function to check if a variable is a class
local function isClass(obj)
    return typeof(obj) == "table" and obj.new and typeof(obj.new) == "function"
end

function BaseManager.newManager(concreteClass, Controller, System)
    -- Argument validation
    if not isClass(Controller) then
        warn("BaseManager.newManager: Controller should be a valid class (table with 'new' method).")
    end

    if not isClass(System) then
        warn("BaseManager.newManager: System should be a valid class (table with 'new' method).")
    end

    local self = setmetatable({}, concreteClass)

    -- Initialize the controller and system only if they are valid
    if isClass(Controller) then
        self.controller = Controller.new()
        if self.controller.initialize then
            self.controller:initialize()
        end
    end

    if isClass(System) then
        self.system = System.new()
    end

    return self
end

return BaseManager
