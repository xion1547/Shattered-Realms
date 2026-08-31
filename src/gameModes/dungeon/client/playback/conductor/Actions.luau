-- src/gameModes/dungeon/client/playback/conductor/Actions.luau
--
-- THE THINGS A TRIGGER CAN DO. One entry per action, dispatched by label.
--
-- A flat static table rather than a `register()` registry, for the reason
-- `EffectHandlers` is one: registration scatters the vocabulary across N files
-- and adds boot-order questions, for a closed set that fits on a screen.
--
-- ============================================================================
-- WHY THIS EXISTS AT ALL -- THE ONE THING A PROPERTY TRACK CANNOT DO
-- ============================================================================
--
-- Every value track is IDEMPOTENT: asking for Transparency at t=0.4 twice gives
-- the same answer twice, so re-reading it every frame is free and correct.
--
-- An action is not. `Emit(30)` twice emits sixty particles. There is no value
-- to interpolate toward, no half-emitted state, and no key density at which a
-- property track could express it.
--
-- ============================================================================
-- KEEPING THIS SMALL IS A DECISION, NOT AN OVERSIGHT
-- ============================================================================
--
-- Moonlite's equivalent -- `Specials.lua` -- is 611 lines for FOUR classes, and
-- it stores state in attributes because some of those actions have no property
-- to read back. That is the measure of how far this can sprawl.
--
-- Two entries. Add a third when an effect actually asks for one, and never
-- because a class "might" need it.
--
-- ============================================================================
-- EVERY HANDLER IS (instance, trigger) -> (), AND THAT IS THE DISCIPLINE
-- ============================================================================
--
-- The moment something in here is not "do this one thing to this one instance"
-- -- the moment it reads game state, decides something, or reaches for a
-- Service -- it has stopped being an action and become logic living in a
-- lookup table. A Score is cosmetic; nothing here may change an outcome.

local Actions = {}

local ScoreTypes = require(
    game:GetService("ReplicatedStorage"):WaitForChild("types"):WaitForChild("Score"))

export type Handler = (instance: Instance, trigger: ScoreTypes.Trigger) -> ()

-- A PARTICLE BURST.
--
-- `Emit` ignores `Rate` entirely, which is what makes "one particle, once,
-- then gone" expressible: leave `Rate = 0` on the emitter forever and let the
-- Score decide every burst.
--
-- The instance check is not defensive noise -- a Score targeting the wrong
-- child is the likeliest authoring mistake here, and `Emit` simply does not
-- exist on a Part. Erroring per-frame would be worse than saying so once.
local function emit(instance: Instance, trigger: ScoreTypes.Trigger)
    if not instance:IsA("ParticleEmitter") then
        warn(string.format(
            "[Conductor] EMIT wants a ParticleEmitter, got a %s (%s)",
            instance.ClassName, instance:GetFullName()))
        return
    end

    instance:Emit(trigger.count or 1)
end

-- A SOUND, restarted from the beginning.
--
-- `TimePosition = 0` before `Play` because a Sound that is already playing
-- ignores `Play` -- so a second trigger on the same sound would do nothing,
-- which reads as a dropped beat rather than as a rule.
local function playSound(instance: Instance, _trigger: ScoreTypes.Trigger)
    if not instance:IsA("Sound") then
        warn(string.format(
            "[Conductor] SOUND wants a Sound, got a %s (%s)",
            instance.ClassName, instance:GetFullName()))
        return
    end

    instance.TimePosition = 0
    instance:Play()
end

Actions.BY_NAME = {
    EMIT = emit,
    SOUND = playSound,
} :: { [string]: Handler }

function Actions.supports(name: string): boolean
    return Actions.BY_NAME[name] ~= nil
end

-- Returns whether it ran, so the caller can say WHICH trigger was unknown
-- rather than failing silently.
function Actions.run(instance: Instance, trigger: ScoreTypes.Trigger): boolean
    local handler = Actions.BY_NAME[trigger.action]
    if not handler then
        return false
    end

    handler(instance, trigger)
    return true
end

return Actions
