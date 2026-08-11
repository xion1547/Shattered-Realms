-- src/shared/eventTape/event/Event.luau
--
-- THE Event instance. One class; the differences between event types live in
-- their declarations (types/*.luau), not in subclasses.
-- See Architecture-Reference.md Part 4, Part 5 and Part 12.
--
-- A dumb data object. It knows nothing about which Service consumes it --
-- routing lives in a server-only table (Part 12), because these modules load
-- on the client too and an Event reaching upward would drag a server-only
-- module across the boundary.

local HttpService = game:GetService("HttpService")

local EventSchema = require(script.Parent.EventSchema)

local Event = {}
Event.__index = Event

-- What a parsed payload looks like once EventSchema is done with it: declared
-- fields only, defaults applied. Values stay `any` because each event type
-- decides its own -- the schema is where that gets narrowed, at runtime.
export type Fields = { [string]: any }

-- PLAIN DATA, and the exact shape that crosses a RemoteEvent. Anything not
-- listed here does not arrive on the other side.
export type SerializedEvent = {
    eventId: string,
    eventType: string,
    subType: string,
    data: Fields,
}

-- CONFIG vs MODULE, and why there are two types rather than one.
--
-- A file under types/ is not one kind of thing. Its eventType, SubType and
-- schema are pure declarative data -- config in the Part 2 sense. Its Builder,
-- its hand-written :withX() methods and its accessors are code. Calling the
-- whole file a Config would promise the next reader they can treat it as data,
-- and a third of it is not.
--
-- So: EventConfig is the data half. EventModule is the whole file. Which one a
-- function asks for says exactly what it touches -- and it is not a
-- distinction invented for tidiness, see the ordering constraint below.
-- The data half of a types/ module: its name, its vocabulary, its parameters.
-- Nothing here is a function, which is what makes it config rather than code.
--
-- It is also what a module has BEFORE its builder exists, and that is not a
-- coincidence -- there is a genuine chicken-and-egg in every types/ module:
-- EventBuilder.extend(Config) is called partway down the file, and
-- `builder()` cannot be defined until after it, because what builder()
-- returns is the very Builder extend() is producing. So extend() has to
-- accept a module that is not finished yet, and the data half is exactly the
-- part that IS finished by then. Asking for the whole module there fails with
-- "missing field 'builder'" on a file that is perfectly correct.
export type EventConfig = {
    eventType: string,
    SubType: { [string]: string },
    schema: EventSchema.Schema,
}

-- The whole module: config plus the code that goes with it. What the registry
-- holds, and what every consumer sees.
--
-- `Builder` stays `any` deliberately. Each event type's builder is its own
-- table with its own :withX() methods -- the whole reason they are
-- hand-written -- and no single type can describe all of them without erasing
-- exactly the autocomplete they exist to provide.
export type EventModule = EventConfig & {
    Builder: any,
}

-- The instance's own fields, named so the methods below can annotate `self`
-- with it. Without that, every `self._data` inside this file is `any`.
--
-- The metatable-carrying `Event` type is at the BOTTOM of this file, for the
-- same reason as Signal's: typeof(setmetatable({}, Event)) resolves against
-- the Event table as it stands, so it has to come after the methods.
type EventState = {
    _eventId: string,
    _eventType: string,
    _subType: string,
    _data: Fields,
    _class: EventConfig,
    _timeStamp: number,
}

-- Every Event carries an id, always (Part 5). It correlates a client's
-- optimistic prediction with the server's confirmation or rejection (Part
-- 15), and must survive serialization -- an id that exists only in memory is
-- the same as no id at all.
local function newEventId()
    return HttpService:GenerateGUID(false)
end

-- Returns (event) or (nil, reason).
--
-- Failures are RETURNED rather than raised because this is the path
-- deserialization takes, where malformed input is expected traffic from a
-- client rather than a programmer error. The builder raises instead.
-- Takes EventConfig, not EventModule, because the config is genuinely all it
-- touches: eventType, SubType and schema. Demanding a builder it never calls
-- would break the authoring path, where the builder hands over a module that
-- is still mid-construction. EventModule is what the REGISTRY requires, and
-- that is the right place for it.
function Event.build(
    eventClass: EventConfig,
    subType: string,
    fields: Fields?,
    eventId: string?
): (Event?, string?)
    if type(eventClass) ~= "table" or type(eventClass.eventType) ~= "string" then
        return nil, "not an event class"
    end
    if eventClass.SubType[subType] == nil then
        return nil, string.format(
            "'%s' is not a subType of %s", tostring(subType), eventClass.eventType)
    end

    local parsed, reason = EventSchema.parse(
        eventClass.eventType, subType, eventClass.schema, fields or {})
    if not parsed then
        return nil, reason
    end

    return setmetatable({
        _eventId = eventId or newEventId(),
        _eventType = eventClass.eventType,
        _subType = subType,
        _data = parsed,
        _class = eventClass,
        -- LOCAL ONLY. Never serialized, and deliberately so.
        --
        -- os.clock() is a monotonic counter with an arbitrary per-process
        -- origin, not a wall clock: a client reporting 412 and a server
        -- reporting 7200 share no zero point, so comparing them across the
        -- wire is meaningless in principle rather than merely imprecise. And
        -- a client-stamped time would be a client-reported VALUE even if the
        -- clocks did agree -- Part 13's never-list, and the exact input the
        -- latency rewind must not let a client choose.
        --
        -- Anything ordering-related uses EventRouter's own receivedAt.
        _timeStamp = os.clock(),
    }, Event)
end

function Event.getEventId(self: EventState): string
    return self._eventId
end

function Event.getEventType(self: EventState): string
    return self._eventType
end

function Event.getSubType(self: EventState): string
    return self._subType
end

function Event.getData(self: EventState): Fields
    return self._data
end

-- The event class this was built from, so a caller holding an Event can
-- reach its accessors: CombatEvent.getSkillId(event).
function Event.getClass(self: EventState): EventConfig
    return self._class
end

-- Reads one validated parameter. Anything absent either was not sent or has
-- no default -- an undeclared field could never have got this far, because
-- validation rejects the whole event.
function Event.get(self: EventState, field: string): any
    return self._data[field]
end

-- When THIS machine built the event. There is no setter: the value is only
-- meaningful on the machine that produced it, so nothing should be able to
-- overwrite it with a number that came from somewhere else.
function Event.getTimeStamp(self: EventState): number
    return self._timeStamp
end

-- Produces PLAIN data. Nothing with a metatable survives a RemoteEvent, so
-- anything not returned here does not reach the other side.
function Event.serialize(self: EventState): SerializedEvent
    return {
        eventId = self._eventId,
        eventType = self._eventType,
        subType = self._subType,
        data = self._data,
    }
end

-- Declared last so it carries the methods above, not just the fields.
export type Event = typeof(setmetatable({} :: EventState, Event))

return Event
