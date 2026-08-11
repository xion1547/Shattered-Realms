-- src/gameModes/dungeon/client/globalManagers/UIManager.luau
--
-- Creates the root ScreenGui and starts whatever draws into it.
--
-- The PlayerManager -> ComponentLoader -> HealthBar{Manager,Controller,System}
-- chain was removed: it produced a static health bar with no data source
-- (nothing ever called updateHealth), and it was the per-property
-- Manager/Controller/System ecosystem the client rewrite replaces with
-- declarative HUD bindings. See docs/Client-Architecture-Handoff.md.

local UIRootGUI = require(script.Parent.UIRootGUI)
local AnimationUI = require(script.Parent.Parent:WaitForChild("utils"):WaitForChild("modules"):WaitForChild("AnimationUI"))

local UIManager = {}
UIManager.__index = UIManager

function UIManager.new()
	return setmetatable({
		Players = nil,
		root = nil,
		AnimationUI = nil,
	}, UIManager)
end

function UIManager:init(Players)
	self.Players = Players

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.root = UIRootGUI.getRoot(playerGui)

	self.AnimationUI = AnimationUI.new(Players.LocalPlayer, self.root)
end

return UIManager
