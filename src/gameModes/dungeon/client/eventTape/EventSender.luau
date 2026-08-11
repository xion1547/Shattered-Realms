-- src/gameModes/dungeon/client/eventTape/EventSender.luau
--
-- OUTBOUND ONLY. Builds tapes and puts them on the wire.
-- See Architecture-Reference.md Parts 12 and 15.
--
-- Sends INTENT ONLY -- "I pressed attack", "I clicked entity X" -- never
-- values or state. The server decides what happened.
--
-- BATCHING, and why the tape abstraction earns its name: events queued during
-- a frame are flushed together as one tape, one FireServer. A player mashing
-- three inputs in a frame costs one remote call instead of three, and the
-- server sees them as one ordered batch rather than three interleaved with
-- whatever else arrived. RemoteEvent is reliable and ordered PER SENDER, so
-- the order within a tape -- and between successive tapes from this client --
-- is preserved. There is no ordering relationship with any other client's
-- traffic, and no way to construct one from here; see Part 12.
--
-- `sendNow` exists for actions where a frame of added latency is worse than
-- an extra remote call. Prefer `queue` and let the flush handle it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local eventTapeFolder = ReplicatedStorage:WaitForChild("eventTape")
local eventFolder = eventTapeFolder:WaitForChild("event")
local EventTape = require(eventFolder:WaitForChild("EventTape"))
local MessageKind = require(eventTapeFolder:WaitForChild("wire"):WaitForChild("MessageKind"))
local RemoteEventsEnum = require(ReplicatedStorage:WaitForChild("remoteEvents"):WaitForChild("RemoteEventsEnum"))

-- Must stay at or below the server's MAX_EVENTS_PER_TAPE, or a legitimate
-- burst gets dropped as oversized. Flushing early is always safe.
local MAX_BATCH = 16

local EventSender = {}
EventSender.__index = EventSender

function EventSender.new(pending)
    -- WaitForChild rather than RemoteEventsManager: the server creates this
    -- during its own boot, so the client may well arrive first. Waiting on
    -- the instance is race-free; asking a manager whether it is "allowed"
    -- yet is not.
    local remote = ReplicatedStorage:WaitForChild(RemoteEventsEnum.EventTapeRemote)

    return setmetatable({
        _remote = remote,
        _pending = pending,
        _queue = {},
        _flushConnection = nil,
    }, EventSender)
end

function EventSender:start()
    assert(not self._flushConnection, "[EventSender] already started")
    self._flushConnection = RunService.Heartbeat:Connect(function()
        self:flush()
    end)
end

function EventSender:stop()
    if self._flushConnection then
        self._flushConnection:Disconnect()
        self._flushConnection = nil
    end
    self:flush()
end

-- Queues an event for this frame's tape. Returns the event id so the caller
-- can correlate, though registering an onResolved callback is the better way
-- to react.
function EventSender:queue(event, label, onResolved)
    if self._pending then
        self._pending:add(event:getEventId(), label or event:getEventType(), onResolved)
    end

    table.insert(self._queue, event)

    -- Flush early rather than let a burst exceed what the server accepts.
    if #self._queue >= MAX_BATCH then
        self:flush()
    end

    return event:getEventId()
end

-- Bypasses the frame batch. Use only where a frame of latency actually hurts.
function EventSender:sendNow(event, label, onResolved)
    local id = self:queue(event, label, onResolved)
    self:flush()
    return id
end

function EventSender:flush()
    if #self._queue == 0 then
        return
    end

    local tape = EventTape.new()
    for _, event in ipairs(self._queue) do
        tape:addEvent(event)
    end
    table.clear(self._queue)

    -- serialize() flattens the whole tape to plain data. Metatables do not
    -- survive a RemoteEvent, so anything not returned by it does not arrive.
    self._remote:FireServer({
        kind = MessageKind.TAPE,
        tape = tape:serialize(),
    })
end

function EventSender:queuedCount()
    return #self._queue
end

return EventSender
