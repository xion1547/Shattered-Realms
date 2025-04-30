-- StarterPlayerScripts/UI/AnimationUI.lua

local AnimationLibrary = require(game:WaitForChild("ReplicatedStorage"):WaitForChild("modules"):WaitForChild("AnimationLibrary"))
local PlayerAnimationController = require(script.Parent:WaitForChild("PlayerAnimationController"))

local AnimationUI = {}
AnimationUI.__index = AnimationUI

function AnimationUI.new(player, rootGUI)
	local self = setmetatable({}, AnimationUI)

	self.rootGUI = rootGUI
	self.Player = player
	self.Humanoid = self:getHumanoid()
	self.Controller = PlayerAnimationController.new(self.Humanoid)
	self.Controller:LoadOwnedAnimations()

	self.ScreenGui = self:buildGui()
	self.Frame = self.ScreenGui:WaitForChild("AnimationFrame")

	self:createButtons()

	return self
end

function AnimationUI:getHumanoid()
	local char = self.Player.Character or self.Player.CharacterAdded:Wait()
	return char:WaitForChild("Humanoid")
end

function AnimationUI:buildGui()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "AnimationGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.Parent = self.rootGUI

	local frame = Instance.new("ScrollingFrame")
	frame.Name = "AnimationFrame"
	frame.Size = UDim2.new(0, 240, 0, 300)
	frame.Position = UDim2.new(0, 50, 0, 100)
	frame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	frame.CanvasSize = UDim2.new(0, 0, 0, 0)
	frame.ScrollBarThickness = 6
	frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	frame.BorderSizePixel = 0
	frame.Parent = screenGui

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame

	return screenGui
end

function AnimationUI:createButton(name)
	local button = Instance.new("TextButton")
	button.Name = name .. "Button"
	button.Size = UDim2.new(1, 0, 0, 40)
	button.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.Font = Enum.Font.Gotham
	button.TextSize = 18
	button.Text = name
	button.BorderSizePixel = 0
	return button
end

function AnimationUI:createButtons()
	for _, animData in ipairs(AnimationLibrary:GetOwnedAnimations()) do
		local button = self:createButton(animData.Name)
		button.Parent = self.Frame

		button.MouseButton1Click:Connect(function()
			self.Controller:PlayAnimation(animData.Name)
		end)
	end
end

function AnimationUI:Destroy()
	if self.ScreenGui then
		self.ScreenGui:Destroy()
	end
end

return AnimationUI
