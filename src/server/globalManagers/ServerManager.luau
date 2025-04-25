-- src/server/globalManagers/ServerManager.lua

local PlayerObject = require(game.ServerScriptService:WaitForChild("Server"):WaitForChild("entities"):WaitForChild("PlayerEntity"))
local PlayerManager = require(game.ServerScriptService:WaitForChild("Server"):WaitForChild("player"):WaitForChild("PlayerManager"))
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteEventsManager = require(ReplicatedStorage:WaitForChild("remoteEvents"):WaitForChild("RemoteEventsManager"))
local SignalService = require(ReplicatedStorage:WaitForChild("utils"):WaitForChild("signal"):WaitForChild("SignalService"))
local SignalEnum = require(ReplicatedStorage:WaitForChild("utils"):WaitForChild("signal"):WaitForChild("SignalEnum"))
local PlayerRegistry = require(game.ServerScriptService:WaitForChild("Server"):WaitForChild("utils"):WaitForChild("signalRegistries"):WaitForChild("PlayerRegistry"))

local ServerManager = {}
ServerManager.__index = ServerManager

function ServerManager.new()
    local self = setmetatable({}, ServerManager)

    self.players = {}
    self.enemies = {}
    self.timers = {}

    self:_bindPlayerEvents()

    return self
end

function ServerManager:init()
    -- Initialize any necessary components or systems here
    -- Initialize RemoteEventsManager
	local remoteEventsManager = RemoteEventsManager.new()
	remoteEventsManager:init()

	-- Initialize SignalService (Singleton or just once)
	SignalService.getInstance()

	-- Initialize SignalEnum (Singleton or just once)
	local signalEnumInstance = SignalEnum.new(PlayerRegistry)
	signalEnumInstance:initialize()
end

-- Private method to bind Roblox player events
function ServerManager:_bindPlayerEvents()
    game.Players.PlayerAdded:Connect(function(player)
        self:AddPlayer(player)
    end)

    game.Players.PlayerRemoving:Connect(function(player)
        self:RemovePlayer(player)
    end)
end

-- Add a player to the manager
function ServerManager:AddPlayer(player)
    local playerObj = PlayerObject.new(player)
    self.players[player.UserId] = playerObj

    -- Optional: bind player to subsystems
    PlayerManager:Bind(playerObj)
end

-- Remove a player and clean up
function ServerManager:RemovePlayer(player)
    local playerObj = self.players[player.UserId]
    if playerObj then
        playerObj:Destroy()
        self.players[player.UserId] = nil
    end
end

-- Example method: get all players
function ServerManager:GetAllPlayers()
    return self.players
end

return ServerManager
