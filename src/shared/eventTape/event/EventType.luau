local EventType = {
    COMBAT = {
        type = "COMBAT",
        subType = {
            MELEE = "MELEE",
            RANGED = "RANGED",
            AOE = "AOE",
            HEAL = "HEAL",
            BUFF = "BUFF",
            DEBUFF = "DEBUFF"
        }
    },
    INVENTORY = {
        type = "INVENTORY",
        subType = {
            LOOT = "LOOT",
            EQUIP_ECHO = "EQUIP_ECHO",
            UNEQUIP_ECHO = "UNEQUIP_ECHO",
            EQUIP_GEAR = "EQUIP_GEAR",
            UNEQUIP_GEAR = "UNEQUIP_GEAR",
        }
    },
    ANIMATION = {
        type = "ANIMATION",
        subType = {
            ATTACK = "ATTACK",
            ULTIMATE = "ULTIMATE",
            EMOTE = "EMOTE",
            BUFF = "BUFF"
        }
    },
    TELEPORT = {
        type = "TELEPORT",
        subType = {
            JOIN = "JOIN",
            LEAVE = "LEAVE",
        }
    }
}

return setmetatable(EventType, {
    __index = function(_, key)
        error("EventType does not have a key: " .. tostring(key))
    end,
    __newindex = function(_, key, value)
        error("EventType is read-only and cannot be modified: " .. tostring(key))
    end
})