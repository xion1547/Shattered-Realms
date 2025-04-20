-- src/replicatedStorage/RemoteEventsManager.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteEventsEnum = require(script.Parent.RemoteEventsEnum)

local RemoteEventsManager = {}
RemoteEventsManager.__index = RemoteEventsManager

-- Table to hold created RemoteEvents
RemoteEventsManager.events = {}

-- Function to create a RemoteEvent if it doesn't exist
function RemoteEventsManager:createEvent(eventName)
    -- Check if the event already exists in ReplicatedStorage
    if not ReplicatedStorage:FindFirstChild(eventName) then
        local newEvent = Instance.new("RemoteEvent")
        newEvent.Name = eventName
        newEvent.Parent = ReplicatedStorage
    end
end

-- Function to get a RemoteEvent (or create it if it doesn't exist)
function RemoteEventsManager:getEvent(eventEnum)
    local eventName = RemoteEventsEnum[eventEnum]
    
    if not eventName then
        warn("[RemoteEventsManager] Event not found in Enum:", eventEnum)
        return nil
    end

    -- If the event is already in the table, return it
    if self.events[eventName] then
        return self.events[eventName]
    end

    -- Otherwise, warn if the event doesn't exist in ReplicatedStorage
    warn("[eventName] Event not found", eventName)
end

return RemoteEventsManager
