-- src/gameModes/dungeon/server/tests/SignalTests.luau
--
-- Exercises Signal.luau directly. See Architecture-Reference.md Part 11.5.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local signalFolder = ReplicatedStorage:WaitForChild("utils"):WaitForChild("signal")
local Signal = require(signalFolder:WaitForChild("Signal"))

local TestRunner = require(script.Parent:WaitForChild("TestRunner"))

return function()
    local t = TestRunner.new("Signal")

    t:case("Fire calls every listener with the given arguments", function(a)
        local signal = Signal.new("Test.OnThing")
        local seen = {}
        signal:Connect(function(x, y) table.insert(seen, { "first", x, y }) end)
        signal:Connect(function(x, y) table.insert(seen, { "second", x, y }) end)

        signal:Fire(7, "hello")

        a.equal(#seen, 2, "both listeners should have run")
        a.equal(seen[1][1], "first", "connection order should be preserved")
        a.equal(seen[1][2], 7, "first argument should pass through")
        a.equal(seen[1][3], "hello", "second argument should pass through")
        a.equal(seen[2][1], "second")
    end)

    t:case("Fire with no listeners is a no-op", function(a)
        local signal = Signal.new("Test.Empty")
        a.noThrow(function() signal:Fire(1, 2, 3) end)
    end)

    t:case("Connect returns a handle whose Disconnect removes the listener", function(a)
        local signal = Signal.new("Test.OnThing")
        local count = 0
        local handle = signal:Connect(function() count += 1 end)

        signal:Fire()
        a.equal(count, 1, "listener should run while connected")

        a.notNil(handle, "Connect must return a handle")
        a.isTrue(handle.Connected, "a fresh handle reports Connected")
        handle:Disconnect()
        a.isFalse(handle.Connected, "a disconnected handle reports not Connected")

        signal:Fire()
        a.equal(count, 1, "listener must not run after Disconnect")
    end)

    t:case("Disconnecting twice is harmless", function(a)
        local signal = Signal.new("Test.OnThing")
        local handle = signal:Connect(function() end)
        handle:Disconnect()
        a.noThrow(function() handle:Disconnect() end)
    end)

    t:case("The same function connected twice fires twice", function(a)
        -- Deliberate behaviour change: the old Signal silently ignored a
        -- duplicate function, which hid double-registration bugs.
        local signal = Signal.new("Test.OnThing")
        local count = 0
        local fn = function() count += 1 end
        signal:Connect(fn)
        signal:Connect(fn)

        signal:Fire()
        a.equal(count, 2, "duplicate connections should both fire")
    end)

    t:case("A listener disconnected mid-broadcast does not run", function(a)
        local signal = Signal.new("Test.OnThing")
        local secondRan = false
        local secondHandle

        signal:Connect(function() secondHandle:Disconnect() end)
        secondHandle = signal:Connect(function() secondRan = true end)

        signal:Fire()
        a.isFalse(secondRan, "a listener disconnected during Fire must be skipped")
    end)

    t:case("A listener connected mid-broadcast does not run in that broadcast", function(a)
        local signal = Signal.new("Test.OnThing")
        local lateRan = 0

        signal:Connect(function()
            signal:Connect(function() lateRan += 1 end)
        end)

        signal:Fire()
        a.equal(lateRan, 0, "the snapshot must exclude listeners added during Fire")

        signal:Fire()
        a.equal(lateRan, 1, "the new listener should run on the next Fire")
    end)

    t:case("One failing listener does not stop the others", function(a)
        local signal = Signal.new("Test.OnThing")
        local ranAfter = false
        signal:Connect(function() error("intentional failure") end)
        signal:Connect(function() ranAfter = true end)

        a.noThrow(function() signal:Fire() end, "Fire must not propagate a listener error")
        a.isTrue(ranAfter, "listeners after a failing one must still run")
    end)

    t:case("Connect rejects a non-function", function(a)
        local signal = Signal.new("Test.OnThing")
        a.throws(function() signal:Connect("not a function") end, "expects a function")
    end)

    t:case("DisconnectAll removes every listener", function(a)
        local signal = Signal.new("Test.OnThing")
        local count = 0
        local handle = signal:Connect(function() count += 1 end)
        signal:Connect(function() count += 1 end)

        signal:DisconnectAll()
        signal:Fire()

        a.equal(count, 0, "no listener should run after DisconnectAll")
        a.isFalse(handle.Connected, "handles should report disconnected")
    end)

    t:case("Destroy blocks further connections and fires", function(a)
        local signal = Signal.new("Test.OnThing")
        local count = 0
        signal:Connect(function() count += 1 end)
        signal:Destroy()

        a.throws(function() signal:Connect(function() end) end, "destroyed")
        a.noThrow(function() signal:Fire() end, "firing a destroyed signal warns, it does not throw")
        a.equal(count, 0, "a destroyed signal must not reach listeners")
        a.noThrow(function() signal:Destroy() end, "Destroy should be idempotent")
    end)

    t:case("GetName reports the declared name", function(a)
        local signal = Signal.new("Combat.OnKill")
        a.equal(signal:GetName(), "Combat.OnKill")
        a.equal(Signal.new():GetName(), "<anonymous>", "an unnamed signal still reports something")
    end)

    return t:run()
end
