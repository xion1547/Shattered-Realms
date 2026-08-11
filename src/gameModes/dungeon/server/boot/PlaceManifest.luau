-- src/gameModes/dungeon/server/boot/PlaceManifest.luau
--
-- What this place declares it needs. See Architecture-Reference.md Part 13.
--
-- Each place declares its own REQUIRED subset -- never "load everything and
-- skip what's missing." The difference matters:
--
--   declared but missing from the build  -> a .project.json bug, fails boot
--   present but never declared           -> a leaked inclusion, also fails
--
-- That two-way check turns "absence is stronger than disconnection" from an
-- assumption you trust into a guarantee verified every time the server boots.
--
-- The layer keys are also the BOOT ORDER, and that is deliberate: authority
-- services are leaves and must be up before anything that calls down into
-- them. Domain services boot after, so they can subscribe to authority Facts
-- that already exist.
--
-- Absent here on purpose: ShopService (Hub only) and AFKService (Farm Zone
-- only). They are not disabled in this place -- they are not in the build.

return {
    order = { "authority", "infra", "domain", "drivers" },

    authority = {
        "ResourceService",
        "StateService",
        "StatService",
        "BuffService",
        "EquipmentService",
        -- Every place, including the Hub -- not because anything it holds
        -- persists (nothing here survives a teleport) but because every
        -- place has entities standing somewhere.
        "SpatialService",
    },

    infra = {
        "SessionService",
        "DataService",
    },

    -- SkillService is deliberately ABSENT: it lives inside CombatService as a
    -- child module, so Combat is the one public-facing authority for that
    -- whole domain. A sub-domain is not a manifest entry.
    domain = {
        "CombatService",
        "InventoryService",
        "DungeonService",
        "DropService",
        "LevelService",
        "AchievementService",
        "ZoneService",
    },

    drivers = {
        "AIService",
    },
}
