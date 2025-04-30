-- src/client/global-managers/UIManager.luau
local UIRootGUI = require(script.Parent.UIRootGUI) -- Import the root GUI manager
local PlayerManager = require(script.Parent.Parent.playerGui.PlayerManager) -- Import the player manager

local UIManager = {}
UIManager.__index = UIManager -- Define the UIManager class

function UIManager.new()
	local self = setmetatable({}, UIManager)
	self.managers = {}
	return self
end

function UIManager:init()
	print("UIManager init running")
	local root = UIRootGUI.getRoot() -- Create or fetch the player root GUI
	local playerManager = PlayerManager.new() -- Create a new instance of PlayerManager
	self.managers["PlayerManager"] = playerManager -- Store the player manager in the UIManager
	playerManager:init(root) -- Initialize the player manager with the root GUI
end

return UIManager
