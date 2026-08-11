-- src/gameModes/dungeon/server/tests/EventTests.luau
--
-- Exercises Event, EventRegistry and the schema engine.
-- See Architecture-Reference.md Part 12.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local eventFolder = ReplicatedStorage:WaitForChild("eventTape"):WaitForChild("event")
local Event = require(eventFolder:WaitForChild("Event"))
local EventSchema = require(eventFolder:WaitForChild("EventSchema"))
local Validators = require(eventFolder:WaitForChild("Validators"))
local EventRegistry = require(eventFolder:WaitForChild("EventRegistry"))
local EventType = require(eventFolder:WaitForChild("EventType"))
local eventTypes = eventFolder:WaitForChild("types")
local CombatEvent = require(eventTypes:WaitForChild("CombatEvent"))
local AnimationEvent = require(eventTypes:WaitForChild("AnimationEvent"))
local SessionEvent = require(eventTypes:WaitForChild("SessionEvent"))
local InventoryEvent = require(eventTypes:WaitForChild("InventoryEvent"))

local TestRunner = require(script.Parent:WaitForChild("TestRunner"))

return function()
    local t = TestRunner.new("Event / Registry / Schema")

    -- EventRegistry --------------------------------------------------------

    t:case("the registry knows every declared event type", function(a)
        -- Every name EventType declares must have a class behind it, and the
        -- registry must find it. The negative cases stay bare strings on
        -- purpose -- there is no constant for a name that does not exist.
        for _, name in ipairs(EventType.all()) do
            a.isTrue(EventRegistry.isValid(name), name .. " has no event class")
        end
        a.isFalse(EventRegistry.isValid("NOPE"))
        a.isFalse(EventRegistry.isValid(nil))
        a.equal(EventRegistry.get(EventType.COMBAT), CombatEvent)
    end)

    t:case("subTypes belong to their own event class", function(a)
        a.isTrue(EventRegistry.hasSubType(EventType.COMBAT, "MELEE"))
        a.isFalse(EventRegistry.hasSubType(EventType.COMBAT, InventoryEvent.SubType.LOOT),
            "LOOT belongs to INVENTORY")
        a.isFalse(EventRegistry.hasSubType("NOPE", "MELEE"))
        a.isFalse(EventRegistry.hasSubType(EventType.COMBAT, nil))
    end)

    t:case("COMBAT covers everything nested under CombatService", function(a)
        -- One eventType per top-level DOMAIN, not per service. SkillService
        -- lives inside CombatService, so a skill activation is COMBAT/SKILL
        -- rather than its own routable type.
        -- The list stays LITERAL. Sourcing it from CombatEvent.SubType would
        -- make the assertion "CombatEvent.SubType contains what
        -- CombatEvent.SubType contains" -- always true, testing nothing. A
        -- written-out expectation is what makes a deleted subType fail here.
        for _, subType in ipairs({ "MELEE", "RANGED", "AOE", "SKILL", "ULTIMATE", "PARRY", "DODGE" }) do
            a.isTrue(EventRegistry.hasSubType(EventType.COMBAT, subType), "COMBAT is missing " .. subType)
        end
    end)

    t:case("no eventType exists for an authority service or a driver", function(a)
        -- A client never says "grant me gold" -- gold moves as a consequence
        -- of a domain action the server decided on. Authority services are
        -- leaves that execute, they do not authorise. AI produces Intentions
        -- by direct call, never over EventTape.
        for _, forbidden in ipairs({ "RESOURCE", "STATE", "STAT", "BUFF", "EQUIPMENT", "AI", "PET" }) do
            a.isFalse(EventRegistry.isValid(forbidden),
                forbidden .. " must not be a routable eventType")
        end
    end)

    t:case("HEAL, BUFF and DEBUFF are no longer COMBAT subtypes", function(a)
        -- They moved out when BuffService and StateService became peer
        -- domains (Part 10) -- nesting them under Combat broke the
        -- one-eventType-to-one-Service rule routing depends on.
        for _, subType in ipairs({ "HEAL", "BUFF", "DEBUFF" }) do
            a.isFalse(EventRegistry.hasSubType(EventType.COMBAT, subType))
        end
    end)

    t:case("subType tables are frozen", function(a)
        -- Second argument is the expected error SUBSTRING, not a message.
        -- This read "a frozen table should reject writes" and so asserted the
        -- error text contained that sentence, which of course it never does.
        a.throws(function() CombatEvent.SubType.INVENTED = "X" end,
            "readonly", "a frozen table must reject writes")
        a.isNil(CombatEvent.SubType.MELE, "a typo must read as nil, not as a string")
    end)

    -- The schema engine ----------------------------------------------------

    t:case("checkField validates one value against its spec", function(a)
        local ok = EventSchema.checkField("X", "n", { type = "number" }, 5)
        a.isTrue(ok)

        local bad, reason = EventSchema.checkField("X", "n", { type = "number" }, "five")
        a.isFalse(bad)
        a.isTrue(string.find(reason, "must be number", 1, true) ~= nil, reason)
    end)

    t:case("a union type accepts either member", function(a)
        local spec = { type = { "string", "number" } }
        a.isTrue(EventSchema.checkField("X", "id", spec, "E1"))
        a.isTrue(EventSchema.checkField("X", "id", spec, 42))
        a.isFalse(EventSchema.checkField("X", "id", spec, {}))
    end)

    t:case("a constraint runs on top of the type", function(a)
        local spec = { type = "number", constraint = function(v) return v > 0 end }
        a.isTrue(EventSchema.checkField("X", "n", spec, 1))

        local ok, reason = EventSchema.checkField("X", "n", spec, -1)
        a.isFalse(ok)
        a.isTrue(string.find(reason, "constraint", 1, true) ~= nil, reason)
    end)

    t:case("parse rejects unknown fields and lists the valid ones", function(a)
        -- This is what replaces autocomplete at runtime: a typo fails with
        -- the whole vocabulary in the message rather than being dropped.
        local schema = { alpha = { type = "string" }, beta = { type = "number" } }
        local fields, reason = EventSchema.parse("X", "SUB", schema, { alfa = "x" })

        a.isNil(fields)
        a.isTrue(string.find(reason, "unknown field 'alfa'", 1, true) ~= nil, reason)
        a.isTrue(string.find(reason, "alpha", 1, true) ~= nil,
            "the error must list the fields that were valid")
    end)

    t:case("parse applies defaults and honours required", function(a)
        local schema = {
            needed = { type = "string", required = true },
            optionalWithDefault = { type = "number", default = 7 },
            plainOptional = { type = "boolean" },
        }

        local fields = EventSchema.parse("X", "SUB", schema, { needed = "yes" })
        a.equal(fields.needed, "yes")
        a.equal(fields.optionalWithDefault, 7, "a declared default applies when absent")
        a.isNil(fields.plainOptional, "no default means the field stays absent")

        local missing, reason = EventSchema.parse("X", "SUB", schema, {})
        a.isNil(missing)
        a.isTrue(string.find(reason, "'needed' is required", 1, true) ~= nil, reason)
    end)

    t:case("requiredFor makes a field mandatory here and forbidden elsewhere", function(a)
        local schema = { skillId = { type = "string", requiredFor = { "SKILL" } } }

        a.notNil(EventSchema.parse("X", "SKILL", schema, { skillId = "CLEAVE" }))

        local missing = EventSchema.parse("X", "SKILL", schema, {})
        a.isNil(missing, "required for this subType")

        local forbidden = EventSchema.parse("X", "MELEE", schema, { skillId = "CLEAVE" })
        a.isNil(forbidden, "and rejected on every other subType")
    end)

    t:case("validateSchema catches a malformed spec", function(a)
        a.equal(#EventSchema.validateSchema("X", { good = { type = "string" } }), 0)
        a.isTrue(#EventSchema.validateSchema("X", { bad = { typ = "string" } }) >= 1,
            "a typo'd spec key must be caught")
        a.isTrue(#EventSchema.validateSchema("X", { bad = { type = "string", constraint = "no" } }) >= 1,
            "constraint must be a function")
    end)

    -- Validators -----------------------------------------------------------
    --
    -- EVERY VALIDATOR IS A FACTORY. There are no bare predicates -- see the
    -- uncalled-factory test at the end of this block for why the uniformity
    -- is what makes that guard possible at all.

    t:case("nonEmptyString rejects the empty string AND non-strings", function(a)
        local check = Validators.nonEmptyString()
        a.isTrue(check("x"))
        a.isFalse(check(""))
        a.isFalse(check(0), "wrong type is a failure, not a shrug")
    end)

    t:case("integer rejects fractions", function(a)
        local check = Validators.integer()
        a.isTrue(check(3))
        a.isTrue(check(-2))
        a.isFalse(check(1.5))
        a.isFalse(check("x"), "wrong type is a failure, not a shrug")
    end)

    t:case("range is inclusive on both ends", function(a)
        local inRange = Validators.range(1, 10)
        a.isTrue(inRange(1), "min is legal")
        a.isTrue(inRange(10), "max is legal")
        a.isTrue(inRange(5))
        a.isFalse(inRange(0))
        a.isFalse(inRange(11))
        a.isFalse(inRange("5"), "wrong type is a failure, not a shrug")
    end)

    t:case("positiveNumber excludes zero, which range cannot", function(a)
        -- range(0, n) would admit 0, and 0 is usually the exact value being
        -- excluded -- a speed of 0 stalls forever, a distance of 0 is not one.
        local positive = Validators.positiveNumber()
        a.isTrue(positive(0.1))
        a.isTrue(positive(1000))
        a.isFalse(positive(0), "zero is not positive")
        a.isFalse(positive(-1))
    end)

    t:case("every numeric validator refuses NaN and infinity", function(a)
        -- NaN fails EVERY comparison, so a naive bounds check lets it pass,
        -- and it survives a RemoteEvent. Infinity passes any one-sided bound.
        -- Both are refused centrally, so this holds for all three.
        for name, check in pairs({
            range = Validators.range(1, 10),
            integer = Validators.integer(),
            positiveNumber = Validators.positiveNumber(),
        }) do
            a.isFalse(check(0 / 0), name .. " must reject NaN")
            a.isFalse(check(math.huge), name .. " must reject +infinity")
            a.isFalse(check(-math.huge), name .. " must reject -infinity")
        end
    end)

    t:case("oneOf tests membership in a list written into the schema", function(a)
        -- The one membership test that stays inside the layer's boundary: the
        -- list is in the schema, so it still answers from the value alone. A
        -- catalog lookup (the deleted existsIn) would not.
        local rarity = Validators.oneOf({ "COMMON", "RARE" })
        a.isTrue(rarity("RARE"))
        a.isFalse(rarity("MYTHIC"))
    end)

    t:case("all stops at the first failure and reports WHICH one", function(a)
        -- The reason for threading a second return through a constraint: a
        -- composed one that only said "failed" would leave you guessing.
        local ran = 0
        local counted = function(value)
            ran += 1
            return true
        end
        local check = Validators.all(Validators.nonEmptyString(), counted)

        a.isTrue(check("ok"))
        a.equal(ran, 1, "the second predicate runs when the first passes")

        local passed, reason = check("")
        a.isFalse(passed)
        a.isTrue(string.find(reason, "empty", 1, true) ~= nil, reason)
        a.equal(ran, 1, "and does NOT run once the first has failed")
    end)

    t:case("a factory rejects malformed arguments at construction", function(a)
        -- Schemas are built when their module is required, so these fail at
        -- load rather than the first time a player sends that field.
        a.throws(function() Validators.range("1", 10) end, "two numbers")
        a.throws(function() Validators.range(10, 1) end, "min <= max")
        a.throws(function() Validators.oneOf({}) end, "non-empty array")
        a.throws(function() Validators.all() end, "at least one predicate")
        a.throws(function() Validators.all(Validators.nonEmptyString(), "x") end, "not a function")
    end)

    t:case("an UNCALLED validator fails boot instead of passing everything", function(a)
        -- The dangerous mistake: `constraint = Validators.range` is a function,
        -- so it survives the "must be a function" test AND satisfies the
        -- Constraint type -- then returns a closure at runtime, which is
        -- truthy, so every value passes silently. No type can catch it.
        local failures = EventSchema.validateSchema("X", {
            bad = { type = "number", constraint = Validators.range },
        })
        a.isTrue(#failures >= 1, "an uncalled factory must be caught")
        a.isTrue(string.find(table.concat(failures, " "), "range", 1, true) ~= nil,
            "the failure must name the validator you owe a call to")

        -- The guard scans the Validators module rather than a hand-kept list,
        -- so it covers a validator nobody remembered to register. nonEmptyString
        -- was never in the old FACTORIES table; it is caught anyway.
        a.isTrue(#EventSchema.validateSchema("X", {
            bad = { type = "string", constraint = Validators.nonEmptyString },
        }) >= 1, "every validator is covered, not just the ones on a list")

        a.equal(#EventSchema.validateSchema("X", {
            good = { type = "number", constraint = Validators.range(1, 10) },
        }), 0, "the called form is fine")
    end)

    t:case("a validator's reason reaches the schema error message", function(a)
        local schema = { slot = { type = "number", constraint = Validators.range(1, 30) } }

        local fields, reason = EventSchema.parse("X", "SUB", schema, { slot = 99 })
        a.isNil(fields)
        a.isTrue(string.find(reason, "between 1 and 30", 1, true) ~= nil, reason)
        a.isTrue(string.find(reason, "99", 1, true) ~= nil,
            "and the offending value is still reported")
    end)

    -- Event ----------------------------------------------------------------

    t:case("build produces a populated event", function(a)
        local event = Event.build(CombatEvent, "MELEE", { targetId = 5 })

        a.equal(event:getEventType(), EventType.COMBAT)
        a.equal(event:getSubType(), CombatEvent.SubType.MELEE)
        a.equal(event:get("targetId"), 5)
        a.equal(event:getClass(), CombatEvent, "an event knows the class it came from")
        a.isType(event:getTimeStamp(), "number")
    end)

    t:case("build returns a reason rather than raising", function(a)
        -- This is the deserialization path, where malformed input is
        -- expected traffic from a client rather than a programmer error.
        local event, reason = Event.build(CombatEvent, "NOPE", {})
        a.isNil(event)
        a.isTrue(string.find(reason, "not a subType of COMBAT", 1, true) ~= nil, reason)

        event = Event.build(CombatEvent, "MELEE", { skillId = "CLEAVE" })
        a.isNil(event, "a forbidden field must be rejected")

        event, reason = Event.build("not a class", "MELEE", {})
        a.isNil(event)
        a.isType(reason, "string")
    end)

    t:case("every event carries a unique id", function(a)
        -- Part 5 requires this and Part 15's reconciliation depends on it.
        local first = Event.build(CombatEvent, "MELEE", {})
        local second = Event.build(CombatEvent, "MELEE", {})

        a.isType(first:getEventId(), "string")
        a.notEqual(first:getEventId(), second:getEventId(), "ids must be unique")

        local fixed = Event.build(CombatEvent, "MELEE", {}, "fixed-id-123")
        a.equal(fixed:getEventId(), "fixed-id-123", "an explicit id is preserved")
    end)

    t:case("serialize produces plain data with every field", function(a)
        local event = Event.build(SessionEvent, "READY", {})
        local serialized = event:serialize()

        -- LITERALS ON PURPOSE, and the only place in this file that should
        -- have them. These assert the WIRE FORMAT. Written as
        -- EventType.SESSION, the test would keep passing if someone changed
        -- that constant's value -- silently breaking every client already
        -- built against the old string. The literal is the contract.
        a.plainData(serialized, "a serialized event must survive a RemoteEvent")
        a.equal(serialized.eventType, "SESSION")
        a.equal(serialized.subType, "READY")
        a.equal(serialized.eventId, event:getEventId(), "the id must cross the wire")
        a.isNil(serialized.timeStamp,
            "the construction time is local only -- it must NOT cross the wire")
    end)

    t:case("the construction timestamp is readable but not settable", function(a)
        -- No setter on purpose: the value only means anything on the machine
        -- that produced it, so nothing should be able to overwrite it with a
        -- number that came from somewhere else.
        local event = Event.build(CombatEvent, "MELEE", {})
        a.isType(event:getTimeStamp(), "number")
        a.isNil(event.setTimeStamp, "there must be no setter")
    end)

    t:case("get reads a validated parameter and nothing else", function(a)
        local event = Event.build(CombatEvent, "SKILL",
            { targetId = "E1", skillId = "CLEAVE" })

        a.equal(event:get("skillId"), "CLEAVE")
        a.isNil(event:get("nonsense"),
            "an undeclared field could never have got this far -- validation rejects the event")
    end)

    -- Per-type accessors ---------------------------------------------------

    t:case("event classes expose named accessors", function(a)
        local combat = Event.build(CombatEvent, "SKILL", { targetId = "E1", skillId = "CLEAVE" })
        a.equal(CombatEvent.getTargetId(combat), "E1")
        a.equal(CombatEvent.getSkillId(combat), "CLEAVE")
        a.isTrue(CombatEvent.isSkillActivation(combat))
        a.isFalse(CombatEvent.isSkillActivation(Event.build(CombatEvent, "MELEE", {})))

        local animation = Event.build(AnimationEvent, "ATTACK", { id = "animation1", range = 5 })
        a.equal(AnimationEvent.getId(animation), "animation1")
        a.equal(AnimationEvent.getRange(animation), 5)
        a.equal(AnimationEvent.getSpeed(animation), 1.0, "the declared default applies")
    end)

    t:case("an animation id is NOT checked against the catalog", function(a)
        -- This used to assert the opposite: `id` carried AnimationRegistry
        -- .isKnown as a constraint, so an undeclared id was rejected here.
        --
        -- That check is deliberately gone. It made the transport layer depend
        -- on the Content Layer to answer a question it could not act on --
        -- "this animation exists" is not "this player may play it" -- and the
        -- consumer has to resolve the id regardless. A constraint validates
        -- the VALUE, never the world. See Validators.luau.
        a.notNil(Event.build(AnimationEvent, "ATTACK", { id = "does_not_exist" }),
            "an unknown id is well-formed; whoever resolves it deals with the miss")
        a.notNil(Event.build(AnimationEvent, "ATTACK", { id = "animation1" }))

        -- What IS still rejected: anything that fails on the value alone.
        a.isNil(Event.build(AnimationEvent, "ATTACK", { id = "animation1", speed = 0 }),
            "a speed of zero stalls the animation forever")
        a.isNil(Event.build(AnimationEvent, "ATTACK", { id = "animation1", range = -1 }))
        a.isNil(Event.build(AnimationEvent, "ATTACK", { id = "animation1", speed = 0 / 0 }),
            "NaN survives a RemoteEvent, so it must be refused here")
    end)

    -- The declaration validator --------------------------------------------

    t:case("every shipped event class is well-formed", function(a)
        for eventType, eventClass in pairs(EventRegistry.classes()) do
            local failures = EventRegistry.checkEventModule(eventType, eventClass)
            a.equal(#failures, 0, table.concat(failures, "; "))
        end
        a.noThrow(function() EventRegistry.validate() end)
    end)

    t:case("the validator catches a parameter with no builder method", function(a)
        -- Proving the validator actually validates. This is what lets the
        -- :withX() methods stay hand-written -- the only way they can be
        -- autocompleted -- without drifting from the schema.
        local fake = {
            eventType = "FAKE",
            SubType = { A = "A" },
            schema = { orphaned = { type = "string" } },
            Builder = {},
        }

        local failures = EventRegistry.checkEventModule("FAKE", fake)
        a.isTrue(#failures >= 1, "a schema field with no method must be caught")
        a.isTrue(string.find(table.concat(failures, " "), "withOrphaned", 1, true) ~= nil,
            "the failure must name the method you owe it")
    end)

    t:case("the validator catches a builder method with no parameter", function(a)
        -- The other direction: a method with nothing behind it sets a field
        -- the schema then rejects, which is a miserable failure to debug.
        local fake = {
            eventType = "FAKE",
            SubType = { A = "A" },
            schema = {},
            Builder = { withGhost = function() end },
        }

        local failures = EventRegistry.checkEventModule("FAKE", fake)
        a.isTrue(#failures >= 1, "an orphaned builder method must be caught")
        a.isTrue(string.find(table.concat(failures, " "), "withGhost", 1, true) ~= nil,
            table.concat(failures, "; "))
    end)

    t:case("the validator ignores the base builder methods", function(a)
        local fake = {
            eventType = "FAKE",
            SubType = { A = "A" },
            schema = {},
            Builder = {},
        }
        a.equal(#EventRegistry.checkEventModule("FAKE", fake), 0,
            "withSubType and withEventId come from the base and are not parameters")
    end)

    t:case("the validator catches a class missing its parts", function(a)
        a.isTrue(#EventRegistry.checkEventModule("FAKE", { eventType = "FAKE", SubType = { A = "A" } }) >= 1,
            "a class with no schema must be caught")
        a.isTrue(#EventRegistry.checkEventModule("FAKE", { eventType = "OTHER", SubType = { A = "A" }, schema = {} }) >= 1,
            "a class whose eventType disagrees with its registry key must be caught")
        a.isTrue(#EventRegistry.checkEventModule("FAKE", { eventType = "FAKE", SubType = {}, schema = {} }) >= 1,
            "a class with no subTypes must be caught")
    end)

    return t:run()
end
