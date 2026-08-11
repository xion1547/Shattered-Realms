-- src/gameModes/dungeon/client/eventTape/EventTapeClient.luau
--
-- The one thing the rest of the client talks to. Owns the sender, the
-- receiver and the pending-actions map, and wires them together.
--
-- Three pieces rather than one, because they are three jobs:
--   EventSender     builds and batches outbound tapes
--   EventReceiver   parses inbound messages and routes them by kind
--   PendingActions  remembers what was sent so an answer can be matched to it
--
-- The previous single EventSender did all three, which is why it read as
-- messy: `send` was building a tape AND recording pending state, and the
-- inbound connection was buried inside an outbound-sounding module.
--
-- This façade is the only file input code needs to import.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RemoteEventsEnum = require(ReplicatedStorage:WaitForChild("remoteEvents"):WaitForChild("RemoteEventsEnum"))

local PendingActions = require(script.Parent:WaitForChild("PendingActions"))
local EventSender = require(script.Parent:WaitForChild("EventSender"))
local EventReceiver = require(script.Parent:WaitForChild("EventReceiver"))

local EventTapeClient = {}
EventTapeClient.__index = EventTapeClient

function EventTapeClient.new()
    local remote = ReplicatedStorage:WaitForChild(RemoteEventsEnum.EventTapeRemote)
    local pending = PendingActions.new()

    return setmetatable({
        _remote = remote,
        pending = pending,
        sender = EventSender.new(pending),
        receiver = EventReceiver.new(remote, pending),
        _sweepConnection = nil,
    }, EventTapeClient)
end

function EventTapeClient:start()
    -- Receiver first: an answer cannot arrive before anything is sent, but
    -- starting the listener first means there is no window where one could.
    self.receiver:start()
    self.sender:start()

    self._sweepConnection = RunService.Heartbeat:Connect(function()
        self.pending:sweep()
    end)
end

function EventTapeClient:stop()
    if self._sweepConnection then
        self._sweepConnection:Disconnect()
        self._sweepConnection = nil
    end
    self.sender:stop()
    self.receiver:stop()
    self.pending:clear()
end

-- Convenience pass-throughs, so callers do not reach through into the parts.
function EventTapeClient:queue(event, label, onResolved)
    return self.sender:queue(event, label, onResolved)
end

function EventTapeClient:sendNow(event, label, onResolved)
    return self.sender:sendNow(event, label, onResolved)
end

function EventTapeClient:onPush(eventType, handler)
    self.receiver:onPush(eventType, handler)
end

return EventTapeClient
