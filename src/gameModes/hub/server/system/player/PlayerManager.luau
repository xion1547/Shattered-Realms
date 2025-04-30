-- src/server/system/player/PlayerManager.lua

local PlayerManager = {}
PlayerManager.__index = PlayerManager

function PlayerManager.new()
    local self = setmetatable({}, PlayerManager)
    self.players = {}
    return self
end

function PlayerManager:init()
    -- Initialization logic if needed
    print("PlayerManager initialized");
end

function PlayerManager:Bind(playerObj)
    self.players[playerObj.playerId] = playerObj -- same ref
end

function PlayerManager:TestingSignal()
    -- test a signal
end

return PlayerManager