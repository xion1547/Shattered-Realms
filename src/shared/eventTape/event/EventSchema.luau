-- src/shared/eventTape/event/EventSchema.luau
--
-- THE ENGINE. One validator for every event payload in the game.
-- See Architecture-Reference.md Part 2 (generic engine + declarative config).
--
-- Before this, each eventType needed a hand-written Event subclass AND a
-- hand-written builder -- two files per type, forever, each repeating the
-- same shape of field checks. That is the N-files-per-thing failure this
-- project exists to avoid, and it had already started: CombatEvent +
-- CombatEventBuilder, AnimationEvent + AnimationEventBuilder.
--
-- Now: this engine, written once, plus ONE declarative schema per type.
-- The schema owns the parameters. There is no second place for them to
-- disagree with.
--
-- SCHEMA FORMAT -- a flat map of fieldName -> FieldSpec:
--
--     local schema: EventSchema.Schema = {
--         targetId = { type = { "string", "number" } },
--         skillId  = { type = "string", requiredFor = { Ev.SubType.SKILL } },
--         speed    = { type = "number", default = 1.0 },
--         slot     = { type = "number", constraint = Validators.range(1, 30) },
--     }
--
--   type        a type name, or a list of accepted type names
--   required    must be present for every subType
--   requiredFor must be present for these subTypes, and is REJECTED on any
--               other -- which is how "a SKILL needs a skillId, a MELEE must
--               not carry one" becomes data instead of a branch
--   default     applied when absent (and the field is not required)
--   constraint  a PURE PREDICATE restricting legal values BEYOND the declared
--               type -- a range, a bounded set. `type` already answers "is
--               this a number"; a constraint answers "is it a number we
--               accept". Deliberately the only place a schema may hold a
--               function, and deliberately narrow: it cannot mutate, cannot
--               branch the engine, and cannot see anything but its own value.
--               Runs only AFTER `type` matched.
--
--               IT VALIDATES THE VALUE, NEVER THE WORLD. A constraint may not
--               consult a definitions table, a registry, or any game state --
--               that would make this layer depend on the Content Layer to
--               answer a question it cannot be trusted on anyway ("this skill
--               exists" is not "this player may use it"). Existence and
--               permission are a Service's job (Part 5). See Validators.luau,
--               which states the boundary and explains what was removed for
--               crossing it.
--
-- WHY THE TYPES BELOW EXIST: without them Luau reverse-engineers a shape from
-- usage and every schema in the codebase resolves to something like
-- `{ [string]: { check: (a) -> (b, string, c...) } }`. A declarative system
-- whose config shape is INFERRED is not declarative. Annotating a schema
-- moves a whole class of authoring mistakes -- a typo'd key, a constraint
-- that is not a function, a requiredFor that is not a list -- from a boot
-- error into a red squiggle.
--
-- Types are erased before the game runs, so none of this validates anything
-- at runtime. That is what parse() is for, and why it does not go away: a
-- client sending `{ speed = "fast" }` is not an authoring mistake and no type
-- can catch it.

local Validators = require(script.Parent.Validators)

local EventSchema = {}

-- One accepted type name, or a list of them.
export type FieldType = string | { string }

-- A pure predicate: true, or false plus the reason why.
export type Constraint = (value: any) -> (boolean, string?)

-- Everything one field declares about itself.
export type FieldSpec = {
    type: FieldType,
    required: boolean?,
    requiredFor: { string }?,
    default: any?,
    constraint: Constraint?,
}

-- fieldName -> what that field accepts.
export type Schema = { [string]: FieldSpec }

local function typeMatches(value: any, expected: FieldType): boolean
    if type(expected) == "table" then
        for _, name in ipairs(expected) do
            if type(value) == name then
                return true
            end
        end
        return false
    end
    return type(value) == expected
end

-- Annotated `: string` so the format calls that consume it type-check.
-- FieldType is a union, and without this the return reads as the union too.
local function describeType(expected: FieldType): string
    if type(expected) == "table" then
        return table.concat(expected, " or ")
    end
    return expected
end

local function knownFields(schema: Schema): string
    local names = {}
    for field in pairs(schema) do
        table.insert(names, field)
    end
    table.sort(names)
    return table.concat(names, ", ")
end

local function isRequired(spec: FieldSpec, subType)
    if spec.required then
        return true
    end
    if spec.requiredFor then
        return table.find(spec.requiredFor, subType) ~= nil
    end
    return false
end

-- A field scoped to specific subTypes is forbidden on every other one.
local function isForbidden(spec: FieldSpec, subType)
    return spec.requiredFor ~= nil and table.find(spec.requiredFor, subType) == nil
end

-- Checks ONE field against its spec. Returns (true) or (false, reason).
--
-- Split out so a builder's :withX() can check at the moment it is called,
-- which is what makes the error name the line that is wrong. Cross-field
-- rules (required, requiredFor, defaults) still run in parse(), because they
-- cannot be judged until every field is in.
function EventSchema.checkField(eventType: string, field: string, spec: FieldSpec, value: any): (boolean, string?)
    if not typeMatches(value, spec.type) then
        return false, string.format(
            "'%s' must be %s, got %s", field, describeType(spec.type), type(value))
    end
    if spec.constraint then
        local ok, reason = spec.constraint(value)
        if not ok then
            return false, string.format("'%s' %s (got: %s)",
                field, reason or "failed its constraint", tostring(value))
        end
    end
    return true
end

-- Untrusted input in, trusted fields out. Returns (fields) or (nil, reason).
--
-- CALLED parse, NOT validate, because it does not answer a yes/no question --
-- it RETURNS the data. The table it hands back is a new one: unknown keys
-- rejected, declared fields copied, defaults filled in. A payload of
-- `{ id = "attack1" }` comes back as `{ id = "attack1", speed = 1.0 }`, bigger
-- than it went in. Nothing called `validate` should be able to do that.
--
-- Failures are RETURNED rather than raised because this runs on the
-- deserialization path too, where malformed input is expected traffic from a
-- client rather than a programmer error. The builder raises on the authoring
-- path, where it IS a programmer error.
function EventSchema.parse(eventType: string, subType: string, schema: Schema, fields: any)
    if type(fields) ~= "table" then
        return nil, string.format("%s: fields must be a table", eventType)
    end

    -- Unknown keys are rejected, and the error lists what was valid. This is
    -- what replaces autocomplete: a misspelled field fails immediately with
    -- the whole vocabulary in the message, rather than being silently
    -- dropped and read as nil somewhere downstream.
    for field in pairs(fields) do
        if schema[field] == nil then
            return nil, string.format(
                "%s/%s: unknown field '%s' -- expected one of: %s",
                eventType, subType, tostring(field), knownFields(schema))
        end
    end

    local parsed = {}

    for field, spec in pairs(schema) do
        local value = fields[field]

        if value ~= nil then
            if isForbidden(spec, subType) then
                return nil, string.format(
                    "%s/%s: '%s' is only valid for subTypes: %s",
                    eventType, subType, field, table.concat(spec.requiredFor :: { string }, ", "))
            end
            if not typeMatches(value, spec.type) then
                return nil, string.format(
                    "%s/%s: '%s' must be %s, got %s",
                    eventType, subType, field, describeType(spec.type), type(value))
            end
            if spec.constraint then
                local ok, reason = spec.constraint(value)
                if not ok then
                    return nil, string.format("%s/%s: '%s' %s (got: %s)",
                        eventType, subType, field,
                        reason or "failed its constraint", tostring(value))
                end
            end
            parsed[field] = value

        elseif isRequired(spec, subType) then
            return nil, string.format(
                "%s/%s: '%s' is required", eventType, subType, field)

        elseif spec.default ~= nil then
            parsed[field] = spec.default
        end
    end

    return parsed
end

-- Boot check: every FieldSpec is well-formed. A schema with a typo'd key is a
-- silently-permissive schema, which is worse than a strict one that errors.
--
-- STILL WORTH RUNNING EVEN THOUGH FieldSpec IS NOW A TYPE. An annotated schema
-- gets most of this from the analyser, but only if it was annotated -- nothing
-- forces that -- and only in an editor, which the server does not have. The
-- uncalled-factory case below is invisible to the type checker regardless: an
-- uncalled factory IS a function and satisfies Constraint structurally.
function EventSchema.validateSchema(eventType: string, schema: any): { string }
    local failures = {}
    local LEGAL_KEYS = {
        type = true, required = true, requiredFor = true,
        default = true, constraint = true,
    }

    if type(schema) ~= "table" then
        return { string.format("%s: schema must be a table", eventType) }
    end

    for field, spec in pairs(schema) do
        if type(spec) ~= "table" then
            table.insert(failures, string.format("%s.%s: spec must be a table", eventType, field))
            continue
        end
        if spec.type == nil then
            table.insert(failures, string.format("%s.%s: missing 'type'", eventType, field))
        end
        if spec.constraint ~= nil and type(spec.constraint) ~= "function" then
            table.insert(failures, string.format(
                "%s.%s: 'constraint' must be a function", eventType, field))
        end
        -- An UNCALLED Validators factory is a function, so it survives the
        -- test above AND satisfies the Constraint type -- and then returns a
        -- closure at runtime, which is truthy, so the constraint silently
        -- passes for every value. Named explicitly because silently-permissive
        -- is the worst way this could fail, and because no type can catch it.
        local uncalled = Validators.uncalledName(spec.constraint)
        if uncalled then
            table.insert(failures, string.format(
                "%s.%s: 'constraint' is Validators.%s itself, uncalled -- every " ..
                "validator is a factory, so it needs (): Validators.%s(...)",
                eventType, field, uncalled, uncalled))
        end
        if spec.requiredFor ~= nil and type(spec.requiredFor) ~= "table" then
            table.insert(failures, string.format("%s.%s: 'requiredFor' must be a list", eventType, field))
        end
        for key in pairs(spec) do
            if not LEGAL_KEYS[key] then
                table.insert(failures, string.format(
                    "%s.%s: unknown spec key '%s'", eventType, field, tostring(key)))
            end
        end
    end

    return failures
end

return EventSchema
