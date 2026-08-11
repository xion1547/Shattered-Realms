-- src/gameModes/dungeon/server/tests/EventTapeTests.luau
--
-- Exercises the fluent builder, EventFactory and EventTape -- the authoring
-- side, and the round trip across the wire.
-- See Architecture-Reference.md Part 12.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local eventFolder = ReplicatedStorage:WaitForChild("eventTape"):WaitForChild("event")
local EventTape = require(eventFolder:WaitForChild("EventTape"))
local EventDeserializer = require(eventFolder:WaitForChild("EventDeserializer"))
local EventFactory = require(eventFolder:WaitForChild("EventFactory"))
local EventBuilder = require(eventFolder:WaitForChild("EventBuilder"))
local EventType = require(eventFolder:WaitForChild("EventType"))
local eventTypes = eventFolder:WaitForChild("types")
local CombatEvent = require(eventTypes:WaitForChild("CombatEvent"))
local AnimationEvent = require(eventTypes:WaitForChild("AnimationEvent"))
local InventoryEvent = require(eventTypes:WaitForChild("InventoryEvent"))
local SessionEvent = require(eventTypes:WaitForChild("SessionEvent"))

local TestRunner = require(script.Parent:WaitForChild("TestRunner"))

local function melee(targetId)
    return EventFactory.create(CombatEvent)
        :withSubType(CombatEvent.SubType.MELEE)
        :withTargetId(targetId)
        :build()
end

