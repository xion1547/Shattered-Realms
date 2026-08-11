-- src/shared/eventTape/event/types/CombatEvent.luau
--
--     EventFactory.create(CombatEvent)
--         :withSubType(CombatEvent.SubType.SKILL)
--         :withTargetId("ENEMY_1")
--         :withSkillId("CLEAVE")
--         :build()
--
-- ONE eventType PER TOP-LEVEL DOMAIN. SkillService lives inside
-- CombatService, so a skill activation is COMBAT/SKILL -- not its own
-- routable type. That is what keeps EventRoutingRegistry one row per domain.
--
-- INTENT ONLY. What the player tried to do and what they were pointing at.
-- No damage number, no target HP, no client timestamp -- the server resolves
-- all of that, and the latency rewind uses server-measured ping (Part 13).

local Event = require(script.Parent.Parent.Event)
local EventBuilder = require(script.Parent.Parent.EventBuilder)
local EventSchema = require(script.Parent.Parent.EventSchema)
local EventType = require(script.Parent.Parent.EventType)

local CombatEvent = {}

CombatEvent.eventType = EventType.COMBAT

CombatEvent.SubType = table.freeze({
    -- Basic attacks, resolved directly by CombatService.
    MELEE = "MELEE",
    RANGED = "RANGED",
    AOE = "AOE",
    -- SkillService, which lives INSIDE CombatService.
    SKILL = "SKILL",
    ULTIMATE = "ULTIMATE",
    -- Defensive intent. PARRY requests a parry window; whether it negates
    -- anything is decided later, in the INTERCEPT phase (Part 11.3).
    PARRY = "PARRY",
    DODGE = "DODGE",
})

-- Annotated, so the analyser polices the shape as you type rather than the
-- server telling you at boot.
local schema: EventSchema.Schema = {
    -- Entity ids are strings for spawned entities ("ENEMY_1") and numbers
    -- for players (UserId), so both are legal.
    targetId = { type = { "string", "number" } },

    -- Required by SKILL and ULTIMATE; REJECTED on everything else. One
    -- declaration expresses both halves -- a client sending a skillId on a
    -- basic swing is building something it should not know how to build.
    --
    -- The subTypes come from the frozen table above, never as bare strings:
    -- misspell one here and the field silently stops being required for a
    -- subType that no longer matches anything.
    skillId = {
        type = "string",
        requiredFor = { CombatEvent.SubType.SKILL, CombatEvent.SubType.ULTIMATE },
    },
}

CombatEvent.schema = schema

-- Builder ---------------------------------------------------------------

local Builder = EventBuilder.extend(CombatEvent)
CombatEvent.Builder = Builder

function Builder:withTargetId(targetId: string | number)
    return self:_set("targetId", targetId)
end

function Builder:withSkillId(skillId: string)
    return self:_set("skillId", skillId)
end

-- Accessors -------------------------------------------------------------

function CombatEvent.getTargetId(event)
    return event:get("targetId")
end

function CombatEvent.getSkillId(event)
    return event:get("skillId")
end

-- Which subTypes SkillService owns. Combat's own business -- routing within
-- a domain never leaves the domain (Part 12).
function CombatEvent.isSkillActivation(event)
    local subType = event:getSubType()
    return subType == CombatEvent.SubType.SKILL
        or subType == CombatEvent.SubType.ULTIMATE
end

-- Conformance check. Fails HERE if this module stops being a valid event
-- module, instead of surfacing in EventRegistry -- the wrong file to be
-- reading when the mistake is in this one.
--
-- It cannot be `return CombatEvent :: Event.EventModule`: that would narrow
-- the module to EventModule and erase the accessors below, which EventModule
-- does not declare and every consumer needs.
local _conforms: Event.EventModule = CombatEvent

return CombatEvent
