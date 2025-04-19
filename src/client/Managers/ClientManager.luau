-- ClientManager.luau

local UIManager = require(script.Parent.UIManager)

local ClientManager = {}

function ClientManager:OnConnect(player)
	print("Player connected:", player.Name)
	UIManager.Init(player)
end

return ClientManager
