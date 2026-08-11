-- INFRASTRUCTURE. Join/leave flow, data load/save, teleport gating.
-- Every place. See Architecture-Reference.md Parts 10 and 13.
--
-- Owns the session Facts. ServerManager currently declares them because
-- this service does not do anything yet -- move the two declare() calls
-- here once it does, since a fact belongs to whoever actually causes it.

local SessionService = {}

SessionService._signals = {}

function SessionService:boot()
    -- TODO: take ownership of Player.Session.OnJoined / OnLeft from
    -- ServerManager.
end

-- Routed from EventTape: eventType SESSION resolves here.
function SessionService:OnAction(player, event) end

function SessionService:onPlayerAdded(player) end

-- Save before teleporting, and BLOCK the teleport if the save fails
-- (Part 6's Data Layer rules). Losing a run is recoverable; losing
-- persisted progression is not.
function SessionService:onPlayerRemoving(player) end

function SessionService:teleportTo(player, placeId) end

return SessionService
