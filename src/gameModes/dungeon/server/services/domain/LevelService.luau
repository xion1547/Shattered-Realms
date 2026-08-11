-- DOMAIN SERVICE. Level-up: stat growth and skill unlocks.
-- Every place, and byte-identical in each. See Part 13's persistence test:
-- this writes persisted progression, so a place-specific growth curve would
-- silently diverge save data with no way to un-diverge it.

local LevelService = {}

function LevelService:boot() end

-- Called by ResourceService when EXP hits its ceiling -- the onCeiling
-- behaviour tag names "LEVEL_UP", and the engine recognises the string. The
-- config never holds a function.
function LevelService:onLevelUp(entity) end

function LevelService:ceilingForLevel(level) return 100 * level end

return LevelService
