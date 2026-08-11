-- src/gameModes/dungeon/server/tests/SignalServiceTests.luau
--
-- Exercises the Fact broker. See Architecture-Reference.md Part 11.5.
--
-- IMPORTANT: SignalService.init() resets all module state, so these tests
-- must run BEFORE ServerManager:init() establishes the real vocabulary.
-- RunTests enforces that ordering, and Main.server.luau runs the suite first.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local signalFolder = ReplicatedStorage:WaitForChild("utils"):WaitForChild("signal")
local SignalService = require(signalFolder:WaitForChild("SignalService"))

local TestRunner = require(script.Parent:WaitForChild("TestRunner"))

local VOCAB = { "Test.OnAlpha", "Test.OnBeta" }

return function()
    local t = TestRunner.new("SignalService")

    -- Registered first on purpose: cases run in registration order, and
    -- every case below calls init(). This is the only point in the run where
    -- SignalService has never been initialised.
    t:case("declare and on refuse to run before init", function(a)
        a.throws(function() SignalService.declare("Test.OnAlpha") end, "called before init")
        a.throws(function() SignalService.on("Test.OnAlpha", function() end) end, "called before init")
    end)

    t:case("declare rejects a name outside the vocabulary", function(a)
        SignalService.init({ VOCAB })
        a.throws(function() SignalService.declare("Test.Nope") end, "not in this place's signal vocabulary")
    end)

    t:case("declare returns a fire-capable Signal", function(a)
        SignalService.init({ VOCAB })
        local signal = SignalService.declare("Test.OnAlpha")

        a.notNil(signal, "declare must return the Signal")
        a.isType(signal.Fire, "function", "the owner receives Fire")
        a.equal(signal:GetName(), "Test.OnAlpha")
    end)

    t:case("declaring the same fact twice errors", function(a)
        SignalService.init({ VOCAB })
        SignalService.declare("Test.OnAlpha")
        a.throws(function() SignalService.declare("Test.OnAlpha") end, "already declared")
    end)

    t:case("on() after declare connects immediately", function(a)
        SignalService.init({ VOCAB })
        local signal = SignalService.declare("Test.OnAlpha")

        local received
        SignalService.on("Test.OnAlpha", function(value) received = value end)
        signal:Fire("payload")

        a.equal(received, "payload", "the listener should have received the fired value")
    end)

    t:case("on() before declare buffers and flushes on declare", function(a)
        SignalService.init({ VOCAB })

        local received
        SignalService.on("Test.OnAlpha", function(value) received = value end)

        -- Boot order between Services is not something a listener should
        -- have to know, so subscribing first must work.
        local signal = SignalService.declare("Test.OnAlpha")
        signal:Fire("late-bound")

        a.equal(received, "late-bound", "a buffered subscription should be live after declare")
    end)

    t:case("a buffered subscription can be cancelled before declare", function(a)
        SignalService.init({ VOCAB })

        local ran = false
        local handle = SignalService.on("Test.OnAlpha", function() ran = true end)
        handle:Disconnect()

        local signal = SignalService.declare("Test.OnAlpha")
        signal:Fire()

        a.isFalse(ran, "a cancelled buffered subscription must not be flushed")
    end)

    t:case("a buffered subscription can be cancelled after declare", function(a)
        SignalService.init({ VOCAB })

        local count = 0
        local handle = SignalService.on("Test.OnAlpha", function() count += 1 end)
        local signal = SignalService.declare("Test.OnAlpha")

        signal:Fire()
        a.equal(count, 1, "the flushed subscription should fire once")

        handle:Disconnect()
        signal:Fire()
        a.equal(count, 1, "the handle must still work after the flush")
    end)

    t:case("on() rejects an unknown name and a non-function", function(a)
        SignalService.init({ VOCAB })
        a.throws(function() SignalService.on("Test.Nope", function() end) end, "vocabulary")
        a.throws(function() SignalService.on("Test.OnAlpha", "nope") end, "expects a function")
    end)

    t:case("validate passes when every declared fact has an owner", function(a)
        SignalService.init({ VOCAB })
        SignalService.declare("Test.OnAlpha")
        SignalService.declare("Test.OnBeta")
        a.noThrow(function() SignalService.validate() end)
    end)

    t:case("validate fails for a vocabulary name nobody declared", function(a)
        SignalService.init({ VOCAB })
        SignalService.declare("Test.OnAlpha")
        a.throws(function() SignalService.validate() end, "Test.OnBeta")
    end)

    t:case("validate distinguishes a subscribed-but-undeclared fact", function(a)
        SignalService.init({ VOCAB })
        SignalService.declare("Test.OnAlpha")
        SignalService.on("Test.OnBeta", function() end)
        a.throws(function() SignalService.validate() end, "subscribed to by at least one listener")
    end)

    t:case("init rejects a name appearing in two vocabularies", function(a)
        -- Two places both claiming to own one fact makes "exactly one owner"
        -- unenforceable, so it fails at init rather than silently.
        a.throws(function()
            SignalService.init({ { "Test.OnAlpha" }, { "Test.OnAlpha" } })
        end, "more than one vocabulary")
    end)

    t:case("init rejects a malformed vocabulary", function(a)
        a.throws(function() SignalService.init("not a table") end, "array of vocabulary tables")
        a.throws(function() SignalService.init({ { 42 } }) end, "non-string entry")
    end)

    local result = t:run()

    -- Leaves module state clean. ServerManager:init() calls SignalService.init()
    -- again anyway, which fully resets, but leaving a half-built vocabulary
    -- behind would make a boot failure here look like a production one.
    -- This must run AFTER t:run(): t:case only registers, it does not execute.
    SignalService.init({})

    return result
end
