-- src/serverShared/definitions/enemies/Goblin.luau
--
-- ONE FILE PER ENEMY. Content Layer -- read once at construction to seed an
-- Entity, never written at runtime.
--
-- ADDING AN ENEMY IS THIS FILE AND NOTHING ELSE. No registry entry, no index
-- to update, no code edit anywhere. `DefinitionLoader` walks this folder at
-- boot, so a file that exists is an enemy that exists.
--
-- An index file listing every enemy would be the same problem in more files --
-- a second place to forget -- which is precisely what the folder walk removes.
--
-- ============================================================================
-- SKILLS LIVE INLINE, UNTIL A SECOND ENEMY WANTS THE SAME ONE
-- ============================================================================
--
-- A goblin's swing is a goblin's business. When a second enemy genuinely needs
-- the same attack it moves to `skills/Shared.luau` and both reference it by id.
-- Not before -- a shared file with one user is indirection with no payer.
--
-- THE POINT OF PUTTING SKILLS HERE AT ALL: attack volumes used to be keyed by
-- WHICH BUTTON WAS PRESSED, so a goblin and a giant meleed with the identical
-- 6.5-stud capsule and there was no path for that to differ. An attack belongs
-- to whoever is swinging it, which is here.

local Goblin = {}

Goblin.id = "GOBLIN"
Goblin.displayName = "Goblin"

Goblin.hp = 60
Goblin.stats = { attack = 8, defense = 3, speed = 6 }

Goblin.aiProfile = "MELEE_CHASER"
Goblin.lootTableId = "GOBLIN_COMMON"
Goblin.lootSlots = 4

-- WHICH HURTBOX SHAPE THIS BODY HAS. A name resolved against
-- HurtboxDefinitions rather than a zone list typed here, because the shape is
-- a property of the MODEL and several enemies will share a rig.
--
-- DUMMY is a single capsule and is honest only for the debug dummies, which
-- genuinely are one part. A real goblin model gets its own entry with zones
-- placed by eye in Studio and read off the rig at spawn.
Goblin.hurtbox = "DUMMY"

-- PLANNED, NOT BUILT. Enemies do not attack at all right now -- the demo that
-- made them swing was retired on 2026-08-21 so the old SWEEP-only model would
-- not be built twice, and they come back after `motion = PATH` exists.
--
-- Written as an empty list rather than omitted so the field's existence and
-- its shape are both visible: this is where a goblin's attacks go.
Goblin.skills = {}

return Goblin
