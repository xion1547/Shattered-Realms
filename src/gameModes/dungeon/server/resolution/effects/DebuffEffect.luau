-- Effect handler: DEBUFF. apply(target, effect, source).
--
-- Separate from BUFF because content reads better declaring intent, not
-- because the mechanism differs -- both end at BuffService, which resolves
-- the stack rule. If these two ever stop differing in content vocabulary
-- too, collapse them.

local DebuffEffect = {}

function DebuffEffect.apply(target, effect, source)
    -- TODO: BuffService:apply(target, BuffDefinitions[effect.buff], source)
end

return DebuffEffect
