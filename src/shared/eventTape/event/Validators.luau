-- src/shared/eventTape/event/Validators.luau
--
-- Predicates for a FieldSpec's `constraint`. Nothing here is an engine --
-- EventSchema is unchanged by every one of these. They are just functions
-- matching EventSchema.Constraint, the slot it already declares.
--
--     slot    = { type = "number", constraint = Validators.range(1, 30) }
--     speed   = { type = "number", default = 1.0, constraint = Validators.range(0.1, 4) }
--     skillId = { type = "string", constraint = Validators.nonEmptyString() }
--
-- THE BOUNDARY THIS FILE MUST NOT CROSS, and the reason it is stated first:
--
--     A CONSTRAINT VALIDATES THE VALUE. IT NEVER VALIDATES THE WORLD.
--
-- Every predicate here answers its question from the value and the schema
-- alone. None of them may consult a definitions table, a registry, a player,
-- or anything else that is game state. There WAS an `existsIn(catalog)` here
-- for exactly that, and AnimationEvent used it via AnimationRegistry.isKnown.
-- Both are gone, for two reasons:
--
--   1. IT MADE THE TRANSPORT LAYER DEPEND ON THE CONTENT LAYER. EventTape's
--      job is to establish that a payload is well-formed. The moment it also
--      answers "does this skill exist", it needs to know what skills are.
--
--   2. IT DID NOT EVEN BUY ANYTHING. Knowing CLEAVE is a declared skill says
--      nothing about whether this player owns it, has unlocked it, or has it
--      off cooldown. The Service has to answer all of that regardless -- so
--      the schema check was work that could not be trusted on its own, paid
--      for with a dependency. A faked skillId is a Service's problem, and
--      the Service is where it dies (Part 5: shape at the boundary,
--      authorisation in the domain).
--
-- If a check needs a catalog, it is not a constraint. It is a game rule.
--
-- THE CONTRACT: a constraint is a PURE PREDICATE. It cannot mutate, cannot
-- branch the engine, and cannot see anything but its own value. It may return
-- (false, reason) instead of bare false, so a composed one can say WHICH part
-- failed. It runs only AFTER `type` matched.
--
-- EVERYTHING IS A FACTORY -- `Validators.nonEmptyString()`, never
-- `Validators.nonEmptyString`. Uniform on purpose; see the footgun guard at
-- the bottom for what the uniformity buys.
--
-- THERE IS NO `boolean()` AND THERE SHOULD NOT BE. A constraint narrows the
-- values a type already admits. A boolean admits exactly true and false and
-- both are legal, so there is nothing left to narrow -- `type = "boolean"` is
-- the whole validation. The same goes for any field whose type is its only
-- rule; reaching for a constraint there just re-runs the type check.

local Validators = {}

-- STRUCTURALLY IDENTICAL TO EventSchema.Constraint, and duplicated rather
-- than aliased BECAUSE IT HAS TO BE. This is a leaf module -- EventSchema
-- requires Validators, so requiring EventSchema back would be a cycle, and a
-- type alias cannot be imported without requiring the module that holds it.
--
-- Luau matches function types structurally, so the two stay interchangeable
-- at every call site regardless.
export type Constraint = (value: any) -> (boolean, string?)

-- WRONG TYPE IS A FAILURE, NOT A SHRUG. These predicates used to return true
-- for a value of the wrong type, on the theory that `type` had already been
-- checked and a union type might legitimately send a string to `range`. That
-- was a validator reporting "passed" for something it never looked at -- and
-- it meant a mis-declared `{ type = "string", constraint = range(1, 30) }`
-- validated nothing, forever, silently. On an untrusted boundary no branch
-- should mean "I did not check". The union case that motivated it is not
-- real; if it ever is, write a bespoke predicate for that field.
-- Every numeric predicate goes through this first, so the two pathological
-- floats are rejected in ONE place rather than each validator remembering.
--
-- NaN fails EVERY comparison, so any naive bounds test lets it through:
-- `value <= 0` is false for NaN, and so is `value > 0`. It survives a
-- RemoteEvent, so a client can send one, and it spreads through arithmetic --
-- one NaN in a damage number leaves a health value no later heal can repair.
--
-- Infinity compares normally, so a two-sided bound catches it, but a
-- one-sided one does not: math.huge passes "greater than zero" cleanly. No
-- gameplay number is ever legitimately infinite, so it is refused here rather
-- than left for each caller to remember.
local function requireRealNumber(value: any): (boolean, string?)
    if type(value) ~= "number" then
        return false, "must be a number"
    end
    if value ~= value then
        return false, "must be a real number"
    end
    if value == math.huge or value == -math.huge then
        return false, "must be finite"
    end
    return true
end

