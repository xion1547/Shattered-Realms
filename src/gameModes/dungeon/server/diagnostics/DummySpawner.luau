-- src/gameModes/dungeon/server/diagnostics/DummySpawner.luau
--
-- TEMPORARY, like PingProbe. Ten anchored dummies so hit detection has
-- something to hit. Delete once ZoneService spawns real encounters.
--
-- A MODULE, NOT A .server SCRIPT, AND THAT IS LOAD-BEARING.
--
-- It was a Script, and it raced the boot test suite. Roblox does not order
-- independent Scripts, so on some runs it attached ten entities BEFORE
-- RunTests ran -- and the targeting suite resolves a 20-stud sphere at the
-- origin, which caught six dummies it had never spawned. That surfaced as
-- "expected 1, actual 7" in a dedup test with nothing wrong with dedup, and
-- it passed or failed depending on which script Roblox happened to start
-- first.
--
-- PingProbe can safely stay a Script because it only OBSERVES. This one
-- mutates the world the tests run against, so Main.server.luau calls it after
-- ServerManager:init(), where the ordering is written down and readable.
--
-- EACH DUMMY IS THE TWO EXISTENCES, side by side (Architecture Part 7):
--
--   the physical half   an anchored Part in workspace, which has a position
--   the mental half     an EnemyEntity, which has hp, stats and an id
--
-- Neither knows about the other until SpatialService:attach links them, and
-- that link is what makes the thing hittable. Registering it in EntityService
-- only makes it findable by id.
--
-- ANCHORED IS LOAD-BEARING, not laziness. An anchored part has no network
-- owner, so no client simulates it and no client can move it. An unanchored
-- one would eventually be handed to whichever player stood nearest, and the
-- position history feeding lag compensation would then be client-authored.

local ServerStorage = game:GetService("ServerStorage")

local serverRoot = game.ServerScriptService:WaitForChild("Server")
local serverShared = ServerStorage:WaitForChild("Shared")

local authority = serverRoot:WaitForChild("services"):WaitForChild("authority")
local EntityService = require(authority:WaitForChild("EntityService"))
local SpatialService = require(authority:WaitForChild("SpatialService"))
local EnemyEntity = require(serverRoot:WaitForChild("entities"):WaitForChild("EnemyEntity"))
local EnemyTemplates = require(serverShared:WaitForChild("definitions"):WaitForChild("EnemyTemplates"))

local COUNT = 10

-- Spread out on purpose. In a pile you cannot tell whether the volume math
-- worked or whether the swing simply caught everything -- the spacing is what
-- makes the test readable.
--
-- Y is half of BODY_SIZE.Y so they sit exactly on the baseplate, whose top
-- surface is y=0 (see dungeon.project.json). Z=10 puts the middle pair inside
-- a 12-stud swing from the default spawn and the rest outside it, which is
-- the point: a test where everything is in range cannot tell you the volume
-- is culling anything.
local SPACING = 6
local ORIGIN = Vector3.new(0, 2.5, 10)

local BODY_SIZE = Vector3.new(4, 5, 4)

-- The hurtbox: the radius of the sphere Overlap tests the attack volume
-- against. Roughly a character's width, and deliberately NOT derived from
-- BODY_SIZE -- the body is what you see, the hurtbox is what you hit, and
-- they are tuned separately.
local HURTBOX_RADIUS = 2.5

local DummySpawner = {}

local function spawnDummy(index: number)
    local entity = EnemyEntity.new(EnemyTemplates.GOBLIN)
    local id = entity.identity:getId()

    local part = Instance.new("Part")
    -- Named after the entity so a hit printed in the output can be found in
    -- the Explorer without counting along the row.
    part.Name = tostring(id)
    part.Anchored = true
    part.Size = BODY_SIZE
    part.Color = Color3.fromRGB(120, 160, 90)
    part.Position = ORIGIN + Vector3.new((index - (COUNT + 1) / 2) * SPACING, 0, 0)
    part.Parent = workspace

    -- The entity's own handle on its body. Not read from the spatial
    -- component, because teardown detaches before it destroys and the anchor
    -- is gone by then (Architecture Part 7).
    entity.model = part

    EntityService:register(entity)
    SpatialService:attach(entity, part, HURTBOX_RADIUS)
end

function DummySpawner.spawnAll()
    for index = 1, COUNT do
        spawnDummy(index)
    end

    -- The two counts should NOT agree. attachedCount is exactly COUNT because
    -- no character has spawned yet; EntityService also holds one entity per
    -- connected player, so it runs ahead by however many people are already in.
    print(string.format(
        "[DummySpawner] spawned %d -- attached=%d registered=%d",
        COUNT, SpatialService:attachedCount(), EntityService:count()))
end

return DummySpawner
