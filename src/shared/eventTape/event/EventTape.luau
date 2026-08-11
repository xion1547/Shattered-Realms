-- src/shared/eventTape/event/EventTape.luau
--
-- An ordered batch of Events. See Architecture-Reference.md Part 12.
--
-- A tape is a container, nothing more. It does not decide anything, does not
-- know what its events mean, and does not sort -- ordering is arrival order,
-- which the tape preserves simply by being a list.

local Event = require(script.Parent.Event)

local EventTape = {}
EventTape.__index = EventTape

-- The whole payload as it crosses the wire: a list of serialized events under
-- one key. `unpackSerialized` is the only thing that should read it directly.
export type SerializedTape = {
    events: { Event.SerializedEvent },
}

-- The instance's own fields, so the methods below can annotate `self`. The
-- metatable-carrying EventTape type is at the bottom, after the methods.
type TapeState = {
    _events: { Event.Event },
}

function EventTape.new(): EventTape
    local state: TapeState = {
        _events = {},
    }
    return setmetatable(state, EventTape)
end

function EventTape.getEvents(self: TapeState): { Event.Event }
    return self._events
end

function EventTape.addEvent(self: TapeState, event: Event.Event): TapeState
    assert(type(event) == "table", "[EventTape] event must be a table")
    table.insert(self._events, event)
    return self
end

function EventTape.count(self: TapeState): number
    return #self._events
end

function EventTape.isEmpty(self: TapeState): boolean
    return #self._events == 0
end

function EventTape.clear(self: TapeState)
    table.clear(self._events)
end

-- Produces PLAIN data, all the way down.
--
-- The previous version returned `{ events = self._events }` -- the live list
-- of Event OBJECTS. Metatables do not survive a RemoteEvent, so the receiver
-- got plain tables while the deserializer expected something it could call
-- methods on. Mapping each event through its own serialize() is what makes
-- the inbound path possible at all.
function EventTape.serialize(self: TapeState): SerializedTape
    local events: { Event.SerializedEvent } = table.create(#self._events)
    for index, event in ipairs(self._events) do
        events[index] = event:serialize()
    end
    return { events = events }
end

-- Returns the raw list of plain event tables from a received payload. It
-- deliberately does NOT rebuild typed Events -- that is EventDeserializer's
-- job, and it needs to happen per event so one malformed entry can be
-- rejected without discarding the rest of the tape.
function EventTape.unpackSerialized(serialized: any): ({ Event.SerializedEvent }?, string?)
    if type(serialized) ~= "table" then
        return nil, "payload is not a table"
    end
    if type(serialized.events) ~= "table" then
        return nil, "payload has no events list"
    end
    return serialized.events
end

-- Declared last so it carries the methods above.
export type EventTape = typeof(setmetatable({} :: TapeState, EventTape))

return EventTape
