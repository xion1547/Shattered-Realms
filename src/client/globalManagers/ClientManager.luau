-- ClientManager.luau

local UIManager = require(script.Parent.UIManager)
local ClientManager = {}

function ClientManager:onConnect(player)
	print("Player connected:", player.Name)
	local uiManagerInstance = UIManager.new()
	print("uiManagerInstance created, uiManagerInstance:", uiManagerInstance)
	uiManagerInstance:init()
end

return ClientManager
