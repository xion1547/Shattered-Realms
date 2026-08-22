-- src/gameModes/dungeon/client/eventTape/EventReceiver.luau
--
-- INBOUND ONLY. Reads what the server sends back and dispatches it.
-- See Architecture-Reference.md Parts 12 and 15.
--
-- ABOUT THE PARAMETER THAT USED TO BE CALLED `envelope`:
--
-- Every payload the server sends is a MESSAGE with a `kind` field, and the
-- kind is what tells the receiver how to read the rest. It is not "validated
-- intent" -- intent only ever travels client -> server. This direction
-- carries the server's ANSWER: a rejection, a confirmation, or an
-- unsolicited fact. `message` is the honest name, and `MessageKind` replaces
-- the bare string it used to be compared against.
--
-- Nothing here decides anything. It parses, routes by kind, and hands off --
-- the same shape as the server's EventRouter, pointed the other way.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local wireFolder = ReplicatedStorage:WaitForChild("eventTape"):WaitForChild("wire")
local MessageKind = require(wireFolder:WaitForChild("MessageKind"))
local RejectReason = require(wireFolder:WaitForChild("RejectReason"))

local EventReceiver = {}
EventReceiver.__index = EventReceiver

function EventReceiver.new(remote, pending)
    return setmetatable({
        _remote = remote,
        _pending = pending,
        _connection = nil,
        _pushHandlers = {},   -- eventType -> fn(payload)

        -- eventType -> true, once it has been reported as unhandled. See
        -- _onPush: the note is worth printing, the repetition is not.
        _warnedUnhandled = {},
    }, EventReceiver)
end

function EventReceiver:start()
    assert(not self._connection, "[EventReceiver] already started")
    self._connection = self._remote.OnClientEvent:Connect(function(message)
        self:_dispatch(message)
    end)
end

function EventReceiver:stop()
    if self._connection then
        self._connection:Disconnect()
        self._connection = nil
    end
end

-- Register what should happen when the server pushes a given eventType.
-- This is where the display layer plugs in.
function EventReceiver:onPush(eventType, handler)
    assert(type(handler) == "function", "[EventReceiver] handler must be a function")
    self._pushHandlers[eventType] = handler
end

function EventReceiver:_dispatch(message)
    -- The server is trusted, but the shape still gets checked: a malformed
    -- message here means a version mismatch between client and server
    -- builds, and silently ignoring it makes that invisible.
    if type(message) ~= "table" or not MessageKind.isValid(message.kind) then
        warn("[EventReceiver] discarded a message with no valid kind")
        return
    end

    if message.kind == MessageKind.REJECT then
        self:_onReject(message)
    elseif message.kind == MessageKind.CONFIRM then
        self:_onConfirm(message)
    elseif message.kind == MessageKind.PUSH then
        self:_onPush(message)
    end
end

function EventReceiver:_onReject(message)
    local entry = self._pending:resolve(message.eventId, "REJECT", message)

    if not entry then
        -- Normal, not an error: an id this client never tracked. A
        -- hand-rolled payload produces exactly this.
        warn(string.format(
            "[EventReceiver] rejection for an untracked event (id=%s, reason=%s)",
            tostring(message.eventId), tostring(message.reason)))
        return
    end

    if RejectReason.isStructural(message.reason) then
        -- Structural means the payload was refused before any game logic ran,
        -- so it is a build mismatch or someone probing -- loud, never shown
        -- in-game.
        --
        -- UNROUTABLE is the one a legitimate client CAN see: a place that
        -- excludes a Service rejects its eventType by design (Part 13), so a
        -- client that has not caught up with which place it is in produces
        -- exactly this. Still worth a warning, but it is not proof of tampering.
        warn(string.format(
            "[EventReceiver] STRUCTURAL rejection of '%s': %s",
            entry.label, tostring(message.reason)))
    else
        -- ILLEGAL is the only reason a real player will ever see, and the
        -- only one worth surfacing in the UI.
        print(string.format("[EventReceiver] '%s' refused: %s", entry.label, tostring(message.reason)))
    end
end

function EventReceiver:_onConfirm(message)
    local entry = self._pending:resolve(message.eventId, "CONFIRM", message)
    if entry then
        -- TODO: apply message.diff to the display layer. The diff carries
        -- what ACTUALLY changed, built from what the server's commits
        -- returned -- never from what anything computed (Part 11.1).
    end
end

function EventReceiver:_onPush(message)
    local handler = self._pushHandlers[message.eventType]
    if handler then
        local ok, err = pcall(handler, message.payload)
        if not ok then
            warn(string.format(
                "[EventReceiver] push handler for '%s' errored: %s",
                tostring(message.eventType), tostring(err)))
        end
        return
    end

    -- Unhandled pushes are expected while the display layer is unbuilt -- but
    -- ONCE PER EVENT TYPE, not once per push. A server that pushes on a timer
    -- turns a useful "nothing is listening to this yet" note into a line every
    -- few frames, which drowns the output it was meant to help you read.
    --
    -- The fact worth reporting is "COMBAT has no handler", and that fact does
    -- not change between pushes.
    if not self._warnedUnhandled[message.eventType] then
        self._warnedUnhandled[message.eventType] = true
        print(string.format(
            "[EventReceiver] no push handler for '%s' -- further ones stay quiet",
            tostring(message.eventType)))
    end
end

return EventReceiver
