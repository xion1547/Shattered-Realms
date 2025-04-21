-- src/client/global-managers/ComponentLoader.lua
local ComponentLoader = {}
ComponentLoader.__index = ComponentLoader

-- Loads components directly under the given folder and returns a table of managers.
function ComponentLoader.loadComponents(folder, parentGUI)
	local loadedManagers = {}

	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Folder") then
			for _, module in ipairs(child:GetChildren()) do
				if module:IsA("ModuleScript") then
					print(`[Module] Found {module:GetFullName()}`)
					local success, component = pcall(require, module)
					if success and type(component) == "table" and type(component.newManager) == "function" then
						local manager = component.newManager()
						manager:init(parentGUI)
						loadedManagers[module.Name] = manager
						print(`[ComponentLoader] Loaded {module.Name}`)
					else
						warn(`[ComponentLoader] Skipped {module.Name}: No valid newManager() method.`)
					end
				end
			end
		end
	end

	return loadedManagers
end

return ComponentLoader
