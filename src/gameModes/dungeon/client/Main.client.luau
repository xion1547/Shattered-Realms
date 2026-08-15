-- Main.client.luau

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientManager = require(script.Parent.globalManagers:WaitForChild("ClientManager"))
local EventTapeClient = require(script.Parent:WaitForChild("eventTape"):WaitForChild("EventTapeClient"))
local InputSystem = require(script.Parent:WaitForChild("systems"):WaitForChild("InputSystem"))
local RemoteEventsManager = require(ReplicatedStorage:WaitForChild("remoteEvents"):WaitForChild("RemoteEventsManager"))
local EventRegistry = require(ReplicatedStorage:WaitForChild("eventTape"):WaitForChild("event"):WaitForChild("EventRegistry"))

local LocalPlayer = Players.LocalPlayer

local function onConnect()
	-- The client authors events too, so it runs the same declaration check the
	-- server does. Event classes live in shared/, so a drifted schema is a
	-- fault on both sides -- and the client is where it would otherwise
	-- surface as a silent build failure rather than a rejected packet.
	EventRegistry.validate()

	-- EventTape first: constructing it blocks on WaitForChild until the
	-- server has created the remote. Doing this before RemoteEventsManager
	-- avoids its createEvent warning about a client trying to create a
	-- RemoteEvent that has not replicated yet.
	local eventTape = EventTapeClient.new()
	eventTape:start()

	local remoteEventsManager = RemoteEventsManager.new()
	remoteEventsManager:init()

	-- Input goes on the wire through EventTape like everything else -- there
	-- is no second path to the server, which is what makes "the client sends
	-- intent" a structural fact rather than a convention.
	local input = InputSystem.new(eventTape)
	input:start()

	-- The legacy Manager/Controller/System tree. Being dissolved with the
	-- client rewrite; left running so the existing HUD still appears.
	task.spawn(ClientManager.onConnect, ClientManager, LocalPlayer)
end

onConnect()
