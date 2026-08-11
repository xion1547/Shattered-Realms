-- src/gameModes/dungeon/client/eventTape/PendingActions.luau
--
-- Actions this client has sent and not yet heard back about.
-- See Architecture-Reference.md Part 15.
--
-- This is the client half of the reconciliation contract, and it is the only
-- reason events carry an id at all: the client plays an animation
-- immediately, optimistically, before the server has said anything -- so when
-- the server does answer, something has to know WHICH optimistic action the
-- answer is about. That is this map.
--
-- It is its own module rather than a field on the sender because it has real
-- behaviour (expiry, rollback callbacks) and is the piece most likely to grow
-- once prediction is real. Sending and remembering-what-was-sent are
-- different jobs.

local PendingActions = {}
PendingActions.__index = PendingActions

-- An action nobody answered within this long is assumed lost. Without a
-- sweep, a dropped confirmation leaks an entry and its optimistic state
-- never resolves -- the animation just stays wrong forever.
local DEFAULT_TIMEOUT = 10

function PendingActions.new(timeout)
    return setmetatable({
        _entries = {},
        _timeout = timeout or DEFAULT_TIMEOUT,
    }, PendingActions)
end

-- `onResolved(outcome, message)` is where an optimistic animation gets
-- confirmed or reversed. outcome is "CONFIRM", "REJECT" or "TIMEOUT".
function PendingActions:add(eventId, label, onResolved)
    assert(type(eventId) == "string", "[PendingActions] eventId must be a string")

    self._entries[eventId] = {
        eventId = eventId,
        label = label or "unnamed",
        sentAt = os.clock(),
        onResolved = onResolved,
    }
end

function PendingActions:get(eventId)
    return self._entries[eventId]
end

function PendingActions:count()
    local count = 0
    for _ in pairs(self._entries) do
        count += 1
    end
    return count
end

-- Returns the entry, or nil if this client was not tracking it -- which is
-- normal, not an error: a PUSH is unsolicited, and a hand-rolled payload
-- carries an id nothing here ever recorded.
function PendingActions:resolve(eventId, outcome, message)
    local entry = self._entries[eventId]
    if not entry then
        return nil
    end

    self._entries[eventId] = nil

    if entry.onResolved then
        local ok, err = pcall(entry.onResolved, outcome, message)
        if not ok then
            warn(string.format(
                "[PendingActions] rollback for '%s' errored: %s", entry.label, tostring(err)))
        end
    end

    return entry
end

-- Call once per frame. Resolves anything that has waited too long, so a lost
-- packet cannot strand optimistic state permanently.
function PendingActions:sweep()
    local now = os.clock()
    local expired

    for eventId, entry in pairs(self._entries) do
        if now - entry.sentAt > self._timeout then
            expired = expired or {}
            table.insert(expired, eventId)
        end
    end

    if not expired then
        return
    end

    for _, eventId in ipairs(expired) do
        local entry = self._entries[eventId]
        warn(string.format(
            "[PendingActions] '%s' timed out after %.1fs with no answer",
            entry.label, self._timeout))
        self:resolve(eventId, "TIMEOUT", nil)
    end
end

function PendingActions:clear()
    table.clear(self._entries)
end

return PendingActions
