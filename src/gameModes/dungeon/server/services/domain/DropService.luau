-- DOMAIN SERVICE. Loot rolls, world drops, pickup range validation.
-- Dungeon place only. See Architecture-Reference.md Part 10.
--
-- Combat -> Drop is a legal SIDEWAYS edge: one-directional and justified
-- (a kill inherently produces loot). Drop -> Combat would close the cycle
-- and is forbidden.

local DropService = {}

function DropService:boot()
    -- TODO: subscribe to Combat.OnKill by NAME once that fact is declared.
    -- SignalService.on("Combat.OnKill", function(attacker, victim) ... end)
end

function DropService:rollLoot(lootTableId, luckModifier) end

function DropService:createDrop(position, item) end

function DropService:isInRange(entity, drop) return false end

function DropService:claim(entity, dropId) end

return DropService
