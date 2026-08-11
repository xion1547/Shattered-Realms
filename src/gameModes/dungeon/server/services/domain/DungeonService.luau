-- DOMAIN SERVICE. Instance lifecycle, wave spawning, boss spawn.
-- Dungeon place only. See Architecture-Reference.md Part 10.

local DungeonService = {}

DungeonService._instances = {}

function DungeonService:boot() end

function DungeonService:createInstance(partyId) end

-- Must tear down every entity it spawned AND their Signal subscriptions:
-- module-level Facts outlive an instance, so a per-run listener that is
-- never disconnected is a leak. This is why Signal:Connect returns a handle.
function DungeonService:destroyInstance(instanceId) end

function DungeonService:spawnWave(instanceId, waveNumber) end

function DungeonService:spawnBoss(instanceId, bossType) end

return DungeonService
