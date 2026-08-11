-- src/shared/eventTape/event/types/SessionEvent.luau
--
--     EventFactory.create(SessionEvent)
--         :withSubType(SessionEvent.SubType.READY)
--         :build()
--
-- READY and TELEPORT carry nothing but their own subType, so an empty schema
-- is the correct schema -- not a gap.
--
-- SESSION is the one infrastructure eventType: SessionService owns a genuine
-- client-facing flow (ready, teleport request). DataService never does.

local Event = require(script.Parent.Parent.Event)
local EventBuilder = require(script.Parent.Parent.EventBuilder)
local EventSchema = require(script.Parent.Parent.EventSchema)
local EventType = require(script.Parent.Parent.EventType)

local SessionEvent = {}

SessionEvent.eventType = EventType.SESSION

SessionEvent.SubType = table.freeze({
    READY = "READY",
    TELEPORT = "TELEPORT",
})

local schema: EventSchema.Schema = {}

SessionEvent.schema = schema

local Builder = EventBuilder.extend(SessionEvent)
SessionEvent.Builder = Builder

-- Conformance check -- see the note in CombatEvent.
local _conforms: Event.EventModule = SessionEvent

return SessionEvent
