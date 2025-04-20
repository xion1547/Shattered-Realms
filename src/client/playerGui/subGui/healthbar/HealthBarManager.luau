-- src/client/gui/player/subGui/HealthBarManager.lua
local HealthBarController = require(script.Parent.HealthBarController)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BaseManager = require(ReplicatedStorage:WaitForChild("util"):WaitForChild("BaseManager"))

local HealthBarManager = {}
HealthBarManager.__index = HealthBarManager

function HealthBarManager.newManager()
    return BaseManager.newManager(HealthBarManager, HealthBarController)
end

function HealthBarManager:init(parent)
    -- Create the HealthBar instance and pass it to the controller
    local HealthBarTemplate = game.ReplicatedStorage:WaitForChild("ui-templates"):WaitForChild("HealthBar")
    local healthBarInstance = HealthBarTemplate:Clone()
    healthBarInstance.Parent = parent
    self.Bar = healthBarInstance
end

function HealthBarManager:updateHealth(healthPercent)
    if self.Bar then
        -- Update the health bar's fill size based on the health percentage
        self.Bar.Fill.Size = UDim2.new(healthPercent, 0, 1, 0)
    end
end

function HealthBarManager:cleanup()
    if self.controller then
        self.controller:cleanup()
    end
end

return HealthBarManager
