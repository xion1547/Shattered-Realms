-- src/gameModes/dungeon/server/diagnostics/DummySpawner.luau
--
-- TEMPORARY. Ten anchored dummies so hit detection has
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
-- A Script that only OBSERVES can be independent. This one
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
local HurtboxDefinitions = require(serverShared:WaitForChild("definitions")
    :WaitForChild("HurtboxDefinitions"))

local COUNT = 10

-- Spread out on purpose. In a pile you cannot tell whether the volume math
-- worked or whether the swing simply caught everything -- the spacing is what
-- makes the test readable.
--
-- Y is half the body height so they sit exactly on the baseplate, whose top
-- surface is y=0 (see dungeon.project.json). Z=10 puts the middle pair inside
-- a 12-stud swing from the default spawn and the rest outside it, which is
-- the point: a test where everything is in range cannot tell you the volume
-- is culling anything.
local SPACING = 6
local ORIGIN = Vector3.new(0, 3, 10)

-- THE BODY IS BUILT FROM THE HURTBOX, not the other way round.
--
-- These were 4x5x4 blocks with a sphere, then 3x6x3 blocks with a derived
-- capsule -- and that second one was RIGHT and still unreadable, because a
-- capsule inscribed in a box leaves the box's corners sticking out of it.
-- Correct maths, and it looks like the hurtbox is the wrong size.
--
-- So the dummy is now a capsule made of parts: two balls and a shaft, exactly
-- the three pieces HurtboxDebug draws an overlay from. WHAT YOU SEE IS WHAT
-- YOU HIT, to the stud, and any disagreement on screen is a real bug rather
-- than a shape mismatch nobody can unsee.
--
-- Real enemies will not work this way -- they are meshes, and §7.2.1's
-- derivation is for them. This is a test fixture, and a test fixture that
-- cannot be misread is worth more than one that is realistic.
local HURTBOX_RADIUS = 1.5
local HURTBOX_HALF_HEIGHT = 1.5

-- Total 3 wide, 6 tall: roughly a character, and tall enough that a capsule
-- is visibly not a sphere.
local BODY_HEIGHT = HURTBOX_HALF_HEIGHT * 2 + HURTBOX_RADIUS * 2
local BODY_COLOR = Color3.fromRGB(120, 160, 90)

local DummySpawner = {}

-- Every piece carries the entity's id as its Name, so InputSystem's
-- mouse-target hint works whichever part of the body the cursor is over --
-- and so a hit printed in the output can be found in the Explorer without
-- counting along the row.
local function piece(name: string, shape: Enum.PartType, size: Vector3, cf: CFrame, parent: Instance): Part
    local part = Instance.new("Part")
    part.Name = name
    part.Shape = shape
    part.Size = size
    part.CFrame = cf
    part.Anchored = true
    part.Color = BODY_COLOR
    part.TopSurface = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth
    part.Parent = parent
    return part
end

local function spawnDummy(index: number)
    local entity = EnemyEntity.new(EnemyTemplates.GOBLIN)
    local id = tostring(entity.identity:getId())

    local centre = ORIGIN + Vector3.new((index - (COUNT + 1) / 2) * SPACING, 0, 0)
    local diameter = HURTBOX_RADIUS * 2

    local model = Instance.new("Model")
    model.Name = id

    -- THE SHAFT IS THE ANCHOR, and its local Y is the capsule's axis -- the
    -- same axis SpatialComponent:endpoints builds along. The two balls are
    -- decoration that happens to sit exactly where the segment ends, which is
    -- the entire point: the body and the hurtbox are the same three numbers.
    local shaft = piece(id, Enum.PartType.Block,
        Vector3.new(diameter, HURTBOX_HALF_HEIGHT * 2, diameter),
        CFrame.new(centre), model)

    piece(id, Enum.PartType.Ball, Vector3.new(diameter, diameter, diameter),
        CFrame.new(centre + Vector3.new(0, HURTBOX_HALF_HEIGHT, 0)), model)
    piece(id, Enum.PartType.Ball, Vector3.new(diameter, diameter, diameter),
        CFrame.new(centre - Vector3.new(0, HURTBOX_HALF_HEIGHT, 0)), model)

    model.PrimaryPart = shaft
    model.Parent = workspace

    -- The entity's own handle on its body -- the MODEL, not the shaft. Not
    -- read back from the spatial component, because teardown detaches before
    -- it destroys and the anchor is gone by then, and because what needs
    -- destroying is the whole model (Architecture Part 7).
    entity.model = model

    EntityService:register(entity)
    SpatialService:attach(entity, shaft, HurtboxDefinitions.DUMMY)
end

function DummySpawner.spawnAll()
    for index = 1, COUNT do
        spawnDummy(index)
    end

    -- The two counts should NOT agree. attachedCount is exactly COUNT because
    -- no character has spawned yet; EntityService also holds one entity per
    -- connected player, so it runs ahead by however many people are already in.
    -- The two counts should NOT agree, and the reason is worth printing
    -- rather than remembering.
    print(string.format(
        "[DummySpawner] spawned %d  capsule r=%.2f halfHeight=%.2f "
            .. "(%.1f wide, %.1f tall)  body built FROM the hurtbox, so they match exactly",
        COUNT, HURTBOX_RADIUS, HURTBOX_HALF_HEIGHT,
        HURTBOX_RADIUS * 2, BODY_HEIGHT))

    print(string.format(
        "    laid out along X from %.1f to %.1f, spacing %.1f, at z=%.1f",
        ORIGIN.X - (COUNT - 1) / 2 * SPACING,
        ORIGIN.X + (COUNT - 1) / 2 * SPACING,
        SPACING, ORIGIN.Z))

    print(string.format(
        "    attached=%d registered=%d  (registered runs ahead by one per "
            .. "connected player -- an entity exists before its body does)",
        SpatialService:attachedCount(), EntityService:count()))
end

return DummySpawner
