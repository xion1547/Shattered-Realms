-- src/gameModes/dungeon/server/services/authority/ResourceService.luau
--
-- AUTHORITY SERVICE. The single door to the Resources component.
-- See Architecture-Reference.md Parts 8 and 10.
--
-- Generic across every resource and every entity type. It never learns what
-- a shield, an invulnerability window or a DYING lock is -- the domain that
-- ORIGINATES a change resolves the full final amount first and hands this
-- service one number to move.
--
-- Leaf in the dependency graph: it requires components and definitions, and
-- must never require a domain Service. That one rule is what makes cycles
-- structurally impossible in the bottom two layers.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- Definitions are server-only. Floors, ceilings, persistence flags and
-- behaviour tags are game data an exploiter should never be able to read --
-- and the client has no use for them, since it only ever displays numbers
-- the server sends it.
local serverShared = ServerStorage:WaitForChild("Shared")
local ResourceDefinitions = require(serverShared:WaitForChild("definitions"):WaitForChild("ResourceDefinitions"))
local SignalService = require(ReplicatedStorage:WaitForChild("utils"):WaitForChild("signal"):WaitForChild("SignalService"))

local ResourceService = {}

ResourceService._signals = {}   -- resourceId -> fire-capable Signal, private
ResourceService._dirty = {}     -- entityId -> { resourceId = true }

function ResourceService:boot()
    -- Per-resource Facts are GENERATED from the definitions table, never
    -- hand-declared: a new resource costs zero lines of signal wiring.
    -- TODO: the vocabulary must contain these names before declare() will
    -- accept them. Generate the name list from ResourceDefinitions and pass
    -- it to SignalService.init as a third vocabulary.
    for _ in pairs(ResourceDefinitions) do
        -- self._signals[resourceId] = SignalService.declare(
        --     string.format("Player.Resources.%s.OnChanged", resourceId))
    end
end

function ResourceService:getDefinition(resourceId)
    return ResourceDefinitions[resourceId]
end

-- QUERY. Never mutates, never persists, never fires.
function ResourceService:get(entity, resourceId)
    return entity.resources:get(resourceId)
end

-- Resolves a ceiling that references another resource id ("MaxHP").
function ResourceService:_resolveCeiling(entity, definition)
    if definition.ceiling == nil then
        return nil
    end
    if type(definition.ceiling) == "number" then
        return definition.ceiling
    end
    return entity.resources:get(definition.ceiling)
end

-- MUTATION. amount is always the FINAL, fully-resolved number: this service
-- does not apply modifiers, and callers must not expect it to.
--
-- Returns the amount actually applied after clamping -- the caller builds
-- its outbound diff from THIS value, never from what it computed, or the
-- client renders a number that never landed.
function ResourceService:grant(entity, resourceId, amount, source, eventId)
    -- TODO: validate, clamp to floor/ceiling, write via resources:setRaw,
    -- mark dirty if persistent, push the outbound confirmation, run any
    -- onCeiling behaviour tag, then fire the Fact as the last step.
    return 0
end

function ResourceService:drain(entity, resourceId, amount, source, eventId)
    -- TODO: same shape as grant, with the onFloor behaviour tag.
    return 0
end

-- Administrative set, for initialisation. Bypasses no validation, but
-- carries no delta semantics.
function ResourceService:set(entity, resourceId, value, source)
    -- TODO
end

-- Scheduler entry point (Part 14). 20Hz -- regen does not need a frame.
function ResourceService:tick(deltaTime)
    -- TODO: advance regen for entities with regenerating resources.
end

return ResourceService
