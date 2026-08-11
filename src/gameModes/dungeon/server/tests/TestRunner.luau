-- src/gameModes/dungeon/server/tests/TestRunner.luau
--
-- A deliberately tiny test harness. No dependencies, no framework.
--
-- This exists because the architecture is being rebuilt from a state where
-- several modules threw on first use and nobody noticed -- see Part 19. A
-- boot-time suite that exercises each system's real entry points turns that
-- class of failure from "discovered by a player" into "printed in the output
-- window before the place finishes loading", which is the same fail-loud
-- discipline the rest of this project already applies to boot validation.
--
-- Assertions raise; the runner pcalls each case, so one failing case never
-- hides the rest of the suite.

local TestRunner = {}
TestRunner.__index = TestRunner

local Assert = {}

local function describe(value)
    if type(value) == "string" then
        return string.format("%q", value)
    end
    return tostring(value)
end

function Assert.equal(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s\n      expected: %s\n      actual:   %s",
            message or "values differ", describe(expected), describe(actual)), 2)
    end
end

function Assert.notEqual(actual, unexpected, message)
    if actual == unexpected then
        error(string.format("%s\n      expected anything but: %s",
            message or "values should differ", describe(unexpected)), 2)
    end
end

function Assert.isTrue(value, message)
    if value ~= true then
        error(string.format("%s\n      expected true, got %s",
            message or "expected true", describe(value)), 2)
    end
end

function Assert.isFalse(value, message)
    if value ~= false then
        error(string.format("%s\n      expected false, got %s",
            message or "expected false", describe(value)), 2)
    end
end

-- Float comparison. Added with the Spatial component, which is the first
-- thing here that interpolates -- `equal` on a lerped coordinate fails on
-- representation error rather than on being wrong.
function Assert.near(actual, expected, tolerance, message)
    if type(actual) ~= "number" then
        error(string.format("%s\n      expected a number, got %s",
            message or "expected a number", describe(actual)), 2)
    end
    if actual ~= actual or math.abs(actual - expected) > (tolerance or 0.001) then
        error(string.format("%s\n      expected: %s (+/- %s)\n      actual:   %s",
            message or "values differ", describe(expected),
            describe(tolerance or 0.001), describe(actual)), 2)
    end
end

function Assert.isNil(value, message)
    if value ~= nil then
        error(string.format("%s\n      expected nil, got %s",
            message or "expected nil", describe(value)), 2)
    end
end

function Assert.notNil(value, message)
    if value == nil then
        error(message or "expected a value, got nil", 2)
    end
end

function Assert.isType(value, expectedType, message)
    if type(value) ~= expectedType then
        error(string.format("%s\n      expected type %s, got %s",
            message or "wrong type", expectedType, type(value)), 2)
    end
end

-- Asserts fn raises. If `contains` is given, the message must include it --
-- otherwise a test can pass on an unrelated error, which is worse than no
-- test at all.
function Assert.throws(fn, contains, message)
    local ok, err = pcall(fn)
    if ok then
        error(message or "expected an error, but the call succeeded", 2)
    end
    if contains and not string.find(tostring(err), contains, 1, true) then
        error(string.format("%s\n      expected error containing: %s\n      actual error: %s",
            message or "wrong error", describe(contains), tostring(err)), 2)
    end
end

function Assert.noThrow(fn, message)
    local ok, err = pcall(fn)
    if not ok then
        error(string.format("%s\n      unexpected error: %s",
            message or "expected no error", tostring(err)), 2)
    end
end

-- Serialized payloads must be plain data all the way down: a metatable
-- anywhere means something will not survive a RemoteEvent.
function Assert.plainData(value, message, _seen)
    _seen = _seen or {}
    if type(value) ~= "table" then
        return
    end
    if getmetatable(value) ~= nil then
        error(string.format("%s\n      found a table with a metatable",
            message or "expected plain data"), 2)
    end
    if _seen[value] then
        return
    end
    _seen[value] = true
    for _, child in pairs(value) do
        Assert.plainData(child, message, _seen)
    end
end

function Assert.deepEqual(actual, expected, message, _path)
    _path = _path or "value"
    if type(actual) ~= type(expected) then
        error(string.format("%s\n      at %s: type %s vs %s",
            message or "values differ", _path, type(actual), type(expected)), 2)
    end
    if type(expected) ~= "table" then
        if actual ~= expected then
            error(string.format("%s\n      at %s: %s vs %s",
                message or "values differ", _path, describe(actual), describe(expected)), 2)
        end
        return
    end
    for key, expectedChild in pairs(expected) do
        Assert.deepEqual(actual[key], expectedChild, message, _path .. "." .. tostring(key))
    end
    for key in pairs(actual) do
        if expected[key] == nil then
            error(string.format("%s\n      at %s.%s: unexpected extra key",
                message or "values differ", _path, tostring(key)), 2)
        end
    end
end

function TestRunner.new(suiteName)
    return setmetatable({
        _name = suiteName,
        _cases = {},
    }, TestRunner)
end

function TestRunner:case(name, fn)
    table.insert(self._cases, { name = name, fn = fn })
end

function TestRunner:run()
    local result = {
        name = self._name,
        passed = 0,
        failed = 0,
        failures = {},
    }

    for _, case in ipairs(self._cases) do
        local ok, err = pcall(case.fn, Assert)
        if ok then
            result.passed += 1
        else
            result.failed += 1
            table.insert(result.failures, {
                name = case.name,
                message = tostring(err),
            })
        end
    end

    return result
end

return TestRunner
