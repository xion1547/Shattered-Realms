local RemoteEventsManager = require(game.ReplicatedStorage:WaitForChild("remoteEvents"):WaitForChild("RemoteEventsManager"))
local RemoteEventsEnum = require(game.ReplicatedStorage:WaitForChild("remoteEvents"):WaitForChild("RemoteEventsEnum"))

local HealthBarController = {}
HealthBarController.__index = HealthBarController

function HealthBarController.new(healthBarManager)
    local self = setmetatable({}, HealthBarController)
    self.manager = healthBarManager -- Store reference to HealthBarManager
    return self
end

function HealthBarController:initialize()
    -- Listen to the remote event for health update requests
end

return HealthBarController