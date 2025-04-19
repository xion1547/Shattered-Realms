-- Manages UI screens and interactions

local UIManager = {}

local StarterGui = game:GetService("StarterGui")
local UIParent = StarterGui:WaitForChild("UI")
local PlayerGUIFolder = UIParent:WaitForChild("player-gui")

-- Create and return a ScreenGui as the root UI for the player
function UIManager:createRootPlayerGUI(player)
    -- Get the Player and PlayerGui
    local playerGui = player:WaitForChild("PlayerGui")
    
    -- Create the ScreenGui
    local rootUI = Instance.new("ScreenGui")
    rootUI.Name = "RootUI"
    rootUI.ResetOnSpawn = false
    rootUI.Parent = playerGui  -- Add it to the player's PlayerGui
    
    return rootUI
end

-- Create and return a ScreenGui as the root UI for the StarterGui ( global UI )
function UIManager:createRootStarterGUI(player)
    -- Create the ScreenGui
    local rootUI = Instance.new("ScreenGui")
    rootUI.Name = "RootUI"
    rootUI.ResetOnSpawn = false
    rootUI.Parent = StarterGui  -- Add it to the player's PlayerGui
    
    return rootUI
end

function UIManager:Init(player)
	-- Create the root ScreenGui
    local rootPlayerGUI = self:createRootPlayerGUI(player)

    -- Dynamically Add any other folder you need here by calling more loadAllComponents

    -- Load all components from the GUI folder
    self:LoadAllComponents(PlayerGUIFolder, rootPlayerGUI)  
    print("PlayerGUIFolder Initialized!")
end

-- Function to dynamically load all available components in the Components folder
function UIManager:LoadAllComponents(componentsFolder, rootScreenGui)
    -- Loop through all scripts in the Components folder
    for _, componentScript in pairs(componentsFolder:GetChildren()) do
        -- Only load module scripts (component files)
        self:LoadComponent(componentScript, rootScreenGui)
    end
end

-- Function to load a single UI component dynamically
function UIManager:LoadComponent(componentScript, rootScreenGui)
	if componentScript:IsA("ModuleScript") then
		local componentModule = require(componentScript)

		-- Initialize the component and parent it to the rootScreenGui
		if componentModule.Create then
			componentModule.Create(rootScreenGui) -- Parent to root ScreenGui
		else
			warn("Component '" .. componentModule.Name .. "' does not have an Initialize function!")
		end
	end
end

return UIManager