-- src/gameModes/dungeon/client/diagnostics/PingProbe.client.luau
--
-- TEMPORARY DIAGNOSTIC. The client half of PingProbe.server.luau. Delete
-- both together.
--
-- It echoes the server's timestamp back untouched and does nothing else.
-- Deliberately NOT routed through EventTape: the tape batches on Heartbeat
-- and would add a frame of its own latency to the very number being
-- measured. This is also why the echo happens inside the connection handler
-- rather than being queued -- every microsecond spent here is added to the
-- measurement as positive bias.
--
-- The value is never read or trusted, only returned, so there is nothing
-- here a client could usefully lie about: the server compares against its
-- own clock and discards anything that comes back negative.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remote = ReplicatedStorage:WaitForChild("PingProbeRemote", 30)
if not remote then
    warn("[PingProbe] no PingProbeRemote -- is the server half in this build?")
    return
end

remote.OnClientEvent:Connect(function(sentAt)
    remote:FireServer(sentAt)
end)

print("[PingProbe] client echo ready")