-- Rejects "". A field that is present but empty is almost always a bug at the
-- sender, not a legitimate value.
function Validators.nonEmptyString(): Constraint
    return function(value)
        if type(value) ~= "string" then
            return false, "must be a string"
        end
        if #value == 0 then
            return false, "must not be empty"
        end
        return true
    end
end

-- Whole numbers only. Slot indices, hit counts, quantities.
function Validators.integer(): Constraint
    return function(value)
        local ok, reason = requireRealNumber(value)
        if not ok then
            return false, reason
        end
        if value % 1 ~= 0 then
            return false, "must be a whole number"
        end
        return true
    end
end

-- Strictly greater than zero. Durations, multipliers, distances -- anything
-- where zero is as meaningless as a negative.
--
-- SEPARATE FROM range() BECAUSE range IS INCLUSIVE. `range(0, n)` admits zero,
-- which is usually the exact value being excluded: a speed of 0 stalls an
-- animation forever, a distance of 0 is not a distance. Writing range(0.0001,
-- n) to dodge that is inventing a bound nobody chose.
function Validators.positiveNumber(): Constraint
    return function(value)
        local ok, reason = requireRealNumber(value)
        if not ok then
            return false, reason
        end
        if value <= 0 then
            return false, "must be greater than zero"
        end
        return true
    end
end

-- Inclusive on both ends.
function Validators.range(min: number, max: number): Constraint
    assert(type(min) == "number" and type(max) == "number",
        "[Validators] range(min, max) needs two numbers")
    assert(min <= max, "[Validators] range(min, max) needs min <= max")

    return function(value)
        -- NaN and infinity are already refused by requireRealNumber, which is
        -- why there is no guard for them here any more.
        local ok, reason = requireRealNumber(value)
        if not ok then
            return false, reason
        end
        if value < min or value > max then
            -- tostring() rather than passing numbers to %s: %s is typed as
            -- taking a string, and %d would reject the fractional bounds this
            -- is explicitly used with, as in range(0.1, 4).
            return false, string.format(
                "must be between %s and %s", tostring(min), tostring(max))
        end
        return true
    end
end

-- Membership in a fixed list of legal values.
--
-- NOT A CATALOG LOOKUP. The list is written into the schema, so this still
-- answers from the value and the schema alone -- it is the one membership
-- test that stays on the right side of the boundary above.
--
-- For a CLOSED VOCABULARY the enum is still the door (Part 2) -- this does not
-- replace CombatEvent.SubType. It is for a small set of legal values inside
-- one field, where an enum module would be more ceremony than the set is worth.
function Validators.oneOf(legalValues: { any }): Constraint
    assert(type(legalValues) == "table" and #legalValues > 0,
        "[Validators] oneOf(list) needs a non-empty array")

    local allowed = table.freeze(table.clone(legalValues))

    return function(value)
        if table.find(allowed, value) then
            return true
        end
        return false, string.format("must be one of: %s", table.concat(allowed, ", "))
    end
end

-- Every predicate must pass, and the first failure ends it -- nothing after a
-- failed check runs. The reason reported is the one that actually failed,
-- which is the whole point of threading reasons through; otherwise a composed
-- constraint says "failed" and you get to guess which half.
function Validators.all(...: Constraint): Constraint
    local predicates = table.pack(...)
    assert(predicates.n > 0, "[Validators] all(...) needs at least one predicate")

    for index = 1, predicates.n do
        assert(type(predicates[index]) == "function",
            string.format("[Validators] all(...) argument %d is not a function", index))
    end

    return function(value)
        for index = 1, predicates.n do
            local ok, reason = predicates[index](value)
            if not ok then
                return false, reason or string.format("failed constraint #%d", index)
            end
        end
        return true
    end
end

-- The footgun guard -----------------------------------------------------
--
-- `constraint = Validators.range` (never called) is a FUNCTION, so it passes a
-- naive "must be a function" test AND satisfies the Constraint type
-- structurally -- then at runtime it returns a closure, which is truthy, so
-- the constraint passes for every value. No type can catch that.
--
-- THIS IS WHY EVERY VALIDATOR IS A FACTORY. With no bare predicates, any
-- constraint that IS one of this module's own functions is by definition the
-- uncalled mistake, so the check is a scan of the module rather than a
-- hand-maintained list of which functions happen to be factories. The old
-- version kept such a list, and a list you must remember to append to is a
-- guard that silently stops covering whatever you forget.
--
-- A bespoke predicate written elsewhere is not in this table, so it passes --
-- correctly, since it is not an uncalled Validators factory.
function Validators.uncalledName(value: any): string?
    if type(value) ~= "function" then
        return nil
    end
    for name, candidate in pairs(Validators) do
        if candidate == value then
            return name
        end
    end
    return nil
end

return Validators
