-- src/gameModes/dungeon/server/resolution/DamageResolution.luau
--
-- The resolution pipeline. See Architecture-Reference.md Part 11.1.
--
-- Named after what it RESOLVES, not what triggers it. A basic swing, a
-- skill, a parry counter, a DoT tick and a future zone hazard all need the
-- identical phases -- calling it AttackPipeline would imply attacks own it
-- and make the first hazard tick feel like a hack.
--
-- THE TWO RULES A STEP MUST OBEY:
--
--   1. A step mutates the context and NOTHING else. It may not call a
--      mutating Service, may not fire a Signal, and may not start another
--      resolution. The moment a step mutates the world you get a pipeline
--      running inside a pipeline, and the resulting numbers are untraceable
--      the first time they come out wrong.
--   2. Reads are free. StatService.compute, BuffService.get and
--      StateService.has are queries and safe to call from a step.
--
-- Named phases rather than priority integers: flat numbers become a known
-- pain point once enough modifier types exist to have real interaction rules
-- ("shields resolve before armor, but only if..."), and they get tuned by
-- trial and error instead of reasoned about.

local DamageResolution = {}

local PHASE_ORDER = { "SOURCE", "ATTACKER", "DEFENSE", "INTERCEPT", "COMMIT" }

local phases = {
    SOURCE = {},      -- base damage, weapon contribution, skill multiplier
    ATTACKER = {},    -- crit roll, attacker buffs, stat scaling
    DEFENSE = {},     -- armor, damage reduction, target buffs
    INTERCEPT = {},   -- parry, block, dodge, shield absorption
    COMMIT = {},      -- clamp, choose HP vs ShieldHits, produce ctx.final
}

local built = false

-- Registration is explicit rather than folder-discovered: the full order is
-- readable in one place, and a step cannot appear in the pipeline by virtue
-- of merely existing on disk.
function DamageResolution.register(phase, step)
    assert(phases[phase], "[DamageResolution] unknown phase: " .. tostring(phase))
    assert(type(step) == "function", "[DamageResolution] a step must be a function")
    table.insert(phases[phase], step)
end

-- Empties every phase and allows buildPipeline to run again. The pipeline is
-- module-level state, so anything that registers steps outside the normal
-- boot path -- a test, a hot reload during development -- must be able to
-- put it back rather than leaving strays registered for the rest of the
-- server's life.
function DamageResolution.clear()
    for phaseName in pairs(phases) do
        table.clear(phases[phaseName])
    end
    built = false
end

function DamageResolution.buildPipeline()
    if built then
        return
    end

    local steps = script.Parent:WaitForChild("steps")

    -- TODO: register each step as it is written, e.g.
    --   DamageResolution.register("ATTACKER", require(steps.attacker.CritStep))
    --   DamageResolution.register("DEFENSE", require(steps.defense.ArmorStep))
    DamageResolution.register("INTERCEPT", require(steps:WaitForChild("ParryStep")))

    built = true
end

-- Pure. Mutates only the context it was given.
function DamageResolution.run(ctx)
    for _, phaseName in ipairs(PHASE_ORDER) do
        for _, step in ipairs(phases[phaseName]) do
            -- Deliberately NOT pcall-wrapped. A step throwing is a
            -- programmer error, not hostile input -- swallowing it would
            -- silently produce a wrong number, which is worse than a crash
            -- with a stack trace.
            step(ctx)
        end
    end
    return ctx
end

function DamageResolution.debugPhases()
    local out = {}
    for _, phaseName in ipairs(PHASE_ORDER) do
        out[phaseName] = #phases[phaseName]
    end
    return out
end

return DamageResolution
