-- src/client/gui/player/subGui/healthbar/HealthBarController.lua
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

return HealthBarController
