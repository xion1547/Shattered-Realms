-- INFRASTRUCTURE. The only module that touches DataStore. No exceptions.
-- See Architecture-Reference.md Part 6, Data Layer.
--
-- Rules that are not negotiable:
--   order is validate -> mutate -> confirm -> save, never save first
--   always pcall-wrapped, always retried
--   never called speculatively, only after a confirmed mutation
--   on save failure the entity keeps correct in-memory state; log and let
--   the next successful save carry it. Do not crash.

local DataService = {}

DataService._dirty = {}    -- entityId -> true

function DataService:boot() end

function DataService:load(player) end

function DataService:save(player) end

-- Not every mutation should hit the DataStore the instant it happens.
-- ResourceService marks a resource dirty and this flushes on its own cadence.
function DataService:markDirty(entityId)
    self._dirty[entityId] = true
end

function DataService:flush() end

return DataService
