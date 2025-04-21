-- src/client/gui/player/subGui/HealthBarManager.lua
local HealthBarController = require(script.Parent.HealthBarController)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BaseManager = require(ReplicatedStorage:WaitForChild("utils"):WaitForChild("BaseManager"))
local TweenUtil = require(script.Parent.Parent.Parent.Parent.utils.TweenUtil)
local HealthBar = require(ReplicatedStorage:WaitForChild("uiTemplates"):WaitForChild("playerGui"):WaitForChild("HealthBar"))

local HealthBarManager = {}
HealthBarManager.__index = HealthBarManager

function HealthBarManager.newManager()
    return BaseManager.newManager(HealthBarManager, HealthBarController)
end

function HealthBarManager:init(parent)
    -- Create the HealthBar instance and pass it to the controller
    local healthBarInstance = HealthBar:create(parent)
	print("HealthBarManager: HealthBar instance created", healthBarInstance)
	self.Bar = healthBarInstance
end

function HealthBarManager:updateHealth(healthPercent)
    if self.Bar then
		local fill = self.Bar:FindFirstChild("Fill")
		if fill then
			TweenUtil:TweenHealthBar(fill, healthPercent)
		end
	end
end

function HealthBarManager:cleanup()
    if self.controller then
        self.controller:cleanup()
    end
end

return HealthBarManager