return function()
    local t = TestRunner.new("EventTape / Builder")

    -- The fluent builder ---------------------------------------------------

    t:case("create returns a builder that chains into an event", function(a)
        local event = EventFactory.create(CombatEvent)
            :withSubType(CombatEvent.SubType.SKILL)
            :withTargetId("ENEMY_9")
            :withSkillId("CLEAVE")
            :build()

        a.equal(event:getEventType(), EventType.COMBAT)
        a.equal(event:getSubType(), CombatEvent.SubType.SKILL)
        a.equal(CombatEvent.getSkillId(event), "CLEAVE")
        a.equal(CombatEvent.getTargetId(event), "ENEMY_9")
    end)

    t:case("create and Class.Builder.new are the same thing", function(a)
        -- `create` reads better and keeps one entry point; `Builder.new()` is
        -- always statically resolvable. They must not diverge.
        --
        -- There used to be a `builder()` wrapper on every event module whose
        -- whole body was `return Builder.new()`. It is gone -- it bought
        -- nothing, and cost a Builder/builder pair on one table differing only
        -- by case.
        local viaFactory = EventFactory.create(CombatEvent)
        local viaClass = CombatEvent.Builder.new()

        a.equal(getmetatable(viaFactory), getmetatable(viaClass))
        a.equal(viaClass:withSubType(CombatEvent.SubType.MELEE):build():getSubType(), "MELEE")
    end)

    t:case("create rejects anything that is not an event class", function(a)
        a.throws(function() EventFactory.create("CombatEvent") end, "expects an event class")
        a.throws(function() EventFactory.create({}) end, "expects an event class")
    end)

    t:case("every with- method returns the builder so calls chain", function(a)
        local builder = EventFactory.create(CombatEvent)
        a.equal(builder:withSubType(CombatEvent.SubType.MELEE), builder)
        a.equal(builder:withTargetId("E1"), builder)
        a.equal(builder:withEventId("fixed-id"), builder)
        a.equal(builder:build():getEventId(), "fixed-id")
    end)

    t:case("a with- method validates its own argument at the call site", function(a)
        -- The failure names the line that is wrong, rather than surfacing at
        -- build() with no clue which call put it there.
        local builder = EventFactory.create(CombatEvent)
        a.throws(function() builder:withTargetId({}) end, "must be string or number")
        a.throws(function() builder:withSkillId(42) end, "must be string")

        local animation = EventFactory.create(AnimationEvent)
        a.throws(function() animation:withSpeed("fast") end, "must be number")
        a.throws(function() animation:withLooped("yes") end, "must be boolean")

        -- A CONSTRAINT fires here too, not just the type. `id` used to carry
        -- a catalog lookup and this line asserted an unknown id threw; that
        -- check is gone on purpose (Validators.luau states why). A numeric
        -- constraint is the honest replacement -- it judges the value alone.
        a.throws(function() animation:withSpeed(0) end, "greater than zero")
    end)

    t:case("withSubType is validated against this event class", function(a)
        a.throws(function()
            EventFactory.create(CombatEvent):withSubType("NOPE")
        end, "not a subType of COMBAT")

        -- A subType belonging to a different domain must not slip through.
        a.throws(function()
            EventFactory.create(CombatEvent):withSubType(InventoryEvent.SubType.LOOT)
        end, "not a subType of COMBAT")
    end)

    t:case("build requires a subType", function(a)
        a.throws(function() EventFactory.create(CombatEvent):build() end,
            "withSubType() is required")
    end)

    t:case("cross-field rules run at build, not at the with- call", function(a)
        -- They cannot be judged until every field is in, and they run through
        -- the same engine the deserializer uses -- so a rule cannot apply to
        -- hand-built events and be skipped for anything off the wire.
        a.throws(function()
            EventFactory.create(CombatEvent)
                :withSubType(CombatEvent.SubType.SKILL)
                :withTargetId("E1")
                :build()
        end, "'skillId' is required")

        a.throws(function()
            EventFactory.create(CombatEvent)
                :withSubType(CombatEvent.SubType.MELEE)
                :withSkillId("CLEAVE")
                :build()
        end, "only valid for subTypes")
    end)

    t:case("declared defaults are applied at build", function(a)
        local event = EventFactory.create(AnimationEvent)
            :withSubType(AnimationEvent.SubType.EMOTE)
            :withId("animation1")
            :build()

        a.equal(AnimationEvent.getSpeed(event), 1.0, "speed has a declared default")
        a.isNil(AnimationEvent.getRange(event), "an optional field with no default stays absent")
    end)

    t:case("an event with no declared parameters builds from subType alone", function(a)
        local event = EventFactory.create(SessionEvent)
            :withSubType(SessionEvent.SubType.READY)
            :build()

        a.equal(event:getEventType(), EventType.SESSION)
        a.isNil(EventFactory.create(InventoryEvent).withAnything,
            "a class with no parameters exposes no with- methods")
    end)

    t:case("methodNameFor follows the naming convention the validator checks", function(a)
        a.equal(EventBuilder.methodNameFor("id"), "withId")
        a.equal(EventBuilder.methodNameFor("targetId"), "withTargetId")
    end)

    -- EventTape ------------------------------------------------------------

    t:case("a tape collects events in order", function(a)
        local tape = EventTape.new()
        a.isTrue(tape:isEmpty())

        tape:addEvent(melee("E1"))
        tape:addEvent(melee("E2"))

        a.equal(tape:count(), 2)
        a.equal(CombatEvent.getTargetId(tape:getEvents()[1]), "E1",
            "insertion order is the ordering guarantee")
        a.equal(CombatEvent.getTargetId(tape:getEvents()[2]), "E2")
    end)

    t:case("serialize produces plain data all the way down", function(a)
        -- REGRESSION: serialize used to return the live list of Event
        -- OBJECTS. Metatables do not survive a RemoteEvent, so the receiver
        -- got plain tables while the deserializer expected method calls.
        local tape = EventTape.new()
        tape:addEvent(melee(3))

        local payload = tape:serialize()
        -- LITERAL ON PURPOSE: this asserts the WIRE FORMAT, so it must not be
        -- written as EventType.COMBAT. See the same note in EventTests.
        a.plainData(payload, "the whole payload must be plain data")
        a.equal(#payload.events, 1)
        a.equal(payload.events[1].eventType, "COMBAT")
        a.equal(payload.events[1].data.targetId, 3)
    end)

    t:case("unpackSerialized returns the raw list and rejects junk", function(a)
        local tape = EventTape.new()
        tape:addEvent(melee("E1"))

        local events, reason = EventTape.unpackSerialized(tape:serialize())
        a.notNil(events, reason)
        a.equal(#events, 1)

        a.isNil(EventTape.unpackSerialized("not a table"))
        a.isNil(EventTape.unpackSerialized({ notEvents = true }))
    end)

    t:case("clear empties the tape without breaking it", function(a)
        local tape = EventTape.new()
        tape:addEvent(melee("E1"))
        tape:clear()

        a.isTrue(tape:isEmpty())
        a.noThrow(function() tape:addEvent(melee("E2")) end)
        a.equal(tape:count(), 1)
    end)

    -- Deserialization ------------------------------------------------------

    t:case("a full round trip preserves everything", function(a)
        local original = EventFactory.create(CombatEvent)
            :withSubType(CombatEvent.SubType.ULTIMATE)
            :withTargetId(77)
            :withSkillId("DOMAIN")
            :build()

        local rebuilt, reason = EventDeserializer.deserialize(original:serialize())
        a.notNil(rebuilt, reason)
        a.equal(rebuilt:getEventType(), EventType.COMBAT)
        a.equal(CombatEvent.getSkillId(rebuilt), "DOMAIN")
        a.equal(CombatEvent.getTargetId(rebuilt), 77)
        a.equal(rebuilt:getEventId(), original:getEventId(), "the id must survive")
        a.equal(rebuilt:getClass(), CombatEvent, "it rebuilds as the right class")
    end)

    t:case("the construction timestamp does not cross the wire", function(a)
        -- os.clock() has an arbitrary per-process origin, so the sender's
        -- value is meaningless to the receiver -- and a client-reported time
        -- would be untrustworthy anyway (Part 13). EventRouter stamps its own
        -- receivedAt; nothing reads a timestamp off a payload.
        local original = melee("E1")

        a.isNil(original:serialize().timeStamp, "timeStamp must not be serialized")
        a.isType(original:getTimeStamp(), "number", "but it is still readable locally")

        local rebuilt = EventDeserializer.deserialize(original:serialize())
        a.isType(rebuilt:getTimeStamp(), "number",
            "the rebuilt event stamps its own construction time")
    end)

    t:case("an ANIMATION event round-trips through its own class", function(a)
        local original = EventFactory.create(AnimationEvent)
            :withSubType(AnimationEvent.SubType.ATTACK)
            :withId("animation1")
            :withSpeed(2)
            :build()

        local rebuilt, reason = EventDeserializer.deserialize(original:serialize())
        a.notNil(rebuilt, reason)
        a.equal(rebuilt:getClass(), AnimationEvent)
        a.equal(AnimationEvent.getId(rebuilt), "animation1")
        a.equal(AnimationEvent.getSpeed(rebuilt), 2)
    end)

    t:case("deserialization revalidates against the same schema", function(a)
        -- One set of rules, both directions. A payload the builder would
        -- reject is rejected off the wire too.
        local event = EventDeserializer.deserialize({
            eventType = EventType.COMBAT, subType = CombatEvent.SubType.MELEE,
            data = { skillId = "CLEAVE" },
        })
        a.isNil(event, "a forbidden field must be rejected on the inbound path")

        event = EventDeserializer.deserialize({
            eventType = EventType.COMBAT, subType = CombatEvent.SubType.MELEE,
            data = { targetID = "E1" },
        })
        a.isNil(event, "an unknown field must be rejected on the inbound path")

        -- A CONSTRAINT is enforced off the wire too, same engine. This used to
        -- send `id = "does_not_exist"` and expect a catalog lookup to reject
        -- it; that check is gone deliberately, so the case now uses a
        -- constraint that judges the value alone.
        event = EventDeserializer.deserialize({
            eventType = EventType.ANIMATION, subType = AnimationEvent.SubType.ATTACK,
            data = { id = "animation1", speed = -3 },
        })
        a.isNil(event, "a failing constraint must be rejected on the inbound path")

        -- And the id itself is NOT checked against the catalog, on purpose.
        a.notNil(EventDeserializer.deserialize({
            eventType = EventType.ANIMATION, subType = AnimationEvent.SubType.ATTACK,
            data = { id = "does_not_exist" },
        }), "an unknown id is well-formed -- existence is not this layer's question")
    end)

    t:case("deserialize returns a reason instead of throwing", function(a)
        -- Everything here came from a client, so malformed input is expected
        -- traffic rather than a programmer error.
        local event, reason = EventDeserializer.deserialize("not a table")
        a.isNil(event)
        a.isType(reason, "string")

        -- "NOPE" stays a literal: the whole point is that it is a name no
        -- constant exists for.
        a.isNil(EventDeserializer.deserialize({ subType = CombatEvent.SubType.MELEE }), "no eventType")
        a.isNil(EventDeserializer.deserialize({
            eventType = "NOPE", subType = CombatEvent.SubType.MELEE, data = {} }), "unknown type")
        a.isNil(EventDeserializer.deserialize({
            eventType = EventType.COMBAT, subType = InventoryEvent.SubType.LOOT, data = {} }),
            "wrong domain")
    end)

    return t:run()
end
