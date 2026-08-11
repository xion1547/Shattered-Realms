-- Effect handler: DAMAGE. Shape is exactly apply(target, effect, source).
--
-- This module requires CombatService; EffectHandlers requires only this
-- module. That indirection is what keeps the label table from becoming a
-- Service Locator -- the table never names a Service.
--
-- A parry counter resolves through here, which means it is a FULL second
-- pipeline run with the roles swapped, sequenced after the first resolution
-- committed. Not nested inside it.

local DamageEffect = {}

function DamageEffect.apply(target, effect, source)
    -- TODO:
    -- local CombatService = require(...services.domain.CombatService)
    -- CombatService:resolveAttack(source, target, {
    --     baseDamage = effect.amount,
    --     source = "EFFECT_DAMAGE",
    -- })
end

return DamageEffect
