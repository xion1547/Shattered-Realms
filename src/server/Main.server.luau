-- Main.server.luau

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteEventsManager = require(ReplicatedStorage:WaitForChild("remoteEvents"):WaitForChild("RemoteEventsManager"))
local LocalPlayer = Players.LocalPlayer
local Client = script.Parent

-- Utility to dynamically load modules from a folder
local function loadModules(folder)
	local loaded = {}
	for _, moduleScript in ipairs(folder:GetChildren()) do
		if moduleScript:IsA("ModuleScript") then
			local success, result = pcall(require, moduleScript)
			if success then
				loaded[moduleScript.Name] = result
			else
				warn(`[Client] Failed to load {moduleScript.Name}: {result}`)
			end
		end
	end
	return loaded
end

-- 🔄 onConnect: Load only the modules you want on player join
local function onConnect()
	-- Initialize RemoteEventsManager
	local remoteEventsManager = RemoteEventsManager.new()
	remoteEventsManager:init()
	print("[Client] RemoteEventsManager initialized.")
end

-- Kick off your custom loading logic
onConnect()
