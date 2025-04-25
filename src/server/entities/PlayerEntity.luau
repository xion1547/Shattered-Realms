-- src/server/models/PlayerEntity.lua
local PlayerEntity = {}
PlayerEntity.__index = PlayerEntity

-- Constructor for PlayerEntity object
function PlayerEntity.new(playerId)
    local self = setmetatable({}, PlayerEntity)

    -- Basic player state
    self.playerId = playerId
    self.health = 100
    self.maxHealth = 100
    self.gold = 0
    self.level = 1
    self.buffs = {}  -- Active buffs/debuffs for the player
    self.abilities = {}  -- Abilities the player has

    -- Tracking other relevant data (example)
    self.enemiesDefeated = 0
    self.questsCompleted = {}

    return self
end

-- Example Method: Take Damage
function PlayerEntity:takeDamage(amount)
    self.health = math.max(self.health - amount, 0)
    if self.health == 0 then
        -- Handle player death
        self:onDeath()
    end
end

-- Example Method: Heal the player
function PlayerEntity:heal(amount)
    self.health = math.min(self.health + amount, self.maxHealth)
end

-- Example Method: Gain Gold
function PlayerEntity:gainGold(amount)
    self.gold = self.gold + amount
end

-- Example Method: Add an Ability
function PlayerEntity:addAbility(ability)
    table.insert(self.abilities, ability)
end

-- Example Method: Apply a Buff
function PlayerEntity:applyBuff(buff)
    table.insert(self.buffs, buff)
    -- Add any logic related to the buff here (e.g., start a timer for temporary buffs)
end

-- Example Method: Remove Buff
function PlayerEntity:removeBuff(buff)
    for i, activeBuff in ipairs(self.buffs) do
        if activeBuff == buff then
            table.remove(self.buffs, i)
            break
        end
    end
end

-- Example Method: Handle PlayerEntity Death (can be expanded)
function PlayerEntity:onDeath()
    -- Logic for what happens when the player dies (respawn, drop items, etc.)
    print(self.playerId .. " has died.")
end

-- Example Method: Update PlayerEntity Level
function PlayerEntity:levelUp()
    self.level = self.level + 1
    self.maxHealth = self.maxHealth + 20  -- Example: increase health per level
    self.health = self.maxHealth  -- Restore health on level up
end

return PlayerEntity
