-- DOMAIN SERVICE. Milestone tracking.
--
-- A PURE LISTENER: it is never called directly by another Service, only ever
-- reacting to Facts. It is the canonical example of an OPTIONAL relationship
-- -- a kill means exactly the same thing whether or not this is watching --
-- which is precisely when Signal is the right tool.
--
-- Note it subscribes by NAME. It cannot require(CombatService), because in a
-- place that excludes Combat that require would not resolve.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SignalService = require(ReplicatedStorage:WaitForChild("utils"):WaitForChild("signal"):WaitForChild("SignalService"))

local AchievementService = {}

AchievementService._subscriptions = {}

function AchievementService:boot()
    -- TODO, once these names are in the vocabulary:
    -- table.insert(self._subscriptions,
    --     SignalService.on("Combat.OnKill", function(attacker, victim)
    --         self:_check(attacker, "KILLS", 1)
    --     end))
end

function AchievementService:_check(entity, milestoneId, delta) end

return AchievementService
