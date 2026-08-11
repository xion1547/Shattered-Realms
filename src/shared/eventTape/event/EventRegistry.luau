-- src/shared/eventTape/event/EventRegistry.luau
--
-- eventType -> its event class. The one place to look to see every kind of
-- event in the game.
--
-- SUBTYPES ARE NOT DECLARED HERE. They used to be -- in the original
-- EventType.luau, alongside the top-level names -- which meant every subType
-- list existed there and again as each class's own SubType table, two places
-- for the same vocabulary to disagree. Each class owns its subTypes now; this
-- just collects the classes.
--
-- The top-level NAMES do have a home, and it is EventType.luau -- a much
-- narrower file than the one that was deleted, holding the four domain names
-- and nothing else. The keys below are those constants, not fresh literals.
--
-- WHICH SERVICES GET AN eventType -- the rule, since it keeps coming up:
--
-- An eventType is a ROUTING KEY for traffic arriving over EventTape. It
-- exists only where a client Request or a server Intention has to reach a
-- top-level domain and be authorised there. NOT one per service.
--
--   DOMAIN services   yes, IF a client originates the action. COMBAT,
--                     INVENTORY. Not Dungeon/Drop/Level/Zone -- nothing a
--                     client sends starts there.
--   INFRASTRUCTURE    only where it owns a client-facing flow. SESSION does.
--   AUTHORITY         NEVER. A client does not say "grant me gold"; gold
--                     moves as a consequence of a domain action. Authority
--                     services are leaves -- they execute, not authorise.
--   DRIVERS           NEVER. Intentions are direct Service calls (Part 5).
--
-- ONE eventType PER TOP-LEVEL DOMAIN, and everything nested underneath
-- shares it: a skill activation is COMBAT/SKILL, not its own type.
--
-- This module also owns the BOOT CHECK over its own contents (validate(),
-- below) -- the same shape as SignalService.validate(): a registry is the
-- thing that knows what it is supposed to contain, so it is the thing that
-- checks it.

local Event = require(script.Parent.Event)
local EventSchema = require(script.Parent.EventSchema)
local EventBuilder = require(script.Parent.EventBuilder)
local EventType = require(script.Parent.EventType)

local types = script.Parent:WaitForChild("types")

local EventRegistry = {}

local CLASSES: { [string]: Event.EventModule } = {
    [EventType.COMBAT] = require(types:WaitForChild("CombatEvent")),
    [EventType.INVENTORY] = require(types:WaitForChild("InventoryEvent")),
    [EventType.SESSION] = require(types:WaitForChild("SessionEvent")),
    [EventType.ANIMATION] = require(types:WaitForChild("AnimationEvent")),
}

function EventRegistry.get(eventType: any): Event.EventModule?
    return CLASSES[eventType]
end

function EventRegistry.isValid(eventType: any): boolean
    return type(eventType) == "string" and CLASSES[eventType] ~= nil
end

function EventRegistry.hasSubType(eventType: any, subType: any): boolean
    local class = CLASSES[eventType]
    if not class or type(subType) ~= "string" then
        return false
    end
    return class.SubType[subType] ~= nil
end

function EventRegistry.all(): { string }
    local names = {}
    for eventType in pairs(CLASSES) do
        table.insert(names, eventType)
    end
    table.sort(names)
    return names
end

function EventRegistry.classes(): { [string]: Event.EventModule }
    return CLASSES
end

