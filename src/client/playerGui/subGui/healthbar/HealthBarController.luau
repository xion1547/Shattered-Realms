-- src/client/gui/player/subGui/HealthBarController.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteEventsManager = require(ReplicatedStorage:WaitForChild("remoteEvents"):WaitForChild("RemoteEventsManager"))
local RemoteEventsEnum = require(ReplicatedStorage:WaitForChild("remoteEvents"):WaitForChild("RemoteEventsEnum"))

local HealthBarController = {}
HealthBarController.__index = HealthBarController

function HealthBarController.new(healthBarManager)
    local self = setmetatable({}, HealthBarController)
    self.healthBarManager = healthBarManager  -- Store reference to HealthBarManager
    return self
end

function HealthBarController:initialize()
    -- Listen to the remote event for health updates
    local healthUpdateEvent = RemoteEventsManager.getEventStatic(RemoteEventsEnum.Player.HealthUpdate)
    healthUpdateEvent.OnClientEvent:Connect(function(healthPercent)
        self.healthBarManager:updateHealth(healthPercent)  -- Call updateHealth on the manager
    end)
end

return HealthBarController
