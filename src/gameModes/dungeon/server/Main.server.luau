-- Main.server.luau

local serverRoot = game.ServerScriptService:WaitForChild("Server")

local RunTests = require(serverRoot:WaitForChild("tests"):WaitForChild("RunTests"))
local ServerManager = require(serverRoot:WaitForChild("globalManagers"):WaitForChild("ServerManager"))

-- Tests run BEFORE ServerManager, deliberately. SignalService.init() resets
-- module state, so the suite would otherwise wipe the live vocabulary and the
-- declared session facts. Running first also means a module that throws on
-- first use is reported before anything depends on it. See tests/RunTests.
RunTests.run()

local serverManager = ServerManager.new()
serverManager:init()

-- TEMPORARY: ten static dummies so hit detection has something to hit.
--
-- Called from here rather than left as its own Script because Roblox does not
-- order independent Scripts against each other. As a Script it sometimes ran
-- before RunTests, and its ten attached entities then showed up as candidates
-- inside the targeting suite -- a real failure with nothing wrong in the code
-- under test. Anything that MUTATES state the suite reads belongs after it,
-- in a place that says so.
local DummySpawner = require(serverRoot:WaitForChild("diagnostics"):WaitForChild("DummySpawner"))
DummySpawner.spawnAll()
