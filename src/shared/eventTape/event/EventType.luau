-- src/shared/eventTape/event/EventType.luau
--
-- The closed vocabulary of TOP-LEVEL event domains. Nothing else.
--
-- A NOTE ON THE FILE THAT USED TO HAVE THIS NAME: an earlier EventType.luau
-- declared the eventTypes AND every subType under them, which meant the
-- subType list existed here and again in each class's own SubType table --
-- two places for the same vocabulary to disagree. That file was deleted for
-- good reason and this is NOT it coming back.
--
-- This one holds ONLY the top-level names. SubTypes stay where they belong,
-- in the event class that owns them (CombatEvent.SubType), and nothing here
-- knows they exist. The duplication that killed the old file is structurally
-- impossible in this one, because there is nothing to duplicate.
--
-- WHY IT EXISTS AT ALL: "COMBAT" was previously a bare literal in three
-- separate files -- the class's own `eventType`, the EventRegistry key, and
-- the EventRoutingRegistry key. Boot checks caught drift between them, so it
-- failed loudly rather than silently, but a call site still had no constant to
-- reference and had to type the string. Closed vocabularies are never compared
-- as bare strings (Part 2); this is the door.
--
--     EventType.COMBAT           -- reference it
--     EventType.isValid(x)       -- test it
--
-- ONE eventType PER TOP-LEVEL DOMAIN. See EventRegistry for the rule on which
-- services earn one (domain services where a client originates the action;
-- never authority services, never drivers).

-- A PLAIN TABLE LITERAL, deliberately. An earlier version built this with
-- table.clone() to keep the names separate from the functions, and the Luau
-- analyser could not see through it -- it inferred `{}` and every EventType.X
-- in the codebase became "Key 'COMBAT' not found in table '{ }'". The
-- constants have to be written here, literally, or the editor cannot resolve
-- them. Same shape as MessageKind and RejectReason.
local EventType = {
    COMBAT = "COMBAT",
    INVENTORY = "INVENTORY",
    SESSION = "SESSION",
    ANIMATION = "ANIMATION",
}

-- A snapshot of the names ALONE, taken before the functions below are added.
--
-- isValid must not answer questions about this module's own methods:
-- `EventType.isValid("isValid")` would otherwise return true, because a
-- lookup on EventType finds a function there and does not care that it is not
-- a domain. Nothing indexes NAMES with a literal key, so the analyser having
-- no idea what is in it costs nothing.
local NAMES = table.clone(EventType)

function EventType.isValid(eventType: any): boolean
    return NAMES[eventType] ~= nil
end

-- Every declared name, sorted. For error messages that want to list the
-- vocabulary rather than make the reader go find it.
function EventType.all(): { string }
    local names = {}
    for name in pairs(NAMES) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

return table.freeze(EventType)