-- Validation ------------------------------------------------------------
--
-- Every declared parameter must have a :withX(), and every :withX() must
-- correspond to a declared parameter.
--
-- This is what lets the builder methods stay hand-written -- which is the
-- only way they can be autocompleted -- without the schema and the methods
-- drifting apart. Add a schema field and forget its method and the server
-- refuses to boot, naming the method you owe it.
--
-- KNOWN GAP, stated rather than implied: this checks that a method with the
-- right NAME exists, never what that method actually sets. A copy-pasted
-- `withSkillId` whose body reads `_set("targetId", ...)` passes cleanly and
-- writes the wrong field at runtime. Closing that means generating the setter
-- bodies from the schema, which is a separate change.
local function collectBuilderCoverage(eventType: string, eventClass: any, failures: { string })
    local builder = eventClass.Builder
    if type(builder) ~= "table" then
        table.insert(failures, string.format("%s: no Builder", eventType))
        return
    end

    local expected = {}

    for field in pairs(eventClass.schema) do
        local methodName = EventBuilder.methodNameFor(field)
        expected[methodName] = field
        if type(rawget(builder, methodName)) ~= "function" then
            table.insert(failures, string.format(
                "%s: parameter '%s' has no builder method -- add %s:%s(value)",
                eventType, field, eventType, methodName))
        end
    end

    -- The other direction: a method with no parameter behind it sets a field
    -- the schema will reject, which is a confusing failure to debug.
    for key, value in pairs(builder) do
        if type(value) == "function" and key:sub(1, 4) == "with" then
            if key ~= "withSubType" and key ~= "withEventId" and expected[key] == nil then
                table.insert(failures, string.format(
                    "%s: builder method '%s' has no matching schema parameter",
                    eventType, key))
            end
        end
    end
end

-- Validates one event class. Returns a list of failures, empty if it is
-- well-formed. Public so a test can prove the validator actually catches
-- drift, rather than only asserting that the shipped classes happen to pass.
function EventRegistry.checkEventModule(eventType: string, eventClass: any): { string }
    local failures: { string } = {}

    if type(eventClass) ~= "table" then
        return { string.format("%s: not a table", eventType) }
    end
    if eventClass.eventType ~= eventType then
        table.insert(failures, string.format(
            "%s: class declares eventType '%s'", eventType, tostring(eventClass.eventType)))
    end
    if type(eventClass.SubType) ~= "table" or next(eventClass.SubType) == nil then
        table.insert(failures, string.format("%s: declares no subTypes", eventType))
    end
    if type(eventClass.schema) ~= "table" then
        table.insert(failures, string.format("%s: missing schema", eventType))
        return failures
    end

    for _, failure in ipairs(EventSchema.validateSchema(eventType, eventClass.schema)) do
        table.insert(failures, failure)
    end
    collectBuilderCoverage(eventType, eventClass, failures)

    return failures
end

-- BOOT CHECK. Call once per place, from boot, beside the other validators.
--
-- Everything it checks is static -- whether CombatEvent's schema has a
-- matching :withSkillId() cannot change while the game runs -- so nothing at
-- runtime gates on this having been called. It is a boot gate, not a
-- precondition: forgetting it costs you an early failure, never a broken
-- deserialize.
--
-- Fails ONCE, listing everything wrong, rather than a warn() per problem
-- scattered through engine output (Part 16).
function EventRegistry.validate()
    local failures: { string } = {}

    for eventType, eventClass in pairs(CLASSES) do
        for _, failure in ipairs(EventRegistry.checkEventModule(eventType, eventClass)) do
            table.insert(failures, failure)
        end
    end

    -- The drift the enum makes possible: a name declared in EventType with no
    -- class behind it. Nothing else would catch it -- CLASSES is keyed BY the
    -- enum, so iterating CLASSES can never notice a name that has no entry.
    -- The reverse (a class with no enum name) cannot happen; there would be no
    -- constant to key it with.
    for _, name in ipairs(EventType.all()) do
        if CLASSES[name] == nil then
            table.insert(failures, string.format(
                "%s: declared in EventType but has no event class", name))
        end
    end

    if #failures > 0 then
        table.sort(failures)
        error(string.format(
            "[EventRegistry] %d event declaration problem(s):\n  - %s",
            #failures, table.concat(failures, "\n  - ")), 0)
    end
end

return EventRegistry
