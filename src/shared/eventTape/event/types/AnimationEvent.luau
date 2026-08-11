--!strict

-- src/shared/eventTape/event/types/AnimationEvent.luau
--
--     EventFactory.create(AnimationEvent)
--         :withSubType(AnimationEvent.SubType.ATTACK)
--         :withId("animation1")
--         :withSpeed(1.25)
--         :build()
--
-- EVERYTHING ABOUT THIS EVENT IS IN THIS ONE FILE: its subTypes, its
-- parameters, the builder methods that set them, and the accessors that read
-- them back. One file per event type -- add a type, add a file, touch
-- nothing else.
--
-- The schema below is the single source of truth for the parameters. The
-- :withX() methods are hand-written so Studio can autocomplete them, and
-- EventRegistry.validate() asserts the two agree -- a schema field with no
-- method, or a method with no field, fails boot and names the mismatch.
--
-- PROVISIONAL, and OUTBOUND ONLY. Animation is a client rendering concern:
-- the server sends what happened and the client picks the animation from its
-- own manifest. There is no AnimationService and there should not be one, so
-- ANIMATION is deliberately absent from EventRoutingRegistry -- an inbound
-- one is correctly rejected as UNROUTABLE.

local Event = require(script.Parent.Parent.Event)
local EventBuilder = require(script.Parent.Parent.EventBuilder)
local EventSchema = require(script.Parent.Parent.EventSchema)
local EventType = require(script.Parent.Parent.EventType)
local Validators = require(script.Parent.Parent.Validators)

local AnimationEvent = {}

AnimationEvent.eventType = EventType.ANIMATION

AnimationEvent.SubType = table.freeze({
    ATTACK = "ATTACK",
    ULTIMATE = "ULTIMATE",
    EMOTE = "EMOTE",
    BUFF = "BUFF",
})

-- The parameters.
--
-- `id` DELIBERATELY HAS NO CONSTRAINT. It used to carry
-- AnimationRegistry.isKnown, which made this layer ask the Content Layer
-- whether an animation exists -- a question EventTape has no business asking
-- and could not act on anyway. Whoever consumes the event resolves the id and
-- deals with a miss. See the boundary note in Validators.luau.
local schema: EventSchema.Schema = {
    id = { type = "string", required = true },

    -- `type = "number"` alone admits 0, negatives, NaN and infinity, none of
    -- which are a distance or a playback rate. A speed of 0 stalls the
    -- animation forever; a negative one has no meaning at all.
    range = { type = "number", constraint = Validators.positiveNumber() },
    speed = { type = "number", default = 1.0, constraint = Validators.positiveNumber() },
    looped = { type = "boolean" },
    status = { type = "string" },
}

AnimationEvent.schema = schema

-- Builder ---------------------------------------------------------------
-- One method per schema field. The argument annotations are what make the
-- editor show you the expected type as you type.

local Builder = EventBuilder.extend(AnimationEvent)
AnimationEvent.Builder = Builder

function Builder:withId(id: string)
    return self:_set("id", id)
end

function Builder:withRange(range: number)
    return self:_set("range", range)
end

function Builder:withSpeed(speed: number)
    return self:_set("speed", speed)
end

function Builder:withLooped(looped: boolean)
    return self:_set("looped", looped)
end

function Builder:withStatus(status: string)
    return self:_set("status", status)
end

-- Accessors -------------------------------------------------------------

function AnimationEvent.getId(event)
    return event:get("id")
end

function AnimationEvent.getSpeed(event)
    return event:get("speed")
end

function AnimationEvent.getRange(event)
    return event:get("range")
end

-- Conformance check -- see the note in CombatEvent.
local _conforms: Event.EventModule = AnimationEvent

return AnimationEvent
