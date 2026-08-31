-- Main.client.luau

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientManager = require(script.Parent.globalManagers:WaitForChild("ClientManager"))
local EventTapeClient = require(script.Parent:WaitForChild("eventTape"):WaitForChild("EventTapeClient"))
local InputSystem = require(script.Parent:WaitForChild("systems"):WaitForChild("InputSystem"))
local Rig = require(script.Parent:WaitForChild("playback"):WaitForChild("Rig"))
local RemoteEventsManager = require(ReplicatedStorage:WaitForChild("remoteEvents"):WaitForChild("RemoteEventsManager"))
local EventRegistry = require(ReplicatedStorage:WaitForChild("eventTape"):WaitForChild("event"):WaitForChild("EventRegistry"))
local AnimationManifest = require(ReplicatedStorage:WaitForChild("definitions"):WaitForChild("AnimationManifest"))

local LocalPlayer = Players.LocalPlayer

local function onConnect()
	-- The client authors events too, so it runs the same declaration check the
	-- server does. Event classes live in shared/, so a drifted schema is a
	-- fault on both sides -- and the client is where it would otherwise
	-- surface as a silent build failure rather than a rejected packet.
	EventRegistry.validate()

	-- SHAPE ONLY, and it throws. A malformed manifest row is a typo in the
	-- repo, so it is the same kind of fault as a drifted event schema and gets
	-- the same treatment -- aggregated, named, and fatal, rather than surfacing
	-- later as an animation that quietly never plays.
	--
	-- Whether an id actually RESOLVES is a different question with a different
	-- answer (Rig:_verify, via AnimationTrack.Length), because that one needs
	-- the CDN and must not be able to stop the client booting.
	local manifestOk, manifestProblems = AnimationManifest.validate()
	if not manifestOk then
		error("[AnimationManifest] invalid:\n    " .. table.concat(manifestProblems, "\n    "))
	end

	-- EventTape first: constructing it blocks on WaitForChild until the
	-- server has created the remote. Doing this before RemoteEventsManager
	-- avoids its createEvent warning about a client trying to create a
	-- RemoteEvent that has not replicated yet.
	local eventTape = EventTapeClient.new()
	eventTape:start()

	local remoteEventsManager = RemoteEventsManager.new()
	remoteEventsManager:init()

	-- THE PLAYER'S OWN BODY IS ANIMATED BY THIS CLIENT, not by the server. That
	-- is Roblox's network-ownership rule, not a choice -- a player's animation
	-- started server-side would cost a full round trip to do something this
	-- machine can do this frame, and an NPC's started client-side would not
	-- replicate at all (Animation.md Part 3).
	local rig = Rig.new()
	rig:start()

	-- Input goes on the wire through EventTape like everything else -- there
	-- is no second path to the server, which is what makes "the client sends
	-- intent" a structural fact rather than a convention.
	--
	-- The rig is handed in so a click can play its swing IMMEDIATELY, without
	-- waiting for the server. That is the optimistic half of Architecture Part
	-- 15, and it is the entire feel of the weapon: the round trip is real and
	-- the animation must not be inside it.
	local input = InputSystem.new(eventTape, rig)
	input:start()

	-- DEVELOPMENT ONLY, and off unless the flag is on. Watches
	-- `DebugConductorTool` on Workspace -- flip it in the Properties panel with
	-- the game running (from the SERVER context; the command bar runs as the
	-- client during a play test and attributes do not replicate upward).
	--
	-- Bound rather than started: this costs one attribute read at boot when off,
	-- and the whole panel is built and torn down by the flag.
	local ConductorTool = require(script.Parent:WaitForChild("diagnostics")
		:WaitForChild("conductorTool"))
	ConductorTool.bindToFlag()

	-- The legacy Manager/Controller/System tree. Being dissolved with the
	-- client rewrite; left running so the existing HUD still appears.
	task.spawn(ClientManager.onConnect, ClientManager, LocalPlayer)
end

onConnect()
