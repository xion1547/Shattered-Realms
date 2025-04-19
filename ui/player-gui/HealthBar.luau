-- src/client/UI/Components/HealthBar.luau
local HealthBar = {}

function HealthBar:Create(parent)
	local healthBar = Instance.new("ImageLabel")
	healthBar.Size = UDim2.new(0, 300, 0, 60)
	healthBar.Position = UDim2.new(0, 20, 0, 20)
	healthBar.BackgroundTransparency = 1
	healthBar.Image = "rbxassetid://YOUR_IMAGE_ID_HERE"
	healthBar.Parent = parent
end

return HealthBar