-- src/gameModes/dungeon/server/services/authority/EntityService.luau
--
-- AUTHORITY SERVICE. The one map of every live entity in this place, and the
-- one door out of it. See Architecture-Reference.md Part 7 and Part 11.5.
--
-- ONE MAP FOR EVERY ENTITY TYPE, AND NO METHOD THAT NAMES ONE. No getPlayer,
-- no getEnemies, no forPlayer. The moment this service can tell a player from
-- a boss, every caller learns that it can ask -- and the composition
-- guarantee that lets StatService and DamageResolution stay ignorant of what
-- they are holding starts leaking from right here. Behaviour that varies by
-- entity type belongs to the component that varies, not to the registry.
--
-- A caller holding a Roblox Player converts it themselves:
--
--     EntityService:get(player.UserId)
--
-- because PlayerEntity builds its identity from UserId. That knowledge lives
-- at the boundary where a Player object enters the system -- the router, the
-- session handler -- not in here.
--
-- THERE IS NO createEntity, DELIBERATELY. Do not add one to make this
-- symmetric; the asymmetry is the correct shape, and was reasoned to twice.
--
--   * Teardown holds everything it needs -- it has the entity. Setup needs a
--     spawn position and a model, which this service has no business knowing.
--   * "Creation" is not one moment. A player registers on join and attaches a
--     body on CharacterAdded, then detaches and re-attaches on every respawn.
--     An enemy does both at once, once. No single signature covers both.
--   * A createEntity taking a template needs a switch on entity type; one
--     taking an already-built entity is register wearing a hat.
--
-- deleteEntity exists because teardown IS one moment, with a required order,
-- over things that already exist. That is the entire difference.
--
-- Spawning belongs to whatever knows about models and spawn points. That is a
-- spawner's job, and a spawner is allowed to exist.

-- Sibling authority service. A sideways dependency, which Part 6 calls
-- suspicious rather than forbidden -- justified here because detaching is
-- step one of a teardown that must not be splittable across call sites.
local SpatialService = require(script.Parent:WaitForChild("SpatialService"))

local ServerStorage = game:GetService("ServerStorage")
local shared = ServerStorage:WaitForChild("Shared")

local Entity = require(shared:WaitForChild("types"):WaitForChild("Entity"))

local EntityService = {}

-- id -> entity. Keyed by the identity id because that is the only thing every
-- entity type has in common; Entity.Entity is exactly that shape and nothing
-- more. Player ids are UserIds (numbers), enemy ids are strings -- one table
-- holds both, and nothing here has reason to care which it is looking at.
EntityService._entitiesMap = {}
EntityService._count = 0

function EntityService:boot()
    -- Nothing to declare yet. Entity.OnRemoved belongs here once something
    -- needs to drop its references without this service knowing it exists --
    -- AIService is the first candidate.
end

-- Enters an entity into the registry.
--
-- Public, unlike its counterpart, because "an entity begins existing" happens
-- at genuinely different moments per type -- a player on join, an enemy at
-- spawn -- so there is no single caller to hide it behind.
function EntityService:register(entity: Entity.Entity)
    assert(type(entity) == "table" and entity.identity,
        "[EntityService] an entity must carry an identity component")

    local id = entity.identity:getId()
    local existing = self._entitiesMap[id]

    -- A collision is always a bug, never a race: player ids are UserIds and
    -- enemy ids come from a monotonic counter. Silently overwriting would
    -- orphan the first entity -- still attached to SpatialService, no longer
    -- reachable by id, and impossible to delete through the front door.
    assert(existing == nil or existing == entity, string.format(
        "[EntityService] id '%s' is already registered to a different entity",
        tostring(id)))

    if existing == nil then
        self._entitiesMap[id] = entity
        self._count += 1
    end
end

function EntityService:get(id): Entity.Entity?
    return self._entitiesMap[id]
end

-- How many entities are live. Counted incrementally because Lua has no O(1)
-- length for a keyed table, and this is the cheap half of verifying a spawn:
-- this and SpatialService:attachedCount() should agree once bodies exist.
function EntityService:count(): number
    return self._count
end

-- THE ONE TEARDOWN DOOR, and the order is load-bearing:
--
--   1. detach      stop being a hit-detection candidate FIRST, so an attack
--                  resolving mid-teardown cannot find a half-dismantled entity
--   2. unregister  stop being findable by id
--   3. destroy     release the body and connections LAST, because it nils out
--                  fields the earlier steps read
--
-- This is one call rather than three at the call site because every way of
-- getting it wrong fails SILENTLY. Skip step 1 and the entity leaves the map
-- but stays in SpatialService's attached set: a corpse that is still a legal
-- target, forever, with nothing in a log to say so. That exact bug was live
-- in ServerManager:RemovePlayer before this existed.
--
-- Returns whether anything was actually torn down.
function EntityService:deleteEntity(entity: Entity.Entity): boolean
    assert(type(entity) == "table" and entity.identity,
        "[EntityService] an entity must carry an identity component")

    -- Re-entrant on purpose. Death and disconnect can race, and the second
    -- caller must not throw from inside a Scheduler tick or a Roblox event.
    if self._entitiesMap[entity.identity:getId()] == nil then
        return false
    end

    SpatialService:detach(entity)
    self:_unregister(entity)

    -- An OPTIONAL part of the Entity contract. Entity.Entity is "a thing
    -- holding an identity", which a bare table satisfies -- so this is called
    -- when present rather than asserted, and test doubles keep working.
    --
    -- Pulled into a local before calling: narrowing the optional field and
    -- then re-indexing it with method syntax is the form Luau argues about.
    local destroy = entity.destroy
    if destroy then
        destroy(entity)
    end

    return true
end

-- PRIVATE. deleteEntity is the only legitimate caller -- unregistering
-- without detaching produces exactly the ghost described above.
function EntityService:_unregister(entity: Entity.Entity)
    local id = entity.identity:getId()
    if self._entitiesMap[id] == nil then
        return
    end

    self._entitiesMap[id] = nil
    self._count -= 1
end

return EntityService
