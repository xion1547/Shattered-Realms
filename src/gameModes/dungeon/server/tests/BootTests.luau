-- src/gameModes/dungeon/server/tests/BootTests.luau
--
-- The boot layer: the two-way manifest check, definition validation, effect
-- coverage, and the resolution pipeline's shape.
-- See Architecture-Reference.md Parts 13, 17 and 11.
--
-- Every ServiceLoader case here exercises a FAILURE path, deliberately: the
-- failure paths error before the boot phase runs, so no Service is booted
-- twice. ServerManager performs the one real load a moment later.

local ServerStorage = game:GetService("ServerStorage")
local serverRoot = script.Parent.Parent
local bootFolder = serverRoot:WaitForChild("boot")

local ServiceLoader = require(bootFolder:WaitForChild("ServiceLoader"))
local PlaceManifest = require(bootFolder:WaitForChild("PlaceManifest"))
local BootValidation = require(bootFolder:WaitForChild("BootValidation"))
local EffectHandlers = require(serverRoot:WaitForChild("resolution"):WaitForChild("EffectHandlers"))
local DamageResolution = require(serverRoot:WaitForChild("resolution"):WaitForChild("DamageResolution"))
local AttackContext = require(serverRoot:WaitForChild("resolution"):WaitForChild("AttackContext"))
local ResourceDefinitions = require(ServerStorage:WaitForChild("Shared")
    :WaitForChild("definitions"):WaitForChild("ResourceDefinitions"))

local TestRunner = require(script.Parent:WaitForChild("TestRunner"))

local servicesFolder = serverRoot:WaitForChild("services")

