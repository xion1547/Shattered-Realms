-- src/serverShared/definitions/enemies/Archer.luau
--
-- See `Goblin.luau` for what a row means and why skills live inline. This file
-- is deliberately the boring second one: it is what proves the folder walk
-- works, because adding it required no edit anywhere else.

local Archer = {}

Archer.id = "ARCHER"
Archer.displayName = "Skeleton Archer"

Archer.hp = 40
Archer.stats = { attack = 12, defense = 2, speed = 5 }

Archer.aiProfile = "RANGED_KITER"
Archer.lootTableId = "SKELETON_COMMON"
Archer.lootSlots = 4

Archer.hurtbox = "DUMMY"

-- PLANNED. A kiter's attack is the first real customer for
-- `motion = PROJECTILE` -- a volume that TRANSLATES over time rather than
-- rotating, tested along the capsule from its last position to its current one
-- so a fast arrow cannot step straight through a body between ticks.
--
-- Empty until that motion kind exists. An archer with a melee swing would be a
-- worse placeholder than an archer with nothing.
Archer.skills = {}

return Archer
