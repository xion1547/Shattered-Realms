-- src/shared/eventTape/event/EventBuilder.luau
--
-- The base fluent builder. Every event type extends this and adds one
-- :withX() per parameter it accepts.
--
--     EventFactory.create(AnimationEvent)
--         :withSubType(AnimationEvent.SubType.ATTACK)
--         :withId("animation1")
--         :withSpeed(1.25)
--         :build()
--
-- WHY HAND-WRITTEN :withX() AND NOT A PAYLOAD TABLE: a table literal gives
-- you nothing until you already know the field names. The methods ARE the
-- documentation -- type a colon and Studio lists exactly what this event
-- accepts, with the argument type on each one. `{ id = "asdf" }` looks the
-- same whether it is right or wrong.
--
-- THE DRIFT THIS WOULD OTHERWISE CAUSE is closed by a validator, not by
-- generating the methods: EventRegistry.validate() asserts every parameter in
-- an event's schema has a matching :withX(), and that every :withX()
-- corresponds to a real parameter. Generating them would kill the
-- autocomplete that is the entire point, so the invariant is CHECKED
-- instead. Add a schema field without its method and the server refuses to
-- boot, naming the method you forgot.
--
-- The base does real work rather than faking an abstract. An earlier version
-- had `withSubType` throw "must be implemented by subclasses", which meant
-- the base was unusable alone and every event reimplemented the same check --
-- but a builder already knows which event class it belongs to, so it can
-- validate a subType without help.

local Event = require(script.Parent.Event)
local EventSchema = require(script.Parent.EventSchema)

local EventBuilder = {}
EventBuilder.__index = EventBuilder

-- What every builder instance carries, whichever event type it belongs to.
--
-- Methods below annotate `self` with this instead of leaving it implicit,
-- which is the whole reason `self._eventClass` resolves to a real
-- EventConfig rather than `any`.
export type BuilderState = {
    _eventClass: Event.EventConfig,
    _subType: string?,
    _eventId: string?,
    _fields: Event.Fields,
}

-- Builds the method name a schema field is expected to expose:
--   "id" -> "withId",  "targetId" -> "withTargetId"
function EventBuilder.methodNameFor(field: string): string
    return "with" .. field:sub(1, 1):upper() .. field:sub(2)
end

-- Creates a builder class for one event class. The returned table is where
-- that event's :withX() methods get defined -- and because it is a concrete
-- named table, a language server can follow it.
-- THE RETURN TYPE IS DELIBERATELY LEFT TO INFERENCE. Naming it would be
-- actively harmful: each event type adds its own :withX() methods to the
-- table this returns, so a declared return type -- `any` included -- pins the
-- shape at the moment of the call and every method added afterwards becomes
-- invisible. Inference lets the local grow as those methods are defined,
-- which is the only way the per-type autocomplete these builders exist for
-- can survive.
--
-- Takes EventConfig, NOT EventModule: at this point in a types/ module the
-- config half is complete -- eventType, SubType, schema -- but the builder is
-- not, and cannot be. builder() returns what this call is about to create.
function EventBuilder.extend(eventClass: Event.EventConfig)
    local Builder = setmetatable({}, { __index = EventBuilder })
    Builder.__index = Builder

    function Builder.new()
        local state: BuilderState = {
            _eventClass = eventClass,
            _subType = nil,
            _eventId = nil,
            _fields = {},
        }
        return setmetatable(state, Builder)
    end

    return Builder
end

-- Validated against the event class this builder belongs to, so a subType
-- from another domain is caught here rather than at build().
-- GENERIC IN `self`, and every method below that returns self is the same.
--
-- The point is the fluent chain. `EventFactory.create(CombatEvent)` returns
-- the concrete CombatEvent Builder; if withSubType declared its return as
-- BuilderState, the very next `:withTargetId()` would be looked up on the
-- base type, which has no such method, and the chain would lose autocomplete
-- one call in -- the exact thing hand-written :withX() methods exist for.
-- Returning T passes the concrete type straight through.
--
-- The cast is the cost. T is opaque inside the function, so reading fields
-- off it needs a widening to BuilderState. It is safe because nothing reaches
-- these methods except through Builder.new(), which builds exactly that shape.
function EventBuilder.withSubType<T>(self: T, subType: string): T
    local state = (self :: any) :: BuilderState
    local eventClass = state._eventClass

    if eventClass.SubType[subType] == nil then
        error(string.format(
            "[%s] '%s' is not a subType of %s -- use %s.SubType.<NAME>",
            eventClass.eventType, tostring(subType),
            eventClass.eventType, eventClass.eventType), 2)
    end
    state._subType = subType
    return self
end

-- Only for rebuilding an event that already had an id. Normal authoring
-- leaves this alone and lets build() generate one.
function EventBuilder.withEventId<T>(self: T, eventId: string): T
    if type(eventId) ~= "string" or eventId == "" then
        error("[EventBuilder] eventId must be a non-empty string", 2)
    end
    local state = (self :: any) :: BuilderState
    state._eventId = eventId
    return self
end

-- What every :withX() delegates to. Validates the single field immediately,
-- against the schema, so the failure names the line that is wrong rather
-- than surfacing at build() with no clue which call put it there.
function EventBuilder._set<T>(self: T, field: string, value: any): T
    local state = (self :: any) :: BuilderState
    local eventClass = state._eventClass
    local spec: EventSchema.FieldSpec? = eventClass.schema[field]

    if spec == nil then
        error(string.format(
            "[%s] '%s' is not a declared parameter", eventClass.eventType, field), 3)
    end

    local ok, reason = EventSchema.checkField(
        eventClass.eventType, field, spec :: EventSchema.FieldSpec, value)
    if not ok then
        -- tostring(): checkField returns `string?`, and %s is typed as taking
        -- a string. It is never actually nil on the failure branch, but the
        -- checker cannot know that from the signature.
        error(string.format("[%s] %s", eventClass.eventType, tostring(reason)), 3)
    end

    state._fields[field] = value
    return self
end

-- NOT generic: this one returns an Event, not self, so there is no chain left
-- to preserve and `self` can be the concrete state type.
function EventBuilder.build(self: BuilderState): Event.Event
    local eventClass = self._eventClass
    local subType = self._subType

    if subType == nil then
        error(string.format(
            "[%s] withSubType() is required before build()", eventClass.eventType), 2)
    end

    -- Cross-field rules (required, requiredFor, defaults) run here, through
    -- the same engine the deserializer uses -- so a rule cannot apply to
    -- hand-built events and be skipped for anything off the wire. Both paths
    -- call Event.build directly; there is no per-type wrapper to keep in sync.
    local event, reason = Event.build(eventClass, subType, self._fields, self._eventId)
    if not event then
        error(string.format("[%s] %s", eventClass.eventType, tostring(reason)), 2)
    end
    return event
end

return EventBuilder
