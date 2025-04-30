-- src/client/globalManagers/UIRoot.luau
local Players = game:GetService("Players")

local UIRootGUI = {}

function UIRootGUI.getRoot()
    local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
    local root = playerGui:FindFirstChild("GameUI")

    if not root then
        root = Instance.new("ScreenGui")
        root.Name = "GameUI"
        root.ResetOnSpawn = false
        root.IgnoreGuiInset = true
        root.Parent = playerGui
    end

    return root
end

return UIRootGUI
-- This module provides a function to get or create the root GUI for the game.
-- It checks if a ScreenGui named "GameUI" exists in the PlayerGui and creates one if it doesn't.