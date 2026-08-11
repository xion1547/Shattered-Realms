-- src/gameModes/dungeon/server/resolution/EffectHandlers.luau
--
-- SERVER ONLY. Label -> one handler, for consequences the Content Layer
-- declared. See Architecture-Reference.md Part 11.2.
--
-- WHY THIS EXISTS, precisely: two kinds of change come out of a resolution.
-- Numbers the pipeline computed (final damage, crit, lifesteal) are Combat's
-- own arithmetic -- exactly one of each, names known at write time, applied
-- by direct call in COMMIT. Consequences the content declared
-- (`{ type = "DEBUFF", buff = "POISON" }`) arrive from a definitions file,
-- vary in count per entry, and a designer can add a fifth tomorrow. You
-- cannot hardcode a call for something that arrived as data. That is the
-- entire justification, and it keeps the dispatched set small.
--
-- A FLAT STATIC TABLE, NOT A register() REGISTRY. Registration scatters the
-- vocabulary across N files and adds boot-order questions, for a closed set
-- of maybe eight entries -- the same reason Part 12 chose a flat routing
-- table over a folder of handler modules.
--
-- THE DISCIPLINE: every entry is shaped exactly
-- `apply(target, effect, source) -> ()`. The moment something is registered
-- that is not "apply this effect to this target" -- the moment this becomes
-- where any Service reaches any other Service by name because it is already
-- required everywhere -- it has stopped being effect dispatch and become a
-- genuine Service Locator. A closed narrow vocabulary is fine; an open door
-- is not.
--
-- Handler modules require Services. This table requires only handlers.

local effects = script.Parent:WaitForChild("effects")

return {
    DAMAGE = require(effects:WaitForChild("DamageEffect")),
    HEAL = require(effects:WaitForChild("HealEffect")),
    BUFF = require(effects:WaitForChild("BuffEffect")),
    DEBUFF = require(effects:WaitForChild("DebuffEffect")),
    STATE = require(effects:WaitForChild("StateEffect")),
}
