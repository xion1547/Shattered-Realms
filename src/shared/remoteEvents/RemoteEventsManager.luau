-- src/replicatedStorage/RemoteEventsManager.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteEventsEnum = require(script.Parent.RemoteEventsEnum)
local RunService = game:GetService("RunService")

local RemoteEventsManager = {}
RemoteEventsManager.__index = RemoteEventsManager

-- Singleton instance
local instance = nil

function RemoteEventsManager.new()
	if instance then
		return instance
	end

	instance = setmetatable({}, RemoteEventsManager)
	return instance
end

function RemoteEventsManager:init()
	self.allowedEventNames = {}

	local function traverseEnum(enumTable)
		for _, value in pairs(enumTable) do
			if typeof(value) == "table" then
				traverseEnum(value)
			else
				self:createEvent(value)
				self.allowedEventNames[value] = true
			end
		end
	end

	traverseEnum(RemoteEventsEnum)
end

function RemoteEventsManager:createEvent(eventName)
	if ReplicatedStorage:FindFirstChild(eventName) then return end

	if RunService:IsClient() then
		warn(`[RemoteEventsManager] Client tried to create RemoteEvent: {eventName}`)
		return
	end

	local newEvent = Instance.new("RemoteEvent")
	newEvent.Name = eventName
	newEvent.Parent = ReplicatedStorage
end

function RemoteEventsManager:getEvent(eventName)
	assert(eventName, "[RemoteEventsManager] Event name required")
	assert(self.allowedEventNames[eventName], `[RemoteEventsManager] '{eventName}' is not in RemoteEventsEnum`)

	local event = ReplicatedStorage:FindFirstChild(eventName)
	assert(event and event:IsA("RemoteEvent"), `[RemoteEventsManager] Event not found or invalid: {eventName}`)

	return event
end

function RemoteEventsManager.getEventStatic(eventName)
	return RemoteEventsManager.new():getEvent(eventName)
end

return RemoteEventsManager
