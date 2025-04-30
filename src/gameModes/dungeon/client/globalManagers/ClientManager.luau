-- ClientManager.luau

local UIManager = require(script.Parent.UIManager)
local ClientManager = {}
local Players = game:GetService("Players")

function ClientManager:onConnect(player)
	print("Player connected:", player.Name)
	local uiManagerInstance = UIManager.new()
	-- Initialize the UIManager with the player instance
	uiManagerInstance:init(Players)
end

return ClientManager
