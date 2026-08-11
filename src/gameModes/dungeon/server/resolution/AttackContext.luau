-- src/gameModes/dungeon/server/resolution/AttackContext.luau
--
-- The mutable context one DamageResolution run passes down its phases.
-- See Architecture-Reference.md Part 11.1.
--
-- THE FIELDS ARE DECLARED HERE, UP FRONT, ON PURPOSE.
--
-- This context accreting forty fields because every step bolted one on is
-- how the pipeline pattern dies. The rule: if a step needs a value no OTHER
-- step reads, that value belongs inside the step, not here. Adding a field
-- means at least two steps genuinely share it.

local AttackContext = {}
AttackContext.__index = AttackContext

function AttackContext.new(attacker, target, activation)
    activation = activation or {}

    return setmetatable({
        -- Inputs, never mutated by steps
        attacker = attacker,
        target = target,
        activation = activation,
        skillDefinition = activation.skillDefinition,
        tags = activation.tags or {},
        source = activation.source or "COMBAT",
        eventId = activation.eventId,

        -- Resolved through the phases
        damage = activation.baseDamage or 0,
        isCrit = false,
        critMultiplier = 1,
        armorReduction = 0,
        lifesteal = 0,

        -- INTERCEPT outcomes
        parried = false,
        parryDefId = nil,
        blocked = false,
        dodged = false,
        absorbedByShield = false,

        -- Content-declared consequences collected during RESOLVE and
        -- dispatched by CombatService AFTER commit. A step appends here; a
        -- step never applies one.
        pendingEffects = {},

        -- COMMIT output
        final = 0,
        targetResource = "HP",   -- or "ShieldHits"
    }, AttackContext)
end

function AttackContext:addEffect(effect)
    assert(type(effect) == "table" and type(effect.type) == "string",
        "[AttackContext] an effect needs a string type")
    table.insert(self.pendingEffects, effect)
end

function AttackContext:isNegated()
    return self.parried or self.dodged or self.damage <= 0
end

return AttackContext
