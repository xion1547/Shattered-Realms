-- Main.client.luau

local Players = game:GetService("Players")
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
	print("🔗 Player connected. Initializing selected client modules...")

	local managers = Client:FindFirstChild("Managers")
	local systems = Client:FindFirstChild("Systems")

	if managers then
		local loadedManagers = loadModules(managers)

		-- Example: Initialize specific managers
		if loadedManagers.UIManager and type(loadedManagers.UIManager.Init) == "function" then
			loadedManagers.UIManager.Init()
		end

		if loadedManagers.InputManager and type(loadedManagers.InputManager.Init) == "function" then
			loadedManagers.InputManager.Init()
		end
	end

	if systems then
		local loadedSystems = loadModules(systems)

		-- Example: Load only some systems
		if loadedSystems.AnimationSystem and type(loadedSystems.AnimationSystem.Init) == "function" then
			loadedSystems.AnimationSystem.Init()
		end
	end

	print("✅ Client initialization complete.")
end

-- Kick off your custom loading logic
onConnect()
