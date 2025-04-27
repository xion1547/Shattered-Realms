-- src/signals/GlobalRegistry.lua
local Signal = require(game:GetService("ReplicatedStorage").utils.signal.Signal)

local GlobalRegistry = {
    Player = {
        TestingSignal = Signal.new(),
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
            EchoSummons = {
                OnSelected = Signal.new(),
            },
            OnItemAdded = Signal.new(),
            OnItemRemoved = Signal.new(),
        }
    }
}

return GlobalRegistry
