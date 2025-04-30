-- src/client/global-managers/UIManager.luau
local UIRootGUI = require(script.Parent.UIRootGUI) -- Import the root GUI manager
local PlayerManager = require(script.Parent.Parent.playerGui.PlayerManager) -- Import the player manager
local AnimationUI = require(script.Parent.Parent:WaitForChild("utils"):WaitForChild("modules"):WaitForChild("AnimationUI")) -- Import the AnimationUI module

local UIManager = {}
UIManager.__index = UIManager -- Define the UIManager class

function UIManager.new()
	local self = setmetatable({}, UIManager)
	self.managers = {}
	self.Players = nil
	self.root = nil

	self.AnimationUI = nil
	return self
end

function UIManager:init(Players)
	print("UIManager init running")
	self.Players = Players -- Store the Players service in the UIManager
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	self.root = UIRootGUI.getRoot(playerGui) -- Create or fetch the player root GUI

	local playerManager = PlayerManager.new() -- Create a new instance of PlayerManager
	self.managers["PlayerManager"] = playerManager -- Store the player manager in the UIManager
	playerManager:init(self.root) -- Initialize the player manager with the root GUI

	self.AnimationUI = AnimationUI.new(Players.LocalPlayer, self.root)
end

return UIManager
