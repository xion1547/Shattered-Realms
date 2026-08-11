-- src/gameModes/dungeon/server/services/domain/CombatService/init.luau
--
-- DOMAIN SERVICE. Hit validation, the DamageResolution pipeline, kill
-- detection, loot trigger. Owns the SkillService sub-domain.
-- See Architecture-Reference.md Parts 10 and 11.
--
-- SkillService is a CHILD of this module, not a sibling in domain/. That is
-- structural, not cosmetic: a skill is by definition a combat concept, and
-- combat resolution needs to know what a skill does. Splitting them into
-- independent top-level Services would just recreate a circular dependency
-- between them. Nesting makes the direction obvious at a glance -- Combat
-- calls into Skill, never the reverse -- and it means the PlaceManifest
-- declares one public-facing authority for the whole domain.
--
-- It is also why COMBAT is one eventType covering everything underneath it:
-- a skill activation is COMBAT/SKILL, not its own top-level type.
--
-- The four phases are hard boundaries and the reason this file will not
-- become an 8,000-line god object:
--
--   VALIDATE  here. Legality only. On reject: return, no pipeline, no Fact.
--   RESOLVE   DamageResolution. Pure. Steps mutate a context and nothing else.
--   COMMIT    here. Apply numbers, dispatch content-declared effects.
--   ANNOUNCE  here. Outbound diff, then Facts.
--
-- A new damage modifier is a new STEP file, never a new branch in this
-- service. If you find yourself adding `if` here for a mechanic, it belongs
-- in a phase.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local resolution = script.Parent.Parent.Parent:WaitForChild("resolution")

local DamageResolution = require(resolution:WaitForChild("DamageResolution"))
local AttackContext = require(resolution:WaitForChild("AttackContext"))
local EffectHandlers = require(resolution:WaitForChild("EffectHandlers"))

local eventTypes = game:GetService("ReplicatedStorage"):WaitForChild("eventTape")
    :WaitForChild("event"):WaitForChild("types")
local CombatEvent = require(eventTypes:WaitForChild("CombatEvent"))

-- The sub-domain, required as a child of this module.
local SkillService = require(script:WaitForChild("SkillService"))

local CombatService = {}

CombatService._signals = {}
CombatService.Skills = SkillService

function CombatService:boot()
    -- TODO: declare Combat.OnHit / OnKill / OnParrySuccess once those names
    -- are in this place's vocabulary.
    SkillService:boot()
    DamageResolution.buildPipeline()
end

-- Routed from EventTape: eventType COMBAT resolves here, by ordinary
-- function call. The event arrives already deserialized into a typed Event
-- and already validated for SHAPE -- what remains is validating LEGALITY.
function CombatService:OnAttack(player, event)
    -- TEMPORARY: proves the client -> server path end to end. Replace with
    -- real validation; keep nothing of this block.
    print(string.format(
        "[CombatService] %s -> COMBAT/%s  id=%s  target=%s  skill=%s",
        player.Name,
        event:getSubType(),
        event:getEventId(),
        tostring(CombatEvent.getTargetId(event)),
        tostring(CombatEvent.getSkillId(event))))

    -- Sub-domain dispatch is Combat's own business from here on, never
    -- EventTape's -- which is why SKILL is a COMBAT subType rather than its
    -- own top-level eventType.
    if CombatEvent.isSkillActivation(event) then
        -- Sub-domain dispatch is Combat's own business from here on, never
        -- EventTape's -- which is why SKILL is a COMBAT subType rather than
        -- its own top-level eventType.
        -- TODO: SkillService:activate(attacker, event:get("skillId"), event:get("targetId"))
    end

    -- VALIDATE ------------------------------------------------------------
    -- TODO: does this player own the skill, is it off cooldown, is the
    -- target a legal entity, is it in latency-tolerant range, does
    -- StateService allow the attacker to act. On reject, return and let the
    -- router's explicit reject reach the client (Part 15).
    return false, "NOT_IMPLEMENTED"
end

-- The one entry point every source of damage uses: a basic swing, a skill, a
-- parry counter, a DoT tick, a future zone hazard. Naming it after what it
-- RESOLVES rather than what triggers it is what keeps it reusable.
function CombatService:resolveAttack(attacker, target, activation)
    -- VALIDATE
    -- TODO: StateService gate on the target.

    -- RESOLVE
    local ctx = AttackContext.new(attacker, target, activation)
    DamageResolution.run(ctx)

    -- COMMIT
    -- TODO: drain ShieldHits or HP with ctx.final, collect the REAL applied
    -- amounts into a diff, apply ctx.lifesteal, then dispatch any
    -- content-declared effects. Must not yield: that is what makes the whole
    -- commit atomic for free.
    self:_dispatchEffects(ctx)

    -- ANNOUNCE
    -- TODO: push the outbound diff built from what the commits RETURNED,
    -- never from what the pipeline computed. Then fire the Facts.

    return ctx
end

-- Consequences the Content Layer declared, dispatched by label. Numbers the
-- pipeline computed are applied directly above; only these go through the
-- table, because only these arrived as data.
function CombatService:_dispatchEffects(ctx)
    for _, effect in ipairs(ctx.pendingEffects) do
        local handler = EffectHandlers[effect.type]
        if handler then
            handler.apply(ctx.target, effect, ctx.attacker)
        end
    end
end

return CombatService
