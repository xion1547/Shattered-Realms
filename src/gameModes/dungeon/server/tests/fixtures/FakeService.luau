-- Test fixture. A stand-in for a real domain Service, so EventRouter's
-- route resolution can be exercised against an actual ModuleScript rather
-- than a synthesized one (ModuleScript.Source is not writable at runtime).

local FakeService = {}

FakeService.received = {}

-- receivedAt is captured so a test can prove the router actually forwards it.
-- It once did not: the closure resolveRoutes built took only (player, event),
-- and Lua discards extra arguments silently, so the server's own arrival
-- timestamp was stamped, buffered, and then dropped at the final hop.
function FakeService:OnAttack(player, event, receivedAt)
    table.insert(FakeService.received, {
        player = player,
        event = event,
        receivedAt = receivedAt,
    })
end

function FakeService.reset()
    table.clear(FakeService.received)
end

return FakeService
