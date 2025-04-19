-- Main.client.luau
local Client = script.Parent
local ManagersFolder = Client:WaitForChild("managers")

-- Load ClientManager
local ClientManager = require(ManagersFolder:WaitForChild("ClientManager"))

-- Kick off bootstrapping
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

if ClientManager.OnConnect then
	task.spawn(ClientManager.OnConnect, ClientManager, LocalPlayer)
end
