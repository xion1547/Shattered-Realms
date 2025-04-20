-- Main.client.luau
-- Load ClientManager
local ClientManager = require(script.Parent.globalManagers:WaitForChild("ClientManager"))

-- Kick off bootstrapping
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

if ClientManager.onConnect then
	print("Main running")
	task.spawn(ClientManager.onConnect, ClientManager, LocalPlayer)
end
