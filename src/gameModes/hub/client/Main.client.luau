-- Main.client.luau
-- Load ClientManager
local ClientManager = require(script.Parent.globalManagers:WaitForChild("ClientManager"))
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteEventsManager = require(ReplicatedStorage:WaitForChild("remoteEvents"):WaitForChild("RemoteEventsManager"))

-- Kick off bootstrapping
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- 🔄 onConnect: Load only the modules you want on player join
local function onConnect()
	print("Main running")
	-- Initialize RemoteEventsManager
	local remoteEventsManager = RemoteEventsManager.new()
	remoteEventsManager:init()
	print("[Client] RemoteEventsManager initialized.")
	-- Async call to ClientManager
	task.spawn(ClientManager.onConnect, ClientManager, LocalPlayer)
end

-- Kick off your custom loading logic
onConnect()
