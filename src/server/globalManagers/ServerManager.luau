-- src/server/globalManagers/ServerManager.lua

local PlayerObject = require(game.ServerScriptService:WaitForChild("Server"):WaitForChild("entities"):WaitForChild("PlayerEntity"))
local PlayerManager = require(game.ServerScriptService:WaitForChild("Server"):WaitForChild("system"):WaitForChild("player"):WaitForChild("PlayerManager"))
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GlobalRegistry = require(ReplicatedStorage:WaitForChild("utils"):WaitForChild("signal"):WaitForChild("GlobalRegistry"))
local RemoteEventsManager = require(ReplicatedStorage:WaitForChild("remoteEvents"):WaitForChild("RemoteEventsManager"))
local SignalService = require(ReplicatedStorage:WaitForChild("utils"):WaitForChild("signal"):WaitForChild("SignalService"))
local SignalEnum = require(ReplicatedStorage:WaitForChild("utils"):WaitForChild("signal"):WaitForChild("SignalEnum"))
local SignalHelper = require(ReplicatedStorage:WaitForChild("utils"):WaitForChild("signal"):WaitForChild("SignalHelper"))

local ServerManager = {}
ServerManager.__index = ServerManager

function ServerManager.new()
    local self = setmetatable({}, ServerManager)

    self.players = {}
    self.enemies = {}
    self.timers = {}
    self.managers = {}

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
	local signalEnumInstance = SignalEnum.new(GlobalRegistry)
	signalEnumInstance:initialize()
    SignalHelper.AutoConnectAll(GlobalRegistry)

    local playerManager = PlayerManager.new() -- Create a new instance of PlayerManager
	self.managers["PlayerManager"] = playerManager -- Store the player manager in the UIManager
	playerManager:init() -- Initialize the player manager with the root GUI

    self:_bindPlayerEvents() -- Bind player events

    print("ServerManager initialized") 
end

-- Private method to bind Roblox player events
function ServerManager:_bindPlayerEvents()
    game.Players.PlayerAdded:Connect(function(player)
        self:AddPlayer(player)
    end)

    game.Players.PlayerRemoving:Connect(function(player)
        self:RemovePlayer(player)
    end)

    -- 🛠️ Add players who are already in the game
    for _, player in ipairs(game.Players:GetPlayers()) do
        self:AddPlayer(player)
    end
end


-- Add a player to the manager
function ServerManager:AddPlayer(player)
    local playerObj = PlayerObject.new(player)
    self.players[playerObj.playerId] = playerObj

    -- 🛡️ Safety check
    local playerManager = self.managers["PlayerManager"]
    if not playerManager then
        warn("[ServerManager] PlayerManager not initialized yet! Retrying...")
        task.defer(function()
            -- Defer the bind to next frame
            local pm = self.managers["PlayerManager"]
            if pm then
                pm:Bind(playerObj)
            else
                warn("[ServerManager] Failed to bind Player after defer! Still no PlayerManager.")
            end
        end)
    else
        playerManager:Bind(playerObj)
    end
end


-- Remove a player and clean up
function ServerManager:RemovePlayer(player)
    local playerObj = self.players[player.UserId]
    if playerObj then
        playerObj:Destroy()
        self.players[player.playerId] = nil
    end
end

-- Example method: get all players
function ServerManager:GetAllPlayers()
    return self.players
end

return ServerManager
