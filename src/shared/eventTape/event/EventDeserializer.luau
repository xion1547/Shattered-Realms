-- src/shared/eventTape/event/EventDeserializer.luau
--
-- Rebuilds a typed Event from the plain data that came off the wire.
-- See Architecture-Reference.md Part 12.
--
-- ONE SET OF RULES, BOTH DIRECTIONS. It resolves the event class from the
-- registry and calls the same `Event.build` the fluent builder calls, so a
-- payload the builder would reject is rejected here too. That property used
-- to depend on each class remembering to put its checks in a hand-written
-- `deserialize` rather than in its builder -- and the wire half is the half
-- that actually matters, since it is the untrusted one.
--
-- A PLAIN MODULE, not a class. It holds no state, so there is nothing for an
-- instance to own. The old one earned its `.new()`: it carried a module cache
-- and a DataModel root it walked at startup. Declaration checking now happens
-- once at boot via EventRegistry.validate(), and nothing here gates on it --
-- what that check covers is static and cannot change while the game runs.
--
-- Failures are RETURNED, not raised. Everything here came from a client, so
-- malformed input is expected traffic: the router rejects the one bad event
-- and keeps processing the rest of the tape.

local Event = require(script.Parent.Event)
local EventRegistry = require(script.Parent.EventRegistry)

local EventDeserializer = {}

function EventDeserializer.deserialize(serialized: any): (Event.Event?, string?)
    if type(serialized) ~= "table" then
        return nil, "event payload is not a table"
    end

    local eventClass = EventRegistry.get(serialized.eventType)
    if not eventClass then
        return nil, string.format("unknown eventType: %s", tostring(serialized.eventType))
    end

    -- No timestamp is read back off the wire. The sender's clock has an
    -- arbitrary origin and is client-controlled either way; the receiving
    -- side stamps its own arrival time (EventRouter).
    return Event.build(eventClass, serialized.subType, serialized.data, serialized.eventId)
end

return EventDeserializer
