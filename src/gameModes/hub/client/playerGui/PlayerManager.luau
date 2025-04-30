-- src/client/gui/player/PlayerManager.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ComponentLoader = require(ReplicatedStorage:WaitForChild("utils"):WaitForChild("ComponentLoader"))

local PlayerManager = {}
PlayerManager.__index = PlayerManager

function PlayerManager.new()
	local self = setmetatable({}, PlayerManager)
	self.managers = {}
	return self
end

function PlayerManager:init(parentGUI)
	local subGuiFolder = script.Parent:WaitForChild("subGui")
	if not subGuiFolder then
		warn("[PlayerManager] subGui folder not found.")
		return
	end

	print(`[PlayerManager] about to run loadComponents`)
	-- Automatically load and bind all sub-managers
	self.managers = ComponentLoader.loadComponents(subGuiFolder, parentGUI)
end

function PlayerManager:cleanup()
	for _, manager in pairs(self.managers) do
		if typeof(manager.cleanup) == "function" then
			manager:cleanup()
		end
	end
	self.managers = nil
end

return PlayerManager
