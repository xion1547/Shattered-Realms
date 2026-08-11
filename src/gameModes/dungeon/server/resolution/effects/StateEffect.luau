-- Effect handler: STATE. apply(target, effect, source).
--
-- Sets one of StateService's fixed flags. Content may only name a declared
-- flag -- StateService asserts on an unknown one rather than inventing it,
-- which is what keeps the flag vocabulary closed.

local StateEffect = {}

function StateEffect.apply(target, effect, source)
    -- TODO: StateService:set(target, effect.flag, effect.duration, source)
end

return StateEffect
