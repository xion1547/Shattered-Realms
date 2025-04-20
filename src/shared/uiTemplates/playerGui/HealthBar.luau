--[[
	HealthBar Module
	This module creates a health bar UI element in the player's GUI.
]]
local HealthBar = {}

function HealthBar:create(parent)
	local frame = Instance.new("ImageLabel")
    frame.Name = "HealthBar"
    frame.Size = UDim2.new(0, 300, 0, 50)
    frame.Position = UDim2.new(0, 20, 0, 20)
    frame.Image = "rbxassetid://YOUR_BACKGROUND_IMAGE"
    frame.BackgroundTransparency = 1

    local fill = Instance.new("Frame")
    fill.Name = "Fill"
    fill.Size = UDim2.new(1, 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
    fill.Parent = frame

    return frame
end

return HealthBar