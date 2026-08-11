-- src/shared/definitions/EnemyTemplates.luau
--
-- Content Layer. See Architecture-Reference.md Part 6.
-- One entry per enemy TYPE, read once at construction to seed an Entity.
-- Adding an enemy is one entry here and no code anywhere.

return {
    GOBLIN = {
        id = "GOBLIN",
        displayName = "Goblin",
        hp = 60,
        stats = { attack = 8, defense = 3, speed = 6 },
        aiProfile = "MELEE_CHASER",
        lootTableId = "GOBLIN_COMMON",
        lootSlots = 4,
    },

    ARCHER = {
        id = "ARCHER",
        displayName = "Skeleton Archer",
        hp = 40,
        stats = { attack = 12, defense = 2, speed = 5 },
        aiProfile = "RANGED_KITER",
        lootTableId = "SKELETON_COMMON",
        lootSlots = 4,
    },
}
