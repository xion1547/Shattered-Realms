-- src/client/gui/player/subGui/healthbar/HealthBarSystem.lua

local HealthBarSystem = {}
HealthBarSystem.__index = HealthBarSystem

function HealthBarSystem.new(healthBarManager)
    local self = setmetatable({}, HealthBarSystem)
    self.healthBarManager = healthBarManager  -- Store reference to HealthBarManager
    return self
end

return HealthBarSystem