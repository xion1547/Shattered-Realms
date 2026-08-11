-- src/gameModes/dungeon/server/tests/RunTests.luau
--
-- Boot-time test suite. Called from Main.server.luau BEFORE ServerManager,
-- and the ordering is not incidental:
--
--   * SignalServiceTests calls SignalService.init(), which resets all module
--     state. Running after ServerManager would wipe the real vocabulary and
--     the declared session facts out from under a live server.
--   * Running first means a system that throws on first use is reported
--     before anything depends on it -- which is the failure mode this suite
--     exists for. See Part 19.
--
-- Set ENABLED = false to skip the suite in a shipping build.

local ENABLED = true

-- Whether a failing suite should stop the server from booting. Off by
-- default so a broken test does not make the place unplayable while you are
-- working in it -- the banner is loud enough to not be missed.
local HALT_ON_FAILURE = false

local RunTests = {}

local SUITES = {
    "SignalTests",
    "SignalServiceTests",
    "ComponentTests",
    "SpatialTests",
    "EventTests",
    "EventTapeTests",
    "EventRouterTests",
    "BootTests",
}

function RunTests.run()
    if not ENABLED then
        return true
    end

    local started = os.clock()
    local results = {}
    local totalPassed, totalFailed = 0, 0

    print("========================================")
    print("  Boot test suite")
    print("========================================")

    for _, suiteName in ipairs(SUITES) do
        local moduleScript = script.Parent:FindFirstChild(suiteName)
        if not moduleScript then
            warn(string.format("  [MISSING] %s -- suite module not found", suiteName))
            totalFailed += 1
            continue
        end

        -- A suite that fails to load or throws outside a case is itself a
        -- failure, not a reason to abandon the rest of the run.
        local ok, result = pcall(function()
            return require(moduleScript)()
        end)

        if not ok then
            warn(string.format("  [ERROR]  %s -- suite crashed: %s", suiteName, tostring(result)))
            totalFailed += 1
            continue
        end

        table.insert(results, result)
        totalPassed += result.passed
        totalFailed += result.failed

        local status = result.failed == 0 and "PASS" or "FAIL"
        print(string.format("  [%s]  %-28s %d passed, %d failed",
            status, result.name, result.passed, result.failed))
    end

    for _, result in ipairs(results) do
        for _, failure in ipairs(result.failures) do
            warn(string.format("\n  FAILED  %s :: %s\n    %s",
                result.name, failure.name, failure.message))
        end
    end

    local elapsed = (os.clock() - started) * 1000
    print("----------------------------------------")
    print(string.format("  %d passed, %d failed  (%.1fms)", totalPassed, totalFailed, elapsed))
    print("========================================")

    if totalFailed > 0 then
        local message = string.format("[RunTests] %d test(s) failed at boot", totalFailed)
        if HALT_ON_FAILURE then
            error(message, 0)
        end
        warn(message)
        return false
    end

    return true
end

return RunTests
