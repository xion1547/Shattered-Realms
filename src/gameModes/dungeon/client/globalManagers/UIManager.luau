-- src/gameModes/dungeon/client/globalManagers/UIManager.luau
--
-- Creates the root ScreenGui and starts whatever draws into it.
--
-- The PlayerManager -> ComponentLoader -> HealthBar{Manager,Controller,System}
-- chain was removed: it produced a static health bar with no data source
-- (nothing ever called updateHealth), and it was the per-property
-- Manager/Controller/System ecosystem the client rewrite replaces with
-- declarative HUD bindings. See docs/Client-Architecture-Handoff.md.
--
-- AnimationUI went the same way. It was a scrollable list of buttons that
-- played animations straight off the Humanoid for eyeballing clips -- useful
-- once, and never wired to anything. Its animation ids lived in
-- shared/modules/AnimationLibrary, which meant a list of placeholder assets
-- was being replicated to every client for a debug panel. Real animation
-- playback belongs to whatever consumes an outbound EventTape diff, not to
-- a GUI that drives the Humanoid directly.
--
-- This creates the root ScreenGui and nothing else draws into it yet.

local UIRootGUI = require(script.Parent.UIRootGUI)

local UIManager = {}
UIManager.__index = UIManager

function UIManager.new()
	return setmetatable({
		Players = nil,
		root = nil,
	}, UIManager)
end

function UIManager:init(Players)
	self.Players = Players

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.root = UIRootGUI.getRoot(playerGui)
end

return UIManager
