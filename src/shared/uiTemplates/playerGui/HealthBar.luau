--[[
	HealthBar Module
	This module creates a health bar UI element in the player's GUI.
]]
local HealthBar = {}

function HealthBar:create(parent)
	-- Container for the health bar
    local container = Instance.new("Frame")
    container.Name = "HealthBar"
    container.Size = UDim2.new(0, 300, 0, 100)
    container.Position = UDim2.new(0, 0, 1, -100)
    container.BackgroundTransparency = 1
    container.Parent = parent

    -- Background (NoHealthBar)
    local bg = Instance.new("ImageLabel")
    bg.Name = "Background"
    bg.Size = UDim2.new(.715, 0, 0.15, 0)
    bg.Position = UDim2.new(0, 43, 0, 43)
    bg.Image = "rbxassetid://132714067698368"
    bg.BackgroundTransparency = 1
    bg.ZIndex = 2 -- Ensure it's rendered above the background
    bg.Parent = container

    -- Foreground (PlayerHealthBar)
    local fg = Instance.new("ImageLabel")
    fg.Name = "Fill"
    fg.Size = UDim2.new(1, 0, 1, 0) -- Will be scaled down as health drops
    fg.Image = "rbxassetid://130962489955750"
    fg.BackgroundTransparency = 1
    fg.ZIndex = 1 -- Ensure it's rendered above the background
    fg.Parent = container

    return container
end

return HealthBar