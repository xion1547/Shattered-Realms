-- src/server/signals/PlayerRegistry.lua
local Signal = require(game:GetService("ReplicatedStorage").utils.signal.Signal)

local PlayerRegistry = {
    Health = {
        OnDamageTaken = Signal.new(),
        OnHealthChanged = Signal.new(),
    },
    Gold = {
        OnGoldGained = Signal.new(),
        OnGoldSpent = Signal.new(),
    },
    EXP = {
        OnEXPChanged = Signal.new(),
        OnLevelUp = Signal.new(),
    },
    Inventory = {
        OnItemAdded = Signal.new(),
        OnItemRemoved = Signal.new(),
    }
}

return PlayerRegistry
