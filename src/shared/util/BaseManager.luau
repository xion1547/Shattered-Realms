-- src/client/utils/BaseManager.lua
local BaseManager = {}
BaseManager.__index = BaseManager

function BaseManager.newManager(concreteClass, Controller)
    local self = setmetatable({}, concreteClass)
    self.controller = Controller.new()
    if self.controller.initialize then
        self.controller:initialize()
    end
    return self
end

return BaseManager
