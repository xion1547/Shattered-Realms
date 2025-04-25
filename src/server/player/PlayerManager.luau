-- src/server/player/PlayerManager.lua

local SignalHelper = require(game.ReplicatedStorage:WaitForChild("utils"):WaitForChild("signal"):WaitForChild("SignalHelper"))
local PlayerRegistry = require(game.ServerScriptService:WaitForChild("Server"):WaitForChild("utils"):WaitForChild("signalRegistries"):WaitForChild("PlayerRegistry"))

local PlayerManager = {}
PlayerManager.__index = PlayerManager

function PlayerManager.new()
    local self = setmetatable({}, PlayerManager)
    self.players = {}
    return self
end

function PlayerManager:Initialize()
    -- Register signals globally via SignalService
    SignalHelper.AutoConnect(PlayerRegistry, self)  -- Now we automatically connect signals to methods in self (PlayerManager)
end

function PlayerManager:Bind(playerObj)
    self.players[playerObj.UserId] = playerObj -- same ref
end

return PlayerManager