-- DOMAIN SERVICE. Current zone per entity, zone-gated eligibility.
-- See Architecture-Reference.md Part 10.
--
-- Distinct from Part 13's PLACES: a place is a separate Roblox experience
-- reached by teleport, a zone is a region within one place.

local ZoneService = {}

function ZoneService:boot() end

function ZoneService:getZone(entity) return nil end

function ZoneService:canPickupHere(entity) return true end

return ZoneService