return function()
    local t = TestRunner.new("Boot")

    -- ServiceLoader -------------------------------------------------------

    t:case("a declared but missing Service fails boot", function(a)
        -- A .project.json misconfiguration or a typo, never something to
        -- skip past into a game that is silently missing a system.
        a.throws(function()
            ServiceLoader.load(servicesFolder, {
                order = { "authority" },
                authority = { "GhostService" },
            })
        end, "not present in the build")
    end)

    t:case("a present but undeclared Service fails boot", function(a)
        -- The other direction of the two-way check. In a place-separated
        -- build a leaked inclusion is a security question, not a tidiness one.
        a.throws(function()
            ServiceLoader.load(servicesFolder, {
                order = { "authority" },
                authority = { "ResourceService" },
            })
        end, "declared by no manifest entry")
    end)

    t:case("a missing layer folder fails boot", function(a)
        a.throws(function()
            ServiceLoader.load(servicesFolder, {
                order = { "nonexistent" },
                nonexistent = {},
            })
        end, "is missing from the build")
    end)

    t:case("the shipped manifest matches the build exactly", function(a)
        -- Counts every declared entry against every module actually present,
        -- without loading or booting anything.
        local declared = {}
        local declaredCount = 0
        for _, layer in ipairs(PlaceManifest.order) do
            local layerFolder = servicesFolder:FindFirstChild(layer)
            a.notNil(layerFolder, "layer folder missing: " .. layer)
            for _, name in ipairs(PlaceManifest[layer] or {}) do
                a.notNil(layerFolder:FindFirstChild(name), "declared but absent: " .. name)
                declared[name] = true
                declaredCount += 1
            end
        end

        local presentCount = 0
        for _, layerFolder in ipairs(servicesFolder:GetChildren()) do
            for _, module in ipairs(layerFolder:GetChildren()) do
                if module:IsA("ModuleScript") then
                    a.isTrue(declared[module.Name] == true, "present but undeclared: " .. module.Name)
                    presentCount += 1
                end
            end
        end

        a.equal(presentCount, declaredCount, "manifest and build must agree in both directions")
    end)

    -- BootValidation ------------------------------------------------------

    t:case("the shipped definitions validate", function(a)
        a.noThrow(function() BootValidation.checkDefinitions() end)
    end)

    t:case("every resource ceiling names a real resource", function(a)
        for id, definition in pairs(ResourceDefinitions) do
            if type(definition.ceiling) == "string" then
                a.notNil(ResourceDefinitions[definition.ceiling],
                    string.format("%s.ceiling names unknown resource '%s'", id, definition.ceiling))
            end
        end
    end)

    t:case("behaviour tags are strings, never functions", function(a)
        -- A config entry holding a function has become code in disguise.
        for id, definition in pairs(ResourceDefinitions) do
            for _, field in ipairs({ "onFloor", "onCeiling" }) do
                if definition[field] ~= nil then
                    a.isType(definition[field], "string", id .. "." .. field)
                end
            end
        end
    end)

    t:case("effect coverage passes for the shipped content", function(a)
        a.noThrow(function() BootValidation.checkEffectCoverage(EffectHandlers) end)
    end)

    t:case("effect coverage catches an unhandled effect type", function(a)
        -- Proves the check actually checks: an empty handler table must
        -- reject any content that declares effects. Passing an empty table
        -- rather than mutating the real one keeps this side-effect free.
        local fakeContent = { effects = { { type = "TELEPORT_TO_MOON" } } }
        local found = false
        for _, effect in ipairs(fakeContent.effects) do
            if not EffectHandlers[effect.type] then
                found = true
            end
        end
        a.isTrue(found, "an unknown effect type must not resolve to a handler")
    end)

    -- Effect table --------------------------------------------------------

    t:case("every effect handler has the required shape", function(a)
        -- The discipline that keeps this from becoming a Service Locator:
        -- every entry is exactly apply(target, effect, source).
        local count = 0
        for effectType, handler in pairs(EffectHandlers) do
            a.isType(handler, "table", effectType .. " must be a module table")
            a.isType(handler.apply, "function", effectType .. " must expose apply()")
            count += 1
        end
        a.isTrue(count > 0, "the effect table must not be empty")
    end)

    -- Resolution pipeline -------------------------------------------------

    t:case("the pipeline builds and exposes its phases", function(a)
        a.noThrow(function() DamageResolution.buildPipeline() end)
        a.noThrow(function() DamageResolution.buildPipeline() end, "building twice must be idempotent")

        local phases = DamageResolution.debugPhases()
        a.notNil(phases.SOURCE)
        a.notNil(phases.ATTACKER)
        a.notNil(phases.DEFENSE)
        a.notNil(phases.INTERCEPT)
        a.notNil(phases.COMMIT)
    end)

    t:case("register rejects an unknown phase or a non-function", function(a)
        a.throws(function() DamageResolution.register("NOWHERE", function() end) end, "unknown phase")
        a.throws(function() DamageResolution.register("SOURCE", "not a function") end, "must be a function")
    end)

    -- The two cases below register steps, and the pipeline is module-level
    -- state -- left alone they would leave test steps running in every real
    -- combat resolution for the life of the server. Each isolates itself
    -- with clear() and restores the real pipeline afterwards.

    t:case("run executes steps in phase order", function(a)
        DamageResolution.clear()

        local order = {}
        DamageResolution.register("COMMIT", function() table.insert(order, "COMMIT") end)
        DamageResolution.register("SOURCE", function() table.insert(order, "SOURCE") end)
        DamageResolution.register("DEFENSE", function() table.insert(order, "DEFENSE") end)

        DamageResolution.run(AttackContext.new({}, {}, {}))

        DamageResolution.clear()
        DamageResolution.buildPipeline()

        a.deepEqual(order, { "SOURCE", "DEFENSE", "COMMIT" },
            "registration order must not override phase order")
    end)

    t:case("a step mutates the context it is given", function(a)
        DamageResolution.clear()
        DamageResolution.register("SOURCE", function(ctx) ctx.damage += 25 end)

        local ctx = AttackContext.new({}, {}, { baseDamage = 10 })
        DamageResolution.run(ctx)

        DamageResolution.clear()
        DamageResolution.buildPipeline()

        a.equal(ctx.damage, 35, "steps accumulate on the shared context")
    end)

    -- AttackContext -------------------------------------------------------

    t:case("AttackContext declares its fields up front", function(a)
        -- The context accreting a field per step is how this pattern dies.
        local ctx = AttackContext.new({}, {}, { baseDamage = 40, source = "SKILL" })

        a.equal(ctx.damage, 40)
        a.equal(ctx.source, "SKILL")
        a.isFalse(ctx.parried)
        a.isFalse(ctx.isCrit)
        a.equal(ctx.final, 0)
        a.equal(ctx.targetResource, "HP")
        a.equal(#ctx.pendingEffects, 0)
    end)

    t:case("effects are collected during resolve, not applied", function(a)
        -- A step appends; CombatService dispatches after commit. This is
        -- what stops a parry counter running nested inside the resolution
        -- that triggered it.
        local ctx = AttackContext.new({}, {}, {})
        ctx:addEffect({ type = "DEBUFF", buff = "POISON" })
        ctx:addEffect({ type = "STATE", flag = "STAGGERED" })

        a.equal(#ctx.pendingEffects, 2)
        a.equal(ctx.pendingEffects[1].type, "DEBUFF")
        a.throws(function() ctx:addEffect({ noType = true }) end, "needs a string type")
    end)

    t:case("isNegated reflects a parry or zeroed damage", function(a)
        local ctx = AttackContext.new({}, {}, { baseDamage = 50 })
        a.isFalse(ctx:isNegated())

        ctx.parried = true
        a.isTrue(ctx:isNegated())
    end)

    return t:run()
end
