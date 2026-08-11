-- src/shared/definitions/ResourceDefinitions.luau
--
-- Content Layer. See Architecture-Reference.md Parts 6 and 8.
--
-- Every numeric quantity in the game is one entry here. Adding a currency is
-- one row, not a new Service -- that is the whole reason EconomyService and
-- the per-currency Services were wrong.
--
-- Rules: read-only after boot, validated at startup, never contains
-- functions. A behaviour tag is a STRING the engine recognises
-- (`onFloor = "TRIGGER_DEATH"`), never an inline callback -- a config entry
-- holding a function has become code in disguise (Part 2).

return {
    HP = {
        id = "HP",
        category = "VITAL",
        floor = 0,
        ceiling = "MaxHP",          -- references another resource id
        persistent = false,          -- server memory only; never crosses a teleport
        onFloor = "TRIGGER_DEATH",
        startsAt = 100,
    },

    MaxHP = {
        id = "MaxHP",
        category = "VITAL",
        floor = 1,
        persistent = false,
        startsAt = 100,
    },

    -- The Attack-Based Shield's hit counter is a Resource, not its own
    -- component: a stored number with a floor, a ceiling and a behaviour at
    -- floor is every property a Resource has (Part 8).
    ShieldHits = {
        id = "ShieldHits",
        category = "VITAL",
        floor = 0,
        persistent = false,
        onFloor = "TRIGGER_SHIELD_BREAK",
        startsAt = 0,
    },

    Gold = {
        id = "Gold",
        category = "CURRENCY",
        floor = 0,
        persistent = true,
        startsAt = 0,
    },

    EXP = {
        id = "EXP",
        category = "PROGRESSION",
        floor = 0,
        ceiling = "EXPCeiling",
        persistent = true,
        onCeiling = "LEVEL_UP",
        startsAt = 0,
    },

    EXPCeiling = {
        id = "EXPCeiling",
        category = "PROGRESSION",
        floor = 1,
        persistent = true,
        startsAt = 100,
    },

    Level = {
        id = "Level",
        category = "PROGRESSION",
        floor = 1,
        persistent = true,
        startsAt = 1,
    },
}
