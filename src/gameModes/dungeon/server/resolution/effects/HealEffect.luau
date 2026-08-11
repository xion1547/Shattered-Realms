-- Effect handler: HEAL. apply(target, effect, source).
--
-- A heal is `resolve amount -> check the StateService gate -> grant`. Three
-- lines, no phases, no pipeline. Build a second resolution pipeline when
-- healing actually has ten modifiers, not before.

local HealEffect = {}

function HealEffect.apply(target, effect, source)
    -- TODO: StateService gate, then
    -- ResourceService:grant(target, "HP", effect.amount, "EFFECT_HEAL")
end

return HealEffect
